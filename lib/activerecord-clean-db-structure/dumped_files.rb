module ActiveRecordCleanDbStructure
  # Finds the files that `db:schema:dump` has just written.
  #
  # Rails owns this naming: it applies ENV["SCHEMA"], the primary/secondary
  # distinction, the per-database `schema_dump` override, and the opt-outs for
  # replicas and for databases that dump to schema.rb. Ask Rails for the paths
  # instead of rebuilding them here, which got the primary database wrong and
  # ignored every one of those rules.
  module DumpedFiles
    module_function

    def paths
      tasks = ActiveRecord::Tasks::DatabaseTasks

      if tasks.respond_to?(:schema_dump_path) # Rails 7.0 and newer
        database_configs.filter_map { |db_config| tasks.schema_dump_path(db_config) }.uniq
      else
        legacy_paths
      end
    end

    def database_configs
      databases = ActiveRecord::Tasks::DatabaseTasks.setup_initial_database_yaml
      ActiveRecord::DatabaseConfigurations.new(databases)
                                          .configs_for(env_name: Rails.env)
                                          .select { |db_config| db_config.database_tasks? }
                                          .select { |db_config| db_config.schema_format == :sql }
    end

    # Rails 6.0 and older. Kept so that this gem behaves on those versions
    # exactly as it did before; it is not covered by the specs.
    def legacy_paths
      return [ENV['DB_STRUCTURE']] if ENV.key?('DB_STRUCTURE')

      Rails.application.config.paths['db'].map { |path| File.join(path, 'structure.sql') }
    end
  end
end
