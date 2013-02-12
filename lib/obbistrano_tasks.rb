Capistrano::Configuration.instance(:must_exist).load do

  #### Global helper methods ######
  
  STDOUT.sync
  $error = false

  # Be less verbose by default
  #logger.level = Capistrano::Logger::IMPORTANT
  
  def pretty_print(msg)
    if logger.level == Capistrano::Logger::IMPORTANT
      msg = msg.slice(0, 87)
      msg << '.' * (90 - msg.size)
      print msg
    else
      puts msg.green
    end
  end
  
  def puts_ok
    if logger.level == Capistrano::Logger::IMPORTANT && !$error
      puts '✔'.green
    end
    $error = false
  end
  
  def puts_fail
    puts '✘'.red
  end
  
  
  def remote_file_exists?(full_path)
    'true' == capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip
  end

  def remote_command_exists?(command)
    'true' == capture("if [ -x \"$(which #{command})\" ]; then echo 'true'; fi").strip
  end
  
  #### Variable defaults
  set :php_bin,            "php"
  
  # Flags an app to install composer - false by default
  set :use_composer,       false
  
  # If set to false download/install composer
  set :composer_bin,       false
  
  # Options to pass to composer when installing/updating
  set :composer_options,   "--no-scripts --verbose --prefer-dist"

  # Whether to update vendors using the configured dependency manager (composer or bin/vendors)
  set :update_vendors,     false
  
  # run bin/vendors script in mode (upgrade, install (faster if shared /vendor folder) or reinstall)
  set :vendors_mode,      "reinstall"

  # Path to deploy to after login. Defaults to root
  set :deploy_to,         '.'
  

  #### Performs the initial setup for tasks ####
  task :config_setup do
    set :root_pass, root rescue nil
    set :environment, environment rescue set :environment, "production"
    set :build_to, build_to rescue set :build_to, deploy_to
  end


  namespace :app do

    # =============================================================================
    # DEPLOYING APPLICATIONS
    # =============================================================================

    task :full_deploy, :roles =>[:web] do
      host.config_check
      deploy_check
      php_wax_deploy if defined? "#{phpwax}"
      cms_deploy if defined? "#{cms}"
      symlink if defined? "#{app_environment}"
      composer.install if use_composer
      bundle.css
      bundle.js
    end
    
    task :symlink, :roles =>[:web] do
      run "ln -s #{deploy_to}/app/config/bootstrap_#{environment}.php #{deploy_to}/app/config/bootstrap.php"
    end

    desc "Deploys the application only - no Framework / Plugins"
    task :deploy, :roles =>[:web] do
      host.config_check
      deploy_check
      bundle.css
      bundle.js
    end

    task :deploy_check, :roles =>[:web] do
      fetch "repository" rescue abort "You have not specified a repository for this application"
      git_copy if deploy_via=="copy" rescue ""
      git_deploy if repository.include? "git"
      svn_deploy if repository.include? "svn"
    end

    task :git_copy, :roles=>[:web] do
      Dir.mkdir("tmp/deploy_cache") rescue ""
      system("git clone --depth 1 #{repository} tmp/deploy_cache/" )
      system("cd tmp/deploy_cache/ && git checkout -b #{branch} origin/#{branch}" )
      upload "tmp/deploy_cache/", "#{deploy_to}", :via => :scp, :recursive=>true
      FileUtils.rm_rf 'tmp/deploy_cache'
    end

    task :git_deploy, :roles =>[:web] do
      puts "*** Application being updated on branch #{branch}".yellow
      
      set :local_branch, $1 if `git branch` =~ /\* (\S+)\s/m
      if !local_branch.eql? branch
        pretty_print "You are on branch #{local_branch}, not #{branch}, please check out there before deploying to be able to combine the correct js and css files.".red
        puts_fail
        exit
      end

      if defined? "#{commit}"
        pretty_print "--> Deploy from #{repository} on commit #{commit}"
      else
        pretty_print "--> Deploy from #{repository} on branch #{branch}"
      end

      begin
        logger.level = -1
        run "ls #{deploy_to}/.git"
        puts_ok
        logger.level = 0
      rescue
        run "mkdir -p #{deploy_to}"
        run "cd #{deploy_to} && git init"
        run "cd #{deploy_to} && git remote add origin #{repository}"
        puts_ok
      end

      pretty_print "--> Updating code from remote repository"
      logger.level = -1
      begin
        run "cd #{deploy_to} && git fetch"
      rescue
        puts_fail
        puts "Unable to connect to remote repository, check your configuration, and that a valid ssh key exists for remote server.".red
        exit
      end
      logger.level = 0
      if defined? "#{commit}"
        run "cd #{deploy_to} && git checkout #{commit} && git submodule update --init --recursive"
      else
        logger.level = -1
        begin
          run "cd #{deploy_to} && git show-branch #{branch} && git checkout #{branch} ; git reset --hard origin/#{branch} && git submodule update --init --recursive"
        rescue
          run "cd #{deploy_to} && git checkout -b #{branch} origin/#{branch} ; git submodule update --init --recursive"
        end
        logger.level = 0
      end
      puts_ok
    end

    task :svn_deploy, :roles =>[:web] do
      run "svn export #{repository} #{deploy_to} --force"
    end

    task :cms_deploy, :roles =>[:web] do
      pretty_print "--> Updating Wildfire CMS on branch #{cms}"
      
      run "mkdir -p #{deploy_to}/plugins/cms"
      begin
        run "ls #{deploy_to}/plugins/cms/.git/"
      rescue
        logger.info "Initialising Wildfire Folder"
        run "cd #{deploy_to}/plugins/cms && git init"
        run "cd #{deploy_to}/plugins/cms && git remote add origin git://github.com/phpwax/wildfire.git"
      end
      logger.info "Updating Wildfire Code from remote"
      run "cd #{deploy_to}/plugins/cms && git fetch"
      begin
        run "cd #{deploy_to}/plugins/cms && git checkout -b #{cms} origin/#{cms}"
      rescue
        run "cd #{deploy_to}/plugins/cms && git checkout #{cms}"
      end
      run "cd #{deploy_to}/plugins/cms && git pull origin #{cms}"
      puts_ok
    end


    task :php_wax_deploy, :roles =>[:web] do
      pretty_print "--> Updating PHP Wax has been updated on branch #{phpwax}"
      run "mkdir -p #{deploy_to}/wax"
      begin
        run "ls #{deploy_to}/wax/.git/"
      rescue
        logger.info "Initialising PHP Wax Folder"
        run "cd #{deploy_to}/wax && git init"
        run "cd #{deploy_to}/wax && git remote add origin git://github.com/phpwax/phpwax.git"
      end
      logger.info "Updating PHP Wax Code from remote"
      run "cd #{deploy_to}/wax && git fetch"
      begin
        run "cd #{deploy_to}/wax && git checkout -b #{phpwax} origin/#{phpwax}"
        puts_ok
      rescue
        run "cd #{deploy_to}/wax && git checkout #{phpwax}"
      end
      run "cd #{deploy_to}/wax && git pull origin #{phpwax}"
      puts_ok
    end


    # =============================================================================
    # GENERAL ADMIN FOR APPLICATIONS
    # =============================================================================

    desc "Clears the application's cache files from tmp/cache."
    task :clearcache, :roles =>[:web] do
      pretty_print "--> Clearing application cache directory"
      begin
        run "cd #{deploy_to} && find tmp/cache -type f -exec rm -f \"{}\" \\;"
        puts_ok
      rescue
        puts_fail
      end
    end

    desc "Clears the application's log files from tmp/log."
    task :clearlogs, :roles =>[:web] do
      pretty_print "--> Clearing application logs from tmp/log"
      begin
        run "cd #{deploy_to} && find tmp/log -type f -exec rm -f \"{}\" \\;"
        puts_ok
      rescue
        puts_fail
      end
    end


    desc "Uses configs in the app/platform directory to configure servers"
    task :install, :roles =>[:host] do
      host.config_check
      host.needs_root
      set :user_to_config, "#{user}"
      begin
        with_user("root", "#{root_pass}") do
          run "rm -f /etc/nginx/sites-enabled/#{user_to_config}.conf; ln -s /home/#{user_to_config}/#{deploy_to}/app/platform/nginx.conf /etc/nginx/sites-enabled/#{user_to_config}.conf"
          run "rm -f /etc/apache2/sites-enabled/#{user_to_config}.conf; ln -s /home/#{user_to_config}/#{deploy_to}/app/platform/apache.conf /etc/apache2/sites-enabled/#{user_to_config}.conf"
        end
        user_cron_tasks = capture("cat #{deploy_to}/app/platform/crontab")
        pretty_print "--> Writing User Cron File"
        write_crontab(user_cron_tasks)
        puts_ok
      rescue
        puts_fail
      end
    end

    def write_crontab(data)
      tmp_cron_file = Tempfile.new('temp_cron').path
      File.open(tmp_cron_file, File::WRONLY | File::APPEND) do |file|
        file.puts data
      end

      command = ['crontab']
      command << "-u #{user}" if defined? "#{user}"
      command << tmp_cron_file

      if system(command.join(' '))
        pretty_print "[write] crontab file updated"
        exit
      else
        warn "[fail] couldn't write crontab"
        exit(1)
      end
    end


  end


  def get_ip(domain)
    require 'socket'
    t = TCPSocket.gethostbyname(domain)
    t[3]
  end

  def with_user(new_user, new_pass, &block)
    old_user, old_pass = user, password
    set :user, new_user
    set :password, new_pass
    close_sessions
    yield
    set :user, old_user
    set :password, old_pass
    close_sessions
  end
  def close_sessions
    sessions.values.each { |session| session.close }
    sessions.clear
  end


  namespace :deploy do
    desc "Uses the specified repository to deploy an application. Also checks for correct versions of PHPWax and plugins."
    task :default, :roles => [:web]  do
      app.full_deploy
    end
  end

  namespace :setup do
    desc "Sets up the server with a user, home directory and mysql login."
    task :default do
      host.setup
    end
  end

  namespace :host do


    desc "Sets up the server with a user, home directory and mysql login."
    task :setup, :roles => [:host] do
      try_login
      vhost
      setup_mysql
    end

    desc "Restarts the web server."
    task :restart, :roles => [:host] do
      needs_root
      fedora.restart
    end

    desc "Creates a new Apache VHost."
    task :vhost, :roles => [:host] do
      needs_root
      fedora.vhost
      fedora.restart
    end

    desc "Sets up a new user."
    task :setup_user, :roles => [:host] do
      needs_root
      fedora.setup_user
    end

    desc "Creates or gets an ssh key for the application"
    task :ssh_key, :roles =>[:host] do
      config_check
      begin
        key = capture "cat .ssh/id_rsa.pub"
      rescue
        run "mkdir -p .ssh/"
        run "ssh-keygen -t rsa -f .ssh/id_rsa -N ''"
        key = capture "cat .ssh/id_rsa.pub"
      end
      puts "---> SSH Key for server is:"
      puts key.green
    end

    desc "Creates a MySQL user and database"
    task :setup_mysql, :roles =>[:host] do
      needs_root
      set :user_to_add, "#{user}"
      set :passwd_to_add, "#{password}"
      pretty_print "--> Creating mysql user"
      with_user("root", "#{root_pass}") do
        "#{databases}".each do |db|
          begin
            run "mysql -uroot -p#{root_pass} -e \"CREATE USER '#{user_to_add}'@'localhost' IDENTIFIED BY '#{passwd_to_add}';\""
            run "mysql -uroot -p#{root_pass} -e 'CREATE DATABASE #{db}'"
            run "mysql -uroot -p#{root_pass} -e \"GRANT ALL PRIVILEGES ON #{db}.* TO '#{user_to_add}'@'localhost' IDENTIFIED BY '#{passwd_to_add}';\""
            puts_ok
          rescue
            logger.info "Database #{db} already exists"
            puts_fail
          end
        end
      end
    end

    desc "Detects what flavour of linux is being used"
    task :detect_os, :roles =>[:host] do
      begin
        run "cat /etc/fedora-release"
        set :os_ver, "fedora"
      rescue
        run "cat /etc/debian_version"
        set :os_ver, "ubuntu"
      rescue
        puts "--> Operating System could not be detected or is not supported" if !defined? "#{os_ver}".red
        puts_fail
        exit if !defined? "#{os_ver}"
      end
      eval "#{os_ver}".testos
    end



    # =============================================================================
    # +MIGRATING+ APPLICATIONS
    # =============================================================================




    ###### Private tasks for server operations #############

    task :config_check do
      config_setup
      databases rescue set(:databases, ["#{application}"])
      aliases rescue set(:aliases, []);
    end

    task :needs_root do
      pretty_print "--> This operation needs root access - Please set a root password inside your /etc/capistrano.conf file".red if !defined? "#{root_pass}"
      puts_fail if !defined? "#{root_pass}"
      exit if !defined? "#{root_pass}"
      config_check
    end

    task :try_login, :roles =>[:host] do
      config_check
      begin
        run "ls"
        pretty_print "Logged in ok"
        puts_ok
      rescue
        print "--> The user does not yet exist. Would you like to create? [Y/N]"
        line = STDIN.gets.upcase.strip
        puts "--> Could not continue as the login does not exist" if line !="Y".red
        puts_fail
        exit if line != "Y"
        setup_user
      end
    end

  end

  namespace :fedora do

    task :setup_user, :roles =>[:host] do
      set :user_to_add, "#{user}"
      set :passwd_to_add, "#{password}"
      with_user("root", "#{root_pass}") do
        run "useradd -m -r -p `openssl passwd #{passwd_to_add}` #{user_to_add}"
        run "chmod -R 0755 /home/#{user_to_add}"
      end
    end

    task :vhost, :roles =>[:host] do
      with_user("root", "#{root_pass}") do
        public_ip = ""
        run "ifconfig eth0 | grep inet | awk '{print $2}' | sed 's/addr://'" do |_, _, public_ip| end
        public_ip = public_ip.strip
        roles[:web].servers.each do |webserver|
          f = File.open(File.join(File.dirname(__FILE__), 'templates/apache_vhost.erb' ))
          contents = f.read
          f.close
          buffer = ERB.new(contents)
          config = buffer.result(binding())
          put config, "/etc/httpd/conf.d/#{webserver}-apache-vhost.conf"
        end
      end
    end

    task :restart, :roles =>[:host] do
      with_user("root", "#{root_pass}") do
        run "/etc/init.d/httpd restart"
      end
    end

    task :ostest, :roles => [:host] do
      puts "#{os_ver}"
      exit
    end

  end

  namespace :ubuntu do
    task :ostest, :roles => [:host] do
      puts "#{os_ver}"
      exit
    end
  end

  task :mirror do
    print "==== Which server would you like to copy #{application} to? [Full Domain Name] "
    new_server = STDIN.gets.strip
    old_roles = roles[:web]
    roles[:web].clear
    role :web, new_server
    host.setup
    roles[:web].clear
    roles[:web] = old_roles
    puts roles[:web]
    run "ls"
    run "rsync -avz -e ssh ./ #{user}@#{new_server}:/home/#{user}/ --exclude 'tmp/*'"
    "#{databases}".each do |db|
      run "mysqldump #{db} | ssh #{user}@#{new_server} mysql #{db}"
    end

  end


  namespace :bundle do


  task :css, :roles => [:web] do
    paths = get_top_level_directories("#{build_to}/public/stylesheets")
    if defined? "#{newdeploy}" then
      if defined? "#{plugins}"
        plugins.each do |plugin|
          pretty_print "-->    Adding Plugin: #{plugin}"
          puts_ok
          paths << "#{build_to}/plugins/#{plugin}/resources/public/stylesheets"
        end
      end
    
      Dir.mkdir("#{build_to}/public/stylesheets/build") rescue ""
      paths.each do |bundle_directory|
        bundle_name = bundle_directory.gsub("#{build_to}/", "").gsub("plugins/", "").gsub("/resources/public/stylesheets", "").gsub("public/stylesheets/", "")
        next if bundle_name.empty?
        files = recursive_file_list(bundle_directory, ".css")
        next if files.empty? || bundle_name == 'dev'
        bundle = ''
        files.each do |file_path|
          bundle << File.read(file_path) << "\n"
        end
        target = "#{build_to}/public/stylesheets/build/#{bundle_name}_combined.css"
        File.open(target, 'w') { |f| f.write(bundle) }
        pretty_print "-->    Created Bundle File: #{target}"
        puts_ok
      end
    else
      paths = paths | get_top_level_directories("#{build_to}/plugins/cms/resources/public/stylesheets") if defined? "#{cms}"
      paths << "#{build_to}/public/stylesheets/"
      Dir.mkdir("#{build_to}/public/stylesheets/build") rescue ""
      paths.each do |bundle_directory|
        pretty_print bundle_directory
        bundle_name = if bundle_directory.index("plugins") then bundle_directory.gsub("#{build_to}/plugins/cms/resources/public/stylesheets", "") else bundle_directory.gsub("#{build_to}/public/stylesheets/", "") end
        bundle_name = if bundle_name.index("/") then bundle_name[0..bundle_name.index("/")-1] else bundle_name end
        next if bundle_name.empty?
        files = recursive_file_list(bundle_directory, ".css")
        next if files.empty? || bundle_name == 'dev'
        bundle = ''
        files.each do |file_path|
          bundle << File.read(file_path) << "\n"
        end
        target = "#{build_to}/public/stylesheets/build/#{bundle_name}_combined.css"
        File.open(target, 'w') { |f| f.write(bundle) }
      end
    end
    pretty_print "--> Uploading CSS build files"
    upload "#{build_to}/public/stylesheets/build", "#{deploy_to}/public/stylesheets/", :via => :scp, :recursive=>true
    puts_ok
  end
  task :js , :roles => [:web] do
    paths = get_top_level_directories("#{build_to}/public/javascripts")
    if defined? "#{newdeploy}" then
      if defined? "#{plugins}"
        plugins.each do |plugin|
          pretty_print "-->    Adding plugin: #{plugin}"
          puts_ok
          paths << "#{build_to}/plugins/#{plugin}/resources/public/javascripts"
        end
      end
      
      Dir.mkdir("#{build_to}/public/javascripts/build") rescue ""
      paths.each do |bundle_directory|
        bundle_name = bundle_directory.gsub("#{build_to}/", "").gsub("plugins/", "").gsub("/resources/public/javascripts", "").gsub("public/javascripts/", "")
        next if bundle_name.empty?
        files = recursive_file_list(bundle_directory, ".js")
        next if files.empty? || bundle_name == 'dev'
        bundle = ''
        files.each do |file_path|
          bundle << File.read(file_path) << "\n"
        end
        target = "#{build_to}/public/javascripts/build/#{bundle_name}_combined.js"
        File.open(target, 'w') { |f| f.write(bundle) }
        pretty_print "-->    Created Bundle File: #{target}"
        puts_ok
      end
    else
      paths = paths | get_top_level_directories("#{build_to}/plugins/cms/resources/public/javascripts") if defined? "#{cms}"
      paths << "#{build_to}/public/javascripts/"
      Dir.mkdir("#{build_to}/public/javascripts/build") rescue ""
      paths.each do |bundle_directory|
        bundle_name = if bundle_directory.index("plugins") then bundle_directory.gsub("#{build_to}/plugins/cms/resources/public/javascripts", "") else bundle_directory.gsub("#{build_to}/public/javascripts/", "") end
        bundle_name = if bundle_name.index("/") then bundle_name[0..bundle_name.index("/")-1] else bundle_name end
        next if bundle_name.empty?
        files = recursive_file_list(bundle_directory, ".js")
        next if files.empty? || bundle_name == 'dev'
        bundle = ''
        files.each do |file_path|
          bundle << File.read(file_path) << "\n"
        end
        target = "#{build_to}/public/javascripts/build/#{bundle_name}_combined.js"
        File.open(target, 'w') { |f| f.write(bundle) }
      end
    end
    pretty_print "--> Uploading javascript build files"
    upload "#{build_to}/public/javascripts/build", "#{deploy_to}/public/javascripts/", :via => :scp, :recursive=>true
    puts_ok
  end



    require 'find'
    def recursive_file_list(basedir, ext)
      files = []
      Find.find(basedir) do |path|
        if FileTest.directory?(path)
          if File.basename(path)[0] == ?. # Skip dot directories
            Find.prune
          else
            next
          end
        end
        files << path if File.extname(path) == ext
      end
      files.sort
    end

    def get_top_level_directories(base_path)
      Dir.entries(base_path).collect do |path|
        path = "#{base_path}/#{path}"
        File.basename(path)[0] == ?. || !File.directory?(path) || File.basename(path)=="build" ? nil : path # not dot directories or files
      end - [nil]
    end

  end
  
  
  namespace :composer do
    desc "Gets composer and installs it"
    task :get, :roles => :web, :except => { :no_release => true } do
      if !remote_file_exists?("#{deploy_to}/composer.phar")
        pretty_print "--> Downloading Composer"
        begin
          run "sh -c 'cd #{deploy_to} && curl -s http://getcomposer.org/installer | #{php_bin}'"
          puts_ok
        rescue
          puts_fail
        end 
      else
        pretty_print "--> Updating Composer"
        begin
          run "sh -c 'cd #{deploy_to} && #{php_bin} composer.phar self-update'"
          puts_ok
        rescue
          puts_fail
        end
      end
    end

    desc "Updates composer"
    task :self_update, :roles => :web, :except => { :no_release => true } do
      pretty_print "--> Updating Composer"
      begin
        run "sh -c 'cd #{deploy_to} && #{composer_bin} self-update'" do |channel, stream, data|
          puts "\n"
          puts data
        end
        puts_ok
      rescue
        puts_fail
      end 
    end

    desc "Runs composer to install vendors from composer.lock file"
    task :install, :roles => :web, :except => { :no_release => true } do
      composer_out = ""
      if composer_bin
        composer.self_update
      else
        composer.get
        set :composer_bin, "#{php_bin} composer.phar"
      end

      pretty_print "--> Installing Composer dependencies"
      begin
        run "cd #{deploy_to} && #{composer_bin} install #{composer_options}" do |channel, stream, data|
          composer_out = data
        end
        puts_ok
      rescue
        puts_fail
        puts composer_out.white_on_red
      end 
    end

    desc "Runs composer to update vendors, and composer.lock file"
    task :update, :roles => :web, :except => { :no_release => true } do
      if composer_bin
        composer.self_update
      else
        composer.get
        set :composer_bin, "#{php_bin} composer.phar"
      end

      pretty_print "--> Updating Composer dependencies"
      begin
        run "sh -c 'cd #{deploy_to} && #{composer_bin} update #{composer_options}'" do |channel, stream, data|
          composer_out = data
        end
        puts_ok
      rescue
        puts_fail
        puts composer_out.white_on_red
      end 
    end

    desc "Dumps an optimized autoloader"
    task :dump_autoload, :roles => :web, :except => { :no_release => true } do
      if composer_bin
        composer.self_update
      else
        composer.get
        set :composer_bin, "#{php_bin} composer.phar"
      end

      pretty_print "--> Dumping an optimized autoloader"
      begin
        run "sh -c 'cd #{deploy_to} && #{composer_bin} dump-autoload --optimize'" do |channel,stream,data|
          composer_out = data
        end
        puts_ok
      rescue
        puts_fail
        puts composer_out.white_on_red
      end      
      
    end

  end



end

