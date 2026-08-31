# frozen_string_literal: true

require 'rails'
require 'active_record'
require 'rake'
require 'tmpdir'

# Exercises the rake task against the Rails version the consuming application
# runs. No database is needed: the task only enhances db:schema:dump, so a stub
# base task standing in for pg_dump is enough.
RSpec.describe 'clean_db_structure.rake' do
  RAW_PG_DUMP = <<~STRUCTURE_SQL
    -- Dumped from database version 14.5

    CREATE TABLE waysact.things (
        id bigint NOT NULL
    );

    INSERT INTO "schema_migrations" (version) VALUES
    ('20220309184009'),
    ('20220202235304');
  STRUCTURE_SQL

  attr_reader :db_dir

  around do |example|
    Dir.mktmpdir { |dir| @db_dir = dir and example.run }
  end

  let(:options) { ActiveSupport::OrderedOptions.new }

  let(:databases) do
    { 'test' => { 'primary' => { 'adapter' => 'postgresql', 'database' => 'app_test' } } }
  end

  # The files Rails itself would write for this configuration.
  let(:dumped_files) do
    ActiveRecord::DatabaseConfigurations.new(databases)
                                        .configs_for(env_name: 'test')
                                        .select(&:database_tasks?)
                                        .filter_map { |c| ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(c) }
  end

  let(:rails_application) do
    config = Struct.new(:paths, :activerecord_clean_db_structure, :load_database_yaml)
                   .new({ 'db' => [db_dir] }, options, databases)
    Struct.new(:config).new(config)
  end

  around do |example|
    previous = ActiveRecord.schema_format
    # The application this gem serves dumps SQL, not schema.rb.
    ActiveRecord.schema_format = :sql
    example.run
  ensure
    ActiveRecord.schema_format = previous
  end

  before do
    Rake.application = Rake::Application.new
    ActiveRecord::Tasks::DatabaseTasks.db_dir = db_dir
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
    allow(Rails).to receive(:application).and_return(rails_application)

    # Stands in for the real dump: writes raw pg_dump output where Rails would.
    files = dumped_files
    Rake::Task.define_task('db:schema:dump') do
      files.each { |file| File.write(file, RAW_PG_DUMP) }
    end
    load 'activerecord-clean-db-structure/tasks/clean_db_structure.rake'
  end

  def dump
    Rake::Task['db:schema:dump'].invoke
  end

  def contents(basename)
    File.read(File.join(db_dir, basename))
  end

  context 'with a single database' do
    it 'cleans the dumped file' do
      dump
      expect(contents('structure.sql')).to include('id BIGSERIAL')
    end

    it 'applies the configured options' do
      options.order_schema_migrations_values = true
      dump
      expect(contents('structure.sql')).to include("\n ('20220202235304')\n,('20220309184009')\n;")
    end
  end

  context 'with several databases' do
    let(:databases) do
      { 'test' => {
        'primary' => { 'adapter' => 'postgresql', 'database' => 'app_test' },
        'animals' => { 'adapter' => 'postgresql', 'database' => 'animals_test' },
        'plants' => { 'adapter' => 'postgresql', 'database' => 'plants_test' }
      } }
    end

    it 'does not fail' do
      expect { dump }.not_to raise_error
    end

    it 'cleans the primary database file' do
      dump
      expect(contents('structure.sql')).to include('id BIGSERIAL')
    end

    it 'cleans the secondary database files' do
      dump
      expect(contents('animals_structure.sql')).to include('id BIGSERIAL')
      expect(contents('plants_structure.sql')).to include('id BIGSERIAL')
    end
  end

  context 'when SCHEMA names the dump file' do
    around do |example|
      previous = ENV['SCHEMA']
      ENV['SCHEMA'] = File.join(@db_dir, 'custom.sql')
      example.run
    ensure
      ENV['SCHEMA'] = previous
    end

    it 'cleans the file Rails wrote' do
      dump
      expect(contents('custom.sql')).to include('id BIGSERIAL')
    end
  end

  context 'when the database dumps to schema.rb' do
    let(:databases) do
      { 'test' => { 'primary' => {
        'adapter' => 'postgresql', 'database' => 'app_test', 'schema_format' => 'ruby'
      } } }
    end

    it 'does not fail' do
      expect { dump }.not_to raise_error
    end

    it 'leaves the ruby schema alone' do
      dump
      expect(contents('schema.rb')).to eq(RAW_PG_DUMP)
    end
  end

  context 'when a database opts out of schema dumping' do
    let(:databases) do
      { 'test' => {
        'primary' => { 'adapter' => 'postgresql', 'database' => 'app_test' },
        'replica' => { 'adapter' => 'postgresql', 'database' => 'app_test', 'replica' => true },
        'admin' => { 'adapter' => 'postgresql', 'database' => 'app_test', 'database_tasks' => false }
      } }
    end

    it 'does not fail' do
      expect { dump }.not_to raise_error
    end

    it 'cleans only the file Rails dumps' do
      dump
      expect(contents('structure.sql')).to include('id BIGSERIAL')
      expect(Dir.children(db_dir)).to contain_exactly('structure.sql')
    end
  end
end
