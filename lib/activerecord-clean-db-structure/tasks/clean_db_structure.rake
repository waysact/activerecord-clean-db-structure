require 'activerecord-clean-db-structure/clean_dump'
require 'activerecord-clean-db-structure/dumped_files'

pre_6_1 = ActiveRecord::VERSION::MAJOR < 6 || (
  ActiveRecord::VERSION::MAJOR == 6 && ActiveRecord::VERSION::MINOR < 1
)

Rake::Task[pre_6_1 ? 'db:structure:dump' : 'db:schema:dump'].enhance do
  ActiveRecordCleanDbStructure::DumpedFiles.paths.each do |filename|
    cleaner = ActiveRecordCleanDbStructure::CleanDump.new(
      File.read(filename),
      **Rails.application.config.activerecord_clean_db_structure
    )
    cleaner.run
    File.write(filename, cleaner.dump)
  end
end
