require 'English'
require 'digest'

module ActiveRecordCleanDbStructure
  class CleanDump
    # Raised when an INSERT INTO "schema_migrations" statement is present but
    # holds no readable version values.
    class NoSchemaMigrationValues < StandardError; end

    # The body of the schema_migrations INSERT statement, up to and including
    # its terminating semicolon.
    SCHEMA_MIGRATIONS_VALUES_REGEXP =
      /(?<=INSERT INTO "schema_migrations" \(version\) VALUES)(?<values>.+?;)\n*/m

    # A single migration version, in raw pg_dump form ("('...')," per line) as
    # well as in the form written by a previous run (",('...')" per line), so
    # that running the cleaner over its own output is a no-op.
    SCHEMA_MIGRATION_VALUE_REGEXP = /^[ ,]?(\('\d{14}'\))[,;]?$/

    # A single CREATE INDEX statement. The same pattern collects and removes
    # them, so the two can never disagree and leave a duplicate behind.
    INDEX_STATEMENT_REGEXP = /^CREATE.+INDEX.+ON.+\n/

    # The pg_dump comment that precedes a CREATE INDEX statement. The index
    # name is not restricted to word characters, because pg_dump does not
    # restrict it either.
    INDEX_COMMENT_REGEXP = /^-- Name: [^;\n]+; Type: INDEX\n+/

    # The table a CREATE INDEX statement applies to. Taken from the ON clause,
    # because the index name may itself contain a dot.
    INDEX_TABLE_REGEXP = / ON (?:ONLY )?([^\s(]+)/

    # The opening keywords of a CREATE TABLE statement. pg_dump writes
    # "CREATE UNLOGGED TABLE" for unlogged tables.
    CREATE_TABLE_REGEXP = /CREATE (?:UNLOGGED )?TABLE/

    # Everything pg_dump may put between the closing parenthesis of a column
    # list and the terminating semicolon: PARTITION BY, WITH, USING, INHERITS,
    # SERVER, TABLESPACE, and whatever a later Postgres adds.
    TABLE_SUFFIX_REGEXP = /\n\)[^;]*;$/

    attr_reader :dump, :options

    def initialize(dump, options = {})
      @dump = dump
      @options = options
    end

    def run
      return dump unless options.fetch(:enabled, true)

      # Remove trailing whitespace
      dump.gsub!(/[ \t]+$/, '')

      if options[:schemas_extensions_if_not_exists]
        dump.gsub!(/^CREATE SCHEMA (?!IF NOT EXISTS)/, 'CREATE SCHEMA IF NOT EXISTS ')
        dump.gsub!(/^CREATE EXTENSION (?!IF NOT EXISTS)/, 'CREATE EXTENSION IF NOT EXISTS ')
      end

      # Remove version-specific output
      dump.gsub!(/^-- Dumped.*/, '')
      dump.gsub!(/^SET row_security = off;\n/m, '') # 9.5
      dump.gsub!(/^SET idle_in_transaction_session_timeout = 0;\n/m, '') # 9.6
      dump.gsub!(/^SET default_with_oids = false;\n/m, '') # all older than 12
      dump.gsub!(/^SET xmloption = content;\n/m, '') # 12
      dump.gsub!(/^SET default_table_access_method = heap;\n/m, '') # 12

      # Remove pg_stat_statements extension (its not relevant to the code)
      dump.gsub!(/^CREATE EXTENSION IF NOT EXISTS pg_stat_statements.*/, '')
      dump.gsub!(/^-- Name: (EXTENSION )?pg_stat_statements;.*/, '')

      # Remove pg_buffercache extension (its not relevant to the code)
      dump.gsub!(/^CREATE EXTENSION IF NOT EXISTS pg_buffercache.*/, '')
      dump.gsub!(/^-- Name: (EXTENSION )?pg_buffercache;.*/, '')

      # Remove comments on extensions, they create problems if the extension is owned by another user
      dump.gsub!(/^COMMENT ON EXTENSION .*/, '')

      # Remove useless, version-specific parts of comments
      dump.gsub!(/^-- (.*); Schema: ([\w_\.]+|-); Owner: -.*/, '-- \1')

      # Remove useless comment lines
      dump.gsub!(/^--$/, '')

      # Reduce noise for id fields by making them (BIG)SERIAL instead of integer+sequence stuff
      unless options[:ignore_ids] == true
        sequences_cleanup
        primary_keys_cleanup
      end

      # Remove inherited tables
      inherited_tables_regexp = /-- Name: ([\w_\.]+); Type: TABLE\n\n[^;]+?INHERITS \([\w_\.]+\);/m
      inherited_tables = dump.scan(inherited_tables_regexp).map(&:first)
      dump.gsub!(inherited_tables_regexp, '')
      inherited_tables.each do |inherited_table_name|
        inherited_table = Regexp.escape(inherited_table_name)
        dump.gsub!(/ALTER TABLE ONLY ([\w_]+\.)?#{inherited_table}[^;]+;/, '')

        index_regexp = /CREATE INDEX ([\w_]+) ON ([\w_]+\.)?#{inherited_table}[^;]+;/m
        dump.scan(index_regexp).map(&:first).each do |inherited_table_index|
          dump.gsub!(/-- Name: #{Regexp.escape(inherited_table_index)}; Type: INDEX.*/, '')
        end
        dump.gsub!(index_regexp, '')
      end

      # Remove partitioned tables
      partitioned_tables = []

      # Postgres 12 pg_dump will output separate ATTACH PARTITION statements (even when run against an 11 or older server)
      partitioned_tables_regexp1 = /ALTER TABLE ONLY [\w_\.]+ ATTACH PARTITION ([\w_\.]+)/
      partitioned_tables += dump.scan(partitioned_tables_regexp1).map(&:last)

      # Earlier versions use an inline PARTITION OF
      partitioned_tables_regexp2 = /-- Name: ([\w_\.]+); Type: TABLE\n\n[^;]+?PARTITION OF [\w_\.]+\n[^;]+?;/m
      partitioned_tables += dump.scan(partitioned_tables_regexp2).map(&:first)

      partitioned_tables.each do |partitioned_table_name|
        partitioned_table = Regexp.escape(partitioned_table_name)
        partitioned_table_name_only = Regexp.escape(partitioned_table_name.split('.').last)
        dump.gsub!(/-- Name: #{partitioned_table_name_only}; Type: TABLE(?: ATTACH)?.*/, '')
        dump.gsub!(/CREATE TABLE #{partitioned_table} \([^;]+;/m, '')
        dump.gsub!(/ALTER TABLE ONLY ([\w_\.]+) ATTACH PARTITION #{partitioned_table}[^;]+;/m, '')

        dump.gsub!(/ALTER TABLE ONLY ([\w_]+\.)?#{partitioned_table}[^;]+;/, '')
        dump.gsub!(/ALTER TABLE ([\w_]+\.)?#{partitioned_table} OWNER TO [^;]+;/, '')
        dump.gsub!(/-- Name: #{partitioned_table} [^;]+; Type: DEFAULT.*/, '')
        dump.gsub!(/-- Name: #{partitioned_table_name_only} [^;]+; Type: CONSTRAINT.*/, '')

        index_regexp = /CREATE (UNIQUE )?INDEX ([\w_]+) ON ([\w_]+\.)?#{partitioned_table}[^;]+;/m
        dump.scan(index_regexp).each do |m|
          partitioned_table_index = Regexp.escape(m[1])
          dump.gsub!(/-- Name: #{partitioned_table_index}; Type: INDEX ATTACH.*/, '')
          dump.gsub!(/-- Name: #{partitioned_table_index}; Type: INDEX.*/, '')
          dump.gsub!(/ALTER INDEX ([\w_\.]+) ATTACH PARTITION ([\w_]+\.)?#{partitioned_table_index};/, '')
        end
        dump.gsub!(index_regexp, '')

        dump.gsub!(/-- Name: ([\w_]+\.)?#{partitioned_table_name_only}_pkey; Type: INDEX ATTACH.*\n\n[^;]+?ATTACH PARTITION ([\w_]+\.)?#{partitioned_table}_pkey;/, '')

        dump.gsub!(/-- Name: TABLE ([\w_]+\.)?#{partitioned_table_name_only}; Type: COMMENT.*\n\s*\nCOMMENT ON TABLE ([\w_]+\.)?#{partitioned_table_name_only} IS '(?:[^']|\n|'')*';/m, '');

        stats_regexp = /-- Name: [^;]+; Type: STATISTICS.*\n\s*\nCREATE STATISTICS ([\w_\.]+) .*? FROM ([\w_]+\.)?#{partitioned_table_name_only};/m
        dump.scan(stats_regexp).each do |m|
          dump.gsub!(/ALTER STATISTICS #{Regexp.escape(m[0])} OWNER TO [^;]+;/, '')
        end
        dump.gsub!(stats_regexp, '');
      end
      # This is mostly done to allow restoring Postgres 11 output on Postgres 10
      dump.gsub!(/^(CREATE(?: UNIQUE)? INDEX .+?) ON ONLY /, '\\1 ON ')

      if options[:order_schema_migrations_values]
        schema_migrations_cleanup
      else
        # Remove whitespace between schema migration INSERTS to make editing easier
        dump.gsub!(/^(INSERT INTO schema_migrations .*)\n\n/, "\\1\n")
      end

      if options[:indexes_after_tables] == true
        # Extract indexes, remove comments and place them just after the respective tables
        indexes =
          dump
            .scan(INDEX_STATEMENT_REGEXP)
            .group_by { |line| line[INDEX_TABLE_REGEXP, 1] }
            .transform_values(&:join)

        dump.gsub!(/#{INDEX_STATEMENT_REGEXP}\n*/, '')
        dump.gsub!(INDEX_COMMENT_REGEXP, '')
        indexes.each do |table, indexes_for_table|
          dump.gsub!(/^(#{CREATE_TABLE_REGEXP} #{Regexp.escape(table)}\b(?:[^;\n]*\n)+\)[^;]*;\n)/) { $1 + "\n" + indexes_for_table }
        end
      end

      move_unique_constraints if options[:move_unique_constraints_to_tables] == true
      order_column_definitions if options[:order_column_definitions] == true

      # Reduce 2+ lines of whitespace to one line of whitespace
      dump.gsub!(/\n{2,}/m, "\n\n")
      # Removing comments leaves blank lines behind at the top of the file
      dump.sub!(/\A\n+/, '')
      # End the file with a single end-of-line character
      dump.sub!(/\n*\z/m, "\n")

      dump
    end

    private

    # Orders the columns definitions alphabetically
    # - ignores quotes which surround column names that are equal to reserved PostgreSQL names.
    # - keeps the columns at the top and places the constraints at the bottom.
    def order_column_definitions
      dump.gsub!(/^(?<table>#{CREATE_TABLE_REGEXP} .+?\(\n)(?<columns>.+?)(?=#{TABLE_SUFFIX_REGEXP})/m) do
        table = $~[:table]
        columns =
          split_column_definitions($~[:columns])
          .sort_by { |column| column.delete('"') }
          .partition { |column| !column.match?(/\A *CONSTRAINT/) }
          .flatten
          .join(",\n")

        [table, columns].join
      end
    end

    # Splits column definitions on ",\n" only at parenthesis depth 0,
    # respecting single-quoted strings (which may contain parentheses).
    def split_column_definitions(text)
      parts = []
      current = +""
      depth = 0
      in_string = false
      i = 0

      while i < text.length
        char = text[i]

        if in_string
          if char == "'" && text[i + 1] == "'"
            current << "''"
            i += 2
            next
          elsif char == "'"
            in_string = false
          end
          current << char
        else
          if char == "'"
            in_string = true
            current << char
          elsif char == "("
            depth += 1
            current << char
          elsif char == ")"
            depth -= 1
            current << char
          elsif char == "," && text[i + 1] == "\n" && depth == 0
            parts << current
            current = +""
            i += 2
            next
          else
            current << char
          end
        end

        i += 1
      end

      parts << current unless current.empty?
      parts
    end

    # Reduce noise for id fields by making them (BIG)SERIAL instead of integer+sequence stuff
    #
    # WARN: might add the (BIG)SERIAL property to columns for which no sequence was originally defined.
    # NOTE: does not work work for columns with a name other than 'id'
    # NOTE: does not work for SMALLSERIAL
    def sequences_cleanup
      dump.gsub!(/^    id integer NOT NULL(,)?$/, '    id SERIAL\1')
      dump.gsub!(/^    id bigint NOT NULL(,)?$/, '    id BIGSERIAL\1')
      dump.gsub!(/^CREATE SEQUENCE [\w\.]+_id_seq\s+(AS integer\s+)?START WITH 1\s+INCREMENT BY 1\s+NO MINVALUE\s+NO MAXVALUE\s+CACHE 1;$/, '')
      dump.gsub!(/^ALTER SEQUENCE [\w\.]+_id_seq OWNED BY .*;$/, '')
      dump.gsub!(/^ALTER TABLE [\w\.]+_id_seq OWNER TO .*;$/, '')
      dump.gsub!(/^ALTER TABLE ONLY [\w\.]+ ALTER COLUMN id SET DEFAULT nextval\('[\w\.]+_id_seq'::regclass\);$/, '')
      dump.gsub!(/^-- Name: (\w+\s+)?id; Type: DEFAULT$/, '')
      dump.gsub!(/^-- .*_id_seq; Type: SEQUENCE.*/, '')
    end

    # Moves the separate primary key statements to the create table statements.
    def primary_keys_cleanup
      primary_keys = []

      # Removes the ADD CONSTRAINT statements for primary keys and stores the info of which statements have been removed.
      dump.gsub!(/^-- Name: [\w\s]+?(?<name>\w+_pkey); Type: CONSTRAINT[\s-]+ALTER TABLE ONLY (?<table>[\w.]+)\s+ADD CONSTRAINT \k<name> PRIMARY KEY \((?<column>[^,\)]+)\);$/) do
        primary_keys.push([$LAST_MATCH_INFO[:table], $LAST_MATCH_INFO[:column]])

        ''
      end

      # Adds the PRIMARY KEY property to each column for which it's statement has just been removed.
      primary_keys.each do |table, column|
        dump.gsub!(/^(?<statement>#{CREATE_TABLE_REGEXP} #{Regexp.escape(table)} \(.*?\s+#{Regexp.escape(column)}\s+[^,\n]+)/m) do
          "#{$LAST_MATCH_INFO[:statement].sub(/ NOT NULL\z/, '')} PRIMARY KEY"
        end
      end
    end

    # Moves the separate unique constraint statements to the create table statements.
    def move_unique_constraints
      unique_constraints = []

      # Removes the ADD CONSTRAINT statements and stores their info.
      dump.gsub!(/^-- Name: [\w\s]+?(?<name>\w+); Type: CONSTRAINT[\s-]+ALTER TABLE ONLY (?<table>[\w.]+)\s+ADD CONSTRAINT \k<name> UNIQUE (?<columns>[^;]+);$/) do
        unique_constraints.push([$LAST_MATCH_INFO[:table], $LAST_MATCH_INFO[:name], $LAST_MATCH_INFO[:columns]])

        ''
      end

      # Adds the UNIQUE contstraint to the table definitions.
      unique_constraints.each do |table, name, columns|
        dump.gsub!(/^#{CREATE_TABLE_REGEXP} #{Regexp.escape(table)} \(.*?#{TABLE_SUFFIX_REGEXP}/m) do |statement|
          constraint = "CONSTRAINT #{name} UNIQUE #{columns}"
          statement.sub(/\n\)/, ",\n    #{constraint}\n)")
        end
      end
    end

    # Cleanup of schema_migrations values to prevent merge conflicts:
    # - sorts all values chronological, or randomly if
    #   order_schema_migrations_values is set to :jumbled
    # - places the comma's in front of each value (except for the first)
    # - places the semicolon on a separate last line
    def schema_migrations_cleanup
      # Read all schema_migrations values from the dump. Only the body of the
      # INSERT statement is examined, so that values are never picked up from
      # elsewhere in the dump.
      body = dump[SCHEMA_MIGRATIONS_VALUES_REGEXP, :values]
      return if body.nil?

      values = body.scan(SCHEMA_MIGRATION_VALUE_REGEXP).flatten.sort

      # An INSERT statement without readable values means the format changed.
      # Writing the dump back out would drop every migration version, so stop.
      if values.empty?
        raise NoSchemaMigrationValues,
              'Found a schema_migrations INSERT statement but no version ' \
              'values in it. Refusing to write an empty version list.'
      end

      if options[:order_schema_migrations_values] == :jumbled
        values.sort_by! { |v| [::Digest::SHA2.hexdigest(v[2...-2]), v].join }
      elsif options[:order_schema_migrations_values] == :reversed
        values.sort_by! { |v| v[2...-2].reverse }
      end

      # Replace the schema_migrations values.
      dump.sub!(SCHEMA_MIGRATIONS_VALUES_REGEXP, "\n #{values.join("\n,")}\n;\n\n")
    end
  end
end
