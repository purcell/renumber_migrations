namespace :db do
  namespace :migrate do
    MIGRATION_DIR = File.join(RAILS_ROOT, "db/migrate")

    def migrations
      Dir.new(MIGRATION_DIR).entries.inject([]) do |found, file|
        found << [$1.to_i, file] if file =~ /^(\d+)_.*\.rb$/
        found
      end
    end

    def svn_status_code(file)
      `svn st #{file}` =~ /^(.)\s+/ ? $1 : nil
    end

    desc 'Renumber uncommitted migrations after discovering a numbering conflict'
    task :renumber => :environment do
      raise "This task currently supports only subversion projects" unless File.exist?(File.join(RAILS_ROOT, ".svn"))
      new_migrations, existing_migrations = migrations.partition { |number, file| %w(A ?).include? svn_status_code("#{MIGRATION_DIR}/#{file}") }
      max_existing = existing_migrations.map { |number, file| number }.max
      min_new = new_migrations.map { |number, file| number }.min

      if min_new.nil? || min_new > max_existing
        puts ">>> Nothing to do -- there are no conflicting migration numbers"
      else
        # Remove overlapping from SVN
        new_from_svn = existing_migrations.select { |number, file| number >= min_new }

        new_from_svn.each do |number, file|
          puts ">>> #{file} is a duplicate from svn: removing for now..."
          File.unlink("#{MIGRATION_DIR}/#{file}")
        end

        # Roll back new migrations
        puts ">>> Migrating down to #{min_new - 1} prior to renaming"
        ENV['VERSION'] = (min_new - 1).to_s
        Rake::Task['db:migrate'].invoke

        # Rename new migrations
        new_migrations.sort.each_with_index do |mig, index|
          number, file = mig
          new_number = max_existing + index + 1
          renamed_file = file.gsub(/^(\d+)/, sprintf("%03d" % new_number))
          puts ">>> Renaming new migration #{file} to #{renamed_file}"
          old_path, new_path = File.join(MIGRATION_DIR, file), File.join(MIGRATION_DIR, renamed_file)
          File.rename(old_path, new_path)
          if svn_status_code(old_path) == '!'
            puts ">>> Telling subversion about the renaming, since you had added the old file"
            system("svn rm #{old_path}")
            system("svn add #{new_path}")
          end
        end

        puts ">>> Updating migrations from svn again:"
        new_from_svn.each do |number, file|
          puts ">>> Restoring #{MIGRATION_DIR}/#{file} from svn"
          system("svn up #{MIGRATION_DIR}/#{file}")
        end

        puts ">>> Not migrating up again automatically: that's your job"
      end
    end
  end
end
