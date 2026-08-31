# frozen_string_literal: true

require 'activerecord-clean-db-structure/clean_dump'

RSpec.describe ActiveRecordCleanDbStructure::CleanDump do
  describe '#run' do
    let(:dump) do
      <<~STRUCTURE_SQL
        INSERT INTO "schema_migrations" (version) VALUES
        ('20220309184009'),
        ('20220309101143'),
        ('20220221045523'),
        ('20220202235304'),
        ;
      STRUCTURE_SQL
    end

    let(:options) { {} }

    subject { described_class.new(dump.dup, options) }

    it 'returns the cleaned dump' do
      expect(subject.run).to eq(subject.dump)
    end

    context 'when cleanup is disabled' do
      let(:options) { { enabled: false } }

      it 'returns the dump unchanged' do
        expect(subject.run).to eq(dump)
      end
    end

    context 'when run over its own output' do
      let(:dump) do
        <<~STRUCTURE_SQL
          --
          -- Name: things; Type: TABLE; Schema: waysact; Owner: -
          --

          CREATE TABLE waysact.things (
              id bigint NOT NULL,
              zebra text,
              alpha text
          );

          --
          -- Name: things things_pkey; Type: CONSTRAINT; Schema: waysact; Owner: -
          --

          ALTER TABLE ONLY waysact.things
              ADD CONSTRAINT things_pkey PRIMARY KEY (id);

          --
          -- Name: idx_things_alpha; Type: INDEX; Schema: waysact; Owner: -
          --

          CREATE INDEX idx_things_alpha ON waysact.things USING btree (alpha);

          INSERT INTO "schema_migrations" (version) VALUES
          ('20220309184009'),
          ('20220202235304');
        STRUCTURE_SQL
      end

      let(:options) do
        {
          indexes_after_tables: true,
          order_column_definitions: true,
          order_schema_migrations_values: true
        }
      end

      it 'is unchanged by a second pass' do
        first_pass = described_class.new(dump.dup, options).tap(&:run).dump
        second_pass = described_class.new(first_pass.dup, options).tap(&:run).dump

        expect(second_pass).to eq(first_pass)
      end
    end

    context 'when ordering schema migrations' do
      let(:options) { { order_schema_migrations_values: true } }
      it 'works' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          INSERT INTO "schema_migrations" (version) VALUES
           ('20220202235304')
          ,('20220221045523')
          ,('20220309101143')
          ,('20220309184009')
          ;
        STRUCTURE_SQL
      end
    end

    context 'when re-running over already cleaned schema migrations' do
      let(:options) { { order_schema_migrations_values: true } }

      it 'keeps every migration version' do
        first_pass = described_class.new(dump.dup, options).tap(&:run).dump
        second_pass = described_class.new(first_pass.dup, options).tap(&:run).dump

        expect(second_pass).to eq(first_pass)
      end
    end

    context 'when the schema_migrations INSERT has no values' do
      let(:dump) do
        <<~STRUCTURE_SQL
          INSERT INTO "schema_migrations" (version) VALUES
          ;
        STRUCTURE_SQL
      end

      let(:options) { { order_schema_migrations_values: true } }

      it 'raises instead of writing an empty list' do
        expect { subject.run }.to raise_error(described_class::NoSchemaMigrationValues)
      end
    end

    context 'when there is no schema_migrations INSERT' do
      let(:dump) { "CREATE TABLE waysact.things (\n    id BIGSERIAL\n);\n" }

      let(:options) { { order_schema_migrations_values: true } }

      it 'leaves the dump alone' do
        subject.run
        expect(subject.dump).to eq(dump)
      end
    end

    context 'when jumbling schema migrations' do
      let(:options) { { order_schema_migrations_values: :jumbled } }
      it 'works' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          INSERT INTO "schema_migrations" (version) VALUES
           ('20220309101143')
          ,('20220202235304')
          ,('20220221045523')
          ,('20220309184009')
          ;
        STRUCTURE_SQL
      end
    end

    context 'when reversing schema migrations' do
      let(:options) { { order_schema_migrations_values: :reversed } }
      it 'sorts by reversed migration ID' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          INSERT INTO "schema_migrations" (version) VALUES
           ('20220221045523')
          ,('20220309101143')
          ,('20220202235304')
          ,('20220309184009')
          ;
        STRUCTURE_SQL
      end
    end

    context 'when schemas_extensions_if_not_exists is enabled' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE SCHEMA waysact;

          CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA waysact;

          CREATE EXTENSION plrust WITH SCHEMA plrust;
        STRUCTURE_SQL
      end

      let(:options) { { schemas_extensions_if_not_exists: true } }

      it 'adds IF NOT EXISTS to CREATE SCHEMA' do
        subject.run
        expect(subject.dump).to include('CREATE SCHEMA IF NOT EXISTS waysact;')
        expect(subject.dump).not_to match(/^CREATE SCHEMA (?!IF)/)
      end

      it 'adds IF NOT EXISTS to CREATE EXTENSION' do
        subject.run
        expect(subject.dump).not_to match(/CREATE EXTENSION (?!IF)/)
      end
    end

    context 'when schemas_extensions_if_not_exists is not set' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE SCHEMA waysact;

          CREATE EXTENSION plrust WITH SCHEMA plrust;
        STRUCTURE_SQL
      end

      it 'leaves statements unchanged' do
        subject.run
        expect(subject.dump).to include('CREATE SCHEMA waysact;')
        expect(subject.dump).to include('CREATE EXTENSION plrust')
        expect(subject.dump).not_to include('IF NOT EXISTS')
      end
    end

    context 'when cleaning up sequences' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.things (
              id bigint NOT NULL
          );

          CREATE SEQUENCE waysact.things_id_seq
              START WITH 1
              INCREMENT BY 1
              NO MINVALUE
              NO MAXVALUE
              CACHE 1;

          ALTER TABLE waysact.things_id_seq OWNER TO waysact;

          ALTER SEQUENCE waysact.things_id_seq OWNED BY waysact.things.id;

          ALTER TABLE ONLY waysact.things ALTER COLUMN id SET DEFAULT nextval('waysact.things_id_seq'::regclass);
        STRUCTURE_SQL
      end

      it 'removes the sequence OWNER TO statement' do
        subject.run
        expect(subject.dump).not_to include('things_id_seq')
      end
    end

    context 'when moving primary keys into the table definition' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.things (
              id bigint NOT NULL,
              name text
          );

          --
          -- Name: things things_pkey; Type: CONSTRAINT; Schema: waysact; Owner: -
          --

          ALTER TABLE ONLY waysact.things
              ADD CONSTRAINT things_pkey PRIMARY KEY (id);
        STRUCTURE_SQL
      end

      it 'inlines the primary key on the id column' do
        subject.run
        expect(subject.dump).to include('id BIGSERIAL PRIMARY KEY')
      end

      it 'removes the separate ADD CONSTRAINT statement' do
        subject.run
        expect(subject.dump).not_to include('ADD CONSTRAINT things_pkey')
      end
    end

    context 'when moving unique constraints into the table definition' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.things (
              id BIGSERIAL,
              email text
          );

          --
          -- Name: things things_email_key; Type: CONSTRAINT; Schema: waysact; Owner: -
          --

          ALTER TABLE ONLY waysact.things
              ADD CONSTRAINT things_email_key UNIQUE (email);
        STRUCTURE_SQL
      end

      let(:options) { { move_unique_constraints_to_tables: true } }

      it 'inlines the unique constraint' do
        subject.run
        expect(subject.dump).to include('CONSTRAINT things_email_key UNIQUE (email)')
      end

      it 'removes the separate ADD CONSTRAINT statement' do
        subject.run
        expect(subject.dump).not_to include('ALTER TABLE ONLY waysact.things')
      end
    end

    context 'when moving unique constraints into a table with a WITH clause' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.things (
              id BIGSERIAL,
              email text
          )
          WITH (fillfactor='85');

          --
          -- Name: things things_email_key; Type: CONSTRAINT; Schema: waysact; Owner: -
          --

          ALTER TABLE ONLY waysact.things
              ADD CONSTRAINT things_email_key UNIQUE (email);
        STRUCTURE_SQL
      end

      let(:options) { { move_unique_constraints_to_tables: true } }

      it 'keeps the unique constraint' do
        expect(subject.tap(&:run).dump).to include('CONSTRAINT things_email_key UNIQUE (email)')
      end
    end

    context 'when removing partitioned tables' do
      let(:dump) do
        <<~STRUCTURE_SQL
          --
          -- Name: events; Type: TABLE; Schema: waysact; Owner: -
          --

          CREATE TABLE waysact.events (
              id bigint NOT NULL
          )
          PARTITION BY RANGE (id);

          --
          -- Name: events_p2024; Type: TABLE; Schema: waysact; Owner: -
          --

          CREATE TABLE waysact.events_p2024 (
              id bigint NOT NULL
          );

          ALTER TABLE ONLY waysact.events ATTACH PARTITION waysact.events_p2024 FOR VALUES FROM (1) TO (100);

          --
          -- Name: idx_events_p2024_id; Type: INDEX; Schema: waysact; Owner: -
          --

          CREATE INDEX idx_events_p2024_id ON waysact.events_p2024 USING btree (id);

          ALTER TABLE waysact.events_p2024 OWNER TO waysact;

          --
          -- Name: events_p2024 events_p2024_pkey; Type: CONSTRAINT; Schema: waysact; Owner: -
          --

          --
          -- Name: events_p2024_pkey; Type: INDEX ATTACH; Schema: waysact; Owner: -
          --

          ALTER INDEX waysact.events_pkey ATTACH PARTITION waysact.events_p2024_pkey;

          --
          -- Name: TABLE events_p2024; Type: COMMENT; Schema: waysact; Owner: -
          --

          COMMENT ON TABLE waysact.events_p2024 IS 'A partition for 2024 data';

          --
          -- Name: events_p2024_stats; Type: STATISTICS; Schema: waysact; Owner: -
          --

          CREATE STATISTICS waysact.events_p2024_stats ON id FROM waysact.events_p2024;

          ALTER STATISTICS waysact.events_p2024_stats OWNER TO waysact;
        STRUCTURE_SQL
      end

      it 'does not leave orphaned comment suffixes as bare SQL' do
        subject.run
        expect(subject.dump).not_to match(/^; Schema:/)
      end

      it 'removes all references to the partition' do
        subject.run
        expect(subject.dump).not_to include('events_p2024')
      end
    end

    context 'when removing inherited tables' do
      let(:dump) do
        <<~STRUCTURE_SQL
          --
          -- Name: parent; Type: TABLE; Schema: waysact; Owner: -
          --

          CREATE TABLE waysact.parent (
              id bigint NOT NULL
          );

          --
          -- Name: child; Type: TABLE; Schema: waysact; Owner: -
          --

          CREATE TABLE waysact.child (
              id bigint NOT NULL
          )
          INHERITS (waysact.parent);

          --
          -- Name: idx_child_id; Type: INDEX; Schema: waysact; Owner: -
          --

          CREATE INDEX idx_child_id ON waysact.child USING btree (id);
        STRUCTURE_SQL
      end

      it 'does not leave orphaned comment suffixes as bare SQL' do
        subject.run
        expect(subject.dump).not_to match(/^; Schema:/)
      end

      it 'removes the inherited table and its index' do
        subject.run
        expect(subject.dump).not_to include('child')
      end

      it 'keeps the parent table' do
        subject.run
        expect(subject.dump).to include('CREATE TABLE waysact.parent')
      end
    end

    context 'when ordering column definitions with multiline constraints' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              id bigint NOT NULL,
              call_uuid uuid NOT NULL,
              event_type text NOT NULL,
              payload jsonb,
              CONSTRAINT call_events_valid CHECK (
          CASE
              WHEN (event_type = 'initiated'::text) THEN validate_json_schema('{"required": ["CallSid"],
          event_type text NOT NULL,
          next_states text[]}'::jsonb, payload)
              ELSE false
          END)
          );
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'keeps the constraint body intact' do
        subject.run
        expect(subject.dump).to include(
          %{validate_json_schema('{"required": ["CallSid"],\nevent_type text NOT NULL,\nnext_states text[]}'::jsonb, payload)}
        )
      end
    end

    context 'when ordering column definitions with WITH clause' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              name text NOT NULL,
              id bigint NOT NULL
          )
          WITH (fillfactor='85');

          CREATE TABLE waysact.other (
              id bigint NOT NULL,
              value text
          );
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'does not move columns between tables' do
        subject.run
        expect(subject.dump).to include('call_events')
        expect(subject.dump).to include('name text NOT NULL')
        # name must remain inside call_events, not move to other
        other_block = subject.dump[/CREATE TABLE waysact\.other \(.*?\);/m]
        expect(other_block).not_to include('name')
      end
    end

    context 'when ordering column definitions of a table with a USING clause' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.aaa (
              zebra text,
              alpha text
          )
          USING heap;

          CREATE TABLE waysact.bbb (
              yankee text,
              bravo text
          );
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'does not move columns between tables' do
        other_block = subject.tap(&:run).dump[/CREATE TABLE waysact\.bbb \(.*?\);/m]
        expect(other_block).not_to include('zebra')
      end

      it 'sorts the columns of the table itself' do
        expect(subject.tap(&:run).dump).to include("    alpha text,\n    zebra text\n)\nUSING heap;")
      end
    end

    context 'when ordering column definitions of an unlogged table' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE UNLOGGED TABLE waysact.cache (
              zebra text,
              alpha text
          );
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'sorts the columns' do
        expect(subject.tap(&:run).dump).to include("    alpha text,\n    zebra text\n);")
      end
    end

    context 'when sorting indexes of an unlogged table' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE UNLOGGED TABLE waysact.cache (
              id BIGSERIAL
          );

          CREATE INDEX idx_cache ON waysact.cache USING btree (id);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'keeps the index' do
        expect(subject.tap(&:run).dump).to include('CREATE INDEX idx_cache ON waysact.cache USING btree (id);')
      end
    end

    context 'when ordering column definitions of a table with comments' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              zebra text,
              alpha text,
              "timestamp" timestamp without time zone
          );

          --
          -- Name: COLUMN call_events.zebra; Type: COMMENT; Schema: waysact; Owner: -
          --

          COMMENT ON COLUMN waysact.call_events.zebra IS 'The zebra.';

          --
          -- Name: COLUMN call_events."timestamp"; Type: COMMENT; Schema: waysact; Owner: -
          --

          COMMENT ON COLUMN waysact.call_events."timestamp" IS 'The timestamp.';

          --
          -- Name: COLUMN call_events.alpha; Type: COMMENT; Schema: waysact; Owner: -
          --

          COMMENT ON COLUMN waysact.call_events.alpha IS 'The alpha.';
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'orders the comments the same way as the columns' do
        commented = subject.tap(&:run).dump.scan(/^COMMENT ON COLUMN \S+\.(\S+) IS/).flatten
        expect(commented).to eq(['alpha', '"timestamp"', 'zebra'])
      end

      it 'keeps each comment with its own column' do
        subject.run
        expect(subject.dump).to include(%{COMMENT ON COLUMN waysact.call_events.alpha IS 'The alpha.';})
        expect(subject.dump).to include(%{COMMENT ON COLUMN waysact.call_events."timestamp" IS 'The timestamp.';})
      end

      it 'is unchanged by a second pass' do
        first_pass = described_class.new(dump.dup, options).tap(&:run).dump
        second_pass = described_class.new(first_pass.dup, options).tap(&:run).dump

        expect(second_pass).to eq(first_pass)
      end
    end

    context 'when a column comment spans several lines' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              zebra text,
              alpha text
          );

          COMMENT ON COLUMN waysact.call_events.zebra IS 'The time at which it happened.
          This is distinct from received_at, and it isn''t always set.';

          COMMENT ON COLUMN waysact.call_events.alpha IS 'The alpha.';
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'moves the whole statement' do
        subject.run
        expect(subject.dump).to include(
          "COMMENT ON COLUMN waysact.call_events.zebra IS 'The time at which it happened.\n" \
          "This is distinct from received_at, and it isn''t always set.';"
        )
      end

      it 'still sorts it after the alpha comment' do
        commented = subject.tap(&:run).dump.scan(/^COMMENT ON COLUMN \S+\.(\S+) IS/).flatten
        expect(commented).to eq(%w[alpha zebra])
      end
    end

    context 'when two tables both have column comments' do
      let(:dump) do
        <<~STRUCTURE_SQL
          COMMENT ON COLUMN waysact.aaa.zebra IS 'aaa zebra.';

          COMMENT ON COLUMN waysact.aaa.alpha IS 'aaa alpha.';

          COMMENT ON COLUMN waysact.bbb.yankee IS 'bbb yankee.';

          COMMENT ON COLUMN waysact.bbb.bravo IS 'bbb bravo.';
        STRUCTURE_SQL
      end

      let(:options) { { order_column_definitions: true } }

      it 'sorts within each table without mixing them' do
        commented = subject.tap(&:run).dump.scan(/^COMMENT ON COLUMN (\S+) IS/).flatten
        expect(commented).to eq(
          %w[waysact.aaa.alpha waysact.aaa.zebra waysact.bbb.bravo waysact.bbb.yankee]
        )
      end
    end

    context 'when column definitions are not ordered' do
      let(:dump) do
        <<~STRUCTURE_SQL
          COMMENT ON COLUMN waysact.aaa.zebra IS 'The zebra.';

          COMMENT ON COLUMN waysact.aaa.alpha IS 'The alpha.';
        STRUCTURE_SQL
      end

      it 'leaves the comments in the order pg_dump wrote them' do
        commented = subject.tap(&:run).dump.scan(/^COMMENT ON COLUMN \S+\.(\S+) IS/).flatten
        expect(commented).to eq(%w[zebra alpha])
      end
    end

    context 'when sorting indexes' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              id BIGSERIAL
          );

          CREATE TABLE waysact.other (
              id BIGSERIAL
          );

          CREATE INDEX foo ON waysact.call_events (id);

          CREATE INDEX "bar" ON waysact.call_events (id);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'works' do
        subject.run
        expect(subject.dump).to eq(<<~STRUCTURE_SQL)
          CREATE TABLE waysact.call_events (
              id BIGSERIAL
          );

          CREATE INDEX foo ON waysact.call_events (id);
          CREATE INDEX "bar" ON waysact.call_events (id);

          CREATE TABLE waysact.other (
              id BIGSERIAL
          );
        STRUCTURE_SQL
      end
    end

    context 'when sorting indexes whose names need quoting' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.users (
              id BIGSERIAL
          );

          --
          -- Name: users email idx; Type: INDEX; Schema: waysact; Owner: -
          --

          CREATE INDEX "users email idx" ON waysact.users USING btree (email);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'moves the index rather than duplicating it' do
        subject.run
        expect(subject.dump.scan('CREATE INDEX "users email idx"').size).to eq(1)
      end

      it 'removes the index comment' do
        subject.run
        expect(subject.dump).not_to include('Type: INDEX')
      end
    end

    context 'when sorting indexes whose names contain a dot' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.users (
              id BIGSERIAL
          );

          CREATE INDEX "idx.foo" ON waysact.users USING btree (email);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'keeps the index' do
        subject.run
        expect(subject.dump).to include('CREATE INDEX "idx.foo" ON waysact.users USING btree (email);')
      end
    end

    context 'when sorting indexes on tables without a schema prefix' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.users (
              id BIGSERIAL
          );

          CREATE TABLE users (
              id BIGSERIAL
          );

          CREATE INDEX idx_foo ON users USING btree (email);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'places the index after its own table only' do
        subject.run
        expect(subject.dump.scan('CREATE INDEX idx_foo').size).to eq(1)
      end
    end

    context 'when a table name is a wildcard match for another' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.users (
              id BIGSERIAL
          );

          CREATE TABLE waysactxusers (
              id BIGSERIAL
          );

          CREATE INDEX idx_foo ON waysact.users USING btree (email);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'places the index after the matching table only' do
        subject.run
        expect(subject.dump.scan('CREATE INDEX idx_foo').size).to eq(1)
      end
    end

    context 'when an index is declared ON ONLY a partitioned parent' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.events (
              id BIGSERIAL
          )
          PARTITION BY RANGE (id);

          CREATE INDEX idx_events ON ONLY waysact.events USING btree (id);

          CREATE INDEX "events idx" ON ONLY waysact.events USING btree (id);
        STRUCTURE_SQL
      end

      it 'drops ONLY regardless of how the index name is spelled' do
        subject.run
        expect(subject.dump).not_to include('ON ONLY')
      end
    end

    context 'when indexes have comments' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.users (
              id BIGSERIAL
          );

          CREATE TABLE waysact.other (
              id BIGSERIAL
          );

          --
          -- Name: idx_users_email; Type: INDEX; Schema: waysact; Owner: -
          --

          CREATE INDEX idx_users_email ON waysact.users USING btree (email);

          --
          -- Name: idx_users_name; Type: INDEX; Schema: waysact; Owner: -
          --

          CREATE INDEX idx_users_name ON waysact.users USING btree (name);

          --
          -- Name: INDEX idx_users_email; Type: COMMENT; Schema: waysact; Owner: -
          --

          COMMENT ON INDEX waysact.idx_users_email IS 'Used to find a user''s address, perhaps
          filtered to only the verified ones.';
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'puts the comment directly after the index it describes' do
        subject.run
        expect(subject.dump).to include(
          "CREATE INDEX idx_users_email ON waysact.users USING btree (email);\n" \
          "COMMENT ON INDEX waysact.idx_users_email IS 'Used to find a user''s address, perhaps\n" \
          "filtered to only the verified ones.';\n"
        )
      end

      it 'keeps the comment only once' do
        subject.run
        expect(subject.dump.scan('COMMENT ON INDEX').size).to eq(1)
      end

      it 'still places the uncommented index with its table' do
        subject.run
        users = subject.dump[/CREATE TABLE waysact\.users .*?(?=CREATE TABLE|\z)/m]
        expect(users).to include('CREATE INDEX idx_users_name')
      end

      it 'is unchanged by a second pass' do
        first_pass = described_class.new(dump.dup, options).tap(&:run).dump
        second_pass = described_class.new(first_pass.dup, options).tap(&:run).dump

        expect(second_pass).to eq(first_pass)
      end
    end

    context 'when an index comment has no matching index' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.users (
              id BIGSERIAL
          );

          COMMENT ON INDEX waysact.idx_that_went_away IS 'Orphaned.';
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'leaves the comment alone rather than dropping it' do
        subject.run
        expect(subject.dump).to include("COMMENT ON INDEX waysact.idx_that_went_away IS 'Orphaned.';")
      end
    end

    context 'when sorting indexes with WITH clause on table' do
      let(:dump) do
        <<~STRUCTURE_SQL
          CREATE TABLE waysact.call_events (
              id BIGSERIAL
          )
          WITH (fillfactor='85');

          CREATE INDEX foo ON waysact.call_events (id);
        STRUCTURE_SQL
      end

      let(:options) { { indexes_after_tables: true } }

      it 'places indexes after the table' do
        subject.run
        expect(subject.dump).to include("WITH (fillfactor='85');")
        expect(subject.dump).to include('CREATE INDEX foo ON waysact.call_events (id);')
      end
    end
  end
end
