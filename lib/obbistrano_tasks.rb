Capistrano::Configuration.instance(:must_exist).load do
  
  #### Performs the initial setup for tasks ####
  task :config_setup do
    set :root_pass, root rescue nil
    set :environment, environment rescue set :environment, "production"
    set :build_to, build_to rescue set :build_to, deploy_to
  end

 
  #### Slicehost Namespace.... Allows Auto Creation of DNS ####
 
  namespace :slicehost do
 
    desc "Sets up slicehost DNS for each of the servers specified with a role of web."
    task :setup do
      puts "*** You need to set a Slicehost API key in /etc/capistrano.conf to run this operation" if !defined? SLICEHOST_API_PASSWORD
      exit if !defined? SLICEHOST_API_PASSWORD
      get_slice_ip
      servers = find_servers :roles => :web
      servers.each do |s|
        if !zone = Zone.find(:first, :params => {:origin => "#{s}."})
          zone = Zone.new(:origin => s, :ttl => TTL)
          zone.save
        end
        recordOne =   Record.new(:record_type => 'A', :zone_id => zone.id, :name => 'www', :data => "#{slice_ip}")
        recordTwo =   Record.new(:record_type => 'A', :zone_id => zone.id, :name => '@', :data => "#{slice_ip}")
        recordThree = Record.new(:record_type => 'A', :zone_id => zone.id, :name => 'beta', :data => "#{slice_ip}")
        recordFour =  Record.new(:record_type => 'A', :zone_id => zone.id, :name => zone.origin, :data => "#{slice_ip}")
        recordFive =  Record.new(:record_type => 'NS', :zone_id => zone.id, :name => zone.origin, :data => 'ns1.slicehost.net.')
        recordSix =   Record.new(:record_type => 'NS', :zone_id => zone.id, :name => zone.origin, :data => 'ns2.slicehost.net.')
        recordSeven = Record.new(:record_type => 'NS', :zone_id => zone.id, :name => zone.origin, :data => 'ns3.slicehost.net.')
        [recordOne, recordTwo, recordThree, recordFour, recordFive, recordSix, recordSeven].each {|r| r.save}
      end
    end
  
    task :get_slice_ip do
      set :slice_ip, get_ip(fetch("host", false))
    end

    desc "Sets up slicehost DNS for Google Apps usage on each of the servers specified with a role of web."
    task :googleapps do
      puts "*** You need to set a Slicehost API key in /etc/capistrano.conf to run this operation" if !defined? SLICEHOST_API_PASSWORD
      exit if !defined? SLICEHOST_API_PASSWORD
      SLICEHOST_API_PASSWORD = "#{slicehost_api_key}"
      mx_records = <<-RECORD
      ASPMX.L.GOOGLE.COM.
      ALT1.ASPMX.L.GOOGLE.COM.
      ALT2.ASPMX.L.GOOGLE.COM.
      ASPMX2.GOOGLEMAIL.COM.
      ASPMX3.GOOGLEMAIL.COM.
      RECORD
      servers = find_servers :roles => :web
      servers.each do |s|
        mx_aux =  %w[5 10 10 20 20 30 ]
        aux_count = 0
        zone = Zone.find(:first, :params => {:origin => "#{s}."})
        mx_records.each do |rec|
          r = Record.new(:record_type => 'MX', :zone_id => zone.id, :name => "#{s}." , :data => "#{rec}", :aux => mx_aux[aux_count])
          r.save
          aux_count =+ 1
        end
        recordOne =   Record.new(:record_type => 'CNAME', :zone_id => zone.id, :name => 'mail', :data => "ghs.google.com.")
        recordTwo =   Record.new(:record_type => 'CNAME', :zone_id => zone.id, :name => 'docs', :data => "ghs.google.com.")
        [recordOne, recordTwo].each {|r| r.save}
      end
    end
 
  end


  #### Github Namespace.... Allows Auto Creation of Repository, ssh keys and Repo permissions ####

  namespace :github do
    
    task :init do
      puts "*** You need to specify a github login and token to run this operation" if !defined? "#{github_login}" || !defined? "#{github_token}"
      exit if !defined? "#{github_login}" || !defined? "#{github_token}"
    end
    
    desc "Sets up a Github Project and allows access for the devs at One Black Bear"
    task :setup do
      init
      api = GithubApi.new("#{github_login}", "#{github_token}")
      params = {
        :name =>"#{application}",
        :body  =>"Project for #{application}",
        :public =>0
      }
      api.create_repo(params)
      api.repo = "#{application}"
      api.add_collaborator("rossriley")
      api.add_collaborator("Sheldon")
      api.add_collaborator("charlesmarshall")
      api.add_collaborator("MichalNoskovic")
      github:key
    end
    
    desc "Grabs the SSH key from the server and adds it to the Github deploy keys"
    task :key do
      init
      api = GithubApi.new("#{github_login}", "#{github_token}")
      app:ssh_key
      server_ssh_key = capture("cat .ssh/id_rsa.pub")
      server_ssh_key
      api.add_key({:title=>"#{host}",:key=>server_ssh_key})
    end
    

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
      bundle.css
      bundle.js
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
      logger.level = 2
      
      set :local_branch, $1 if `git branch` =~ /\* (\S+)\s/m
      if !local_branch.eql? branch
        logger.info "You are on branch #{local_branch}, not #{branch}, please check out there before deploying to be able to combine the correct js and css files." 
        exit
      end
      
      if defined? "#{commit}"
        logger.info "Deploying application from #{repository} on commit #{commit}"
      else
        logger.info "Deploying application from #{repository} on branch #{branch}"
      end
      logger.level = -1
      begin
        run "ls #{deploy_to}/.git"
      rescue
        run "mkdir -p #{deploy_to}"
        run "cd #{deploy_to} && git init"
        run "cd #{deploy_to} && git remote add origin #{repository}"
      end
      logger.level = 2
      
      run "cd #{deploy_to} && git fetch"
      
      if defined? "#{commit}"
        run "cd #{deploy_to} && git checkout #{commit} && git submodule update --init --recursive"
      else
        begin
          run "cd #{deploy_to} && git show-branch #{branch} && git checkout #{branch} && git reset --hard origin/#{branch} && git submodule update --init --recursive"
        rescue
          run "cd #{deploy_to} && git checkout -b #{branch} origin/#{branch} && git submodule update --init --recursive"
        end
      end
      
      logger.info "Application has been updated on branch #{branch}"
    end
  
    task :svn_deploy, :roles =>[:web] do
      run "svn export #{repository} #{deploy_to} --force"
    end
  
    task :cms_deploy, :roles =>[:web] do
      logger.level = -1
      run "mkdir -p #{deploy_to}/plugins/cms"
      begin
        run "ls #{deploy_to}/plugins/cms/.git/"
      rescue
        logger.level = 2
        logger.info "Initialising Wildfire Folder"
        run "cd #{deploy_to}/plugins/cms && git init"
        run "cd #{deploy_to}/plugins/cms && git remote add origin git://github.com/phpwax/wildfire.git"
      end
      logger.info "Updating Wildfire Code from remote"
      run "cd #{deploy_to}/plugins/cms && git fetch"
      logger.level = -1
      begin
        run "cd #{deploy_to}/plugins/cms && git checkout -b #{cms} origin/#{cms}"
      rescue
        run "cd #{deploy_to}/plugins/cms && git checkout #{cms}"
      end
      run "cd #{deploy_to}/plugins/cms && git pull origin #{cms}"
      logger.level = 2
      logger.info "Wildfire CMS has been updated on branch #{cms}"
    end
    
  
    task :php_wax_deploy, :roles =>[:web] do
      logger.level = -1
      run "mkdir -p #{deploy_to}/wax"
      begin
        run "ls #{deploy_to}/wax/.git/"
      rescue
        logger.level = 2
        logger.info "Initialising PHP Wax Folder"
        run "cd #{deploy_to}/wax && git init"
        run "cd #{deploy_to}/wax && git remote add origin git://github.com/phpwax/phpwax.git"
      end
      logger.info "Updating PHP Wax Code from remote"
      run "cd #{deploy_to}/wax && git fetch"
      logger.level = -1
      begin
        run "cd #{deploy_to}/wax && git checkout -b #{phpwax} origin/#{phpwax}"
      rescue
        run "cd #{deploy_to}/wax && git checkout #{phpwax}"
      end
      run "cd #{deploy_to}/wax && git pull origin #{phpwax}"
      logger.level = 3
      logger.info "PHP Wax has been updated on branch #{phpwax}"
    end
  
  
    # =============================================================================
    # GENERAL ADMIN FOR APPLICATIONS
    # =============================================================================
  
    desc "Clears the application's cache files from tmp/cache."
    task :clearcache, :roles =>[:web] do
      run "cd #{deploy_to} && find tmp/cache -type f -exec rm -f \"{}\" \\;"
    end
  
    desc "Clears the application's log files from tmp/log."
    task :clearlogs, :roles =>[:web] do
      run "cd #{deploy_to} && find tmp/log -type f -exec rm -f \"{}\" \\;"
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
        logger.info "Writing User Cron File"
        write_crontab(user_cron_tasks)
      rescue
        
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
        puts "[write] crontab file updated"
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
      logger.level=-1
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
        run "cat .ssh/id_rsa.pub"
      rescue
        run "mkdir -p .ssh/"
        run "ssh-keygen -t rsa -f .ssh/id_rsa -N ''"
        run "cat .ssh/id_rsa.pub"
      end
    end
    
    desc "Creates a MySQL user and database"
    task :setup_mysql, :roles =>[:host] do
      needs_root
      set :user_to_add, "#{user}"
      set :passwd_to_add, "#{password}"
      with_user("root", "#{root_pass}") do
        "#{databases}".each do |db|
          begin
            run "mysql -uroot -p#{root_pass} -e \"CREATE USER '#{user_to_add}'@'localhost' IDENTIFIED BY '#{passwd_to_add}';\""
            run "mysql -uroot -p#{root_pass} -e 'CREATE DATABASE #{db}'"
            run "mysql -uroot -p#{root_pass} -e \"GRANT ALL PRIVILEGES ON #{db}.* TO '#{user_to_add}'@'localhost' IDENTIFIED BY '#{passwd_to_add}';\""
          rescue
            logger.info "Database #{db} already exists"
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
        puts "*** Operating System could not be detected or is not supported" if !defined? "#{os_ver}"
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
      puts "*** This operation needs root access - Please set a root password inside your /etc/capistrano.conf file" if !defined? "#{root_pass}"
      exit if !defined? "#{root_pass}"
      config_check
    end
    
    task :try_login, :roles =>[:host] do
      config_check
      begin
        run "ls"
        puts "Logged in ok"
      rescue
        print "==== The user does not yet exist. Would you like to create? [Y/N]"
        line = STDIN.gets.upcase.strip
        puts "*** Could not continue as the login does not exist" if line !="Y"
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
    paths = paths | get_top_level_directories("#{build_to}/plugins/cms/resources/public/stylesheets") if defined? "#{cms}"
    paths << "#{build_to}/public/stylesheets/"
    if defined? "#{plugins}"
      plugins.each do |plugin|
        paths << "#{build_to}/plugins/#{plugin}/resources/public/stylesheets"
      end
    end
    Dir.mkdir("#{build_to}/public/stylesheets/build") rescue ""
    paths.each do |bundle_directory|      
      bundle_name = bundle_directory.gsub(/(cms)|(\/plugins)|(resources)|(public)|(stylesheets)|(\/)/i, "")
      bundle_name = if(bundle_name.index(".") == 0) then bundle_name[1..bundle_name.length] else bundle_name end
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
    upload "#{build_to}/public/stylesheets/build", "#{deploy_to}/public/stylesheets/", :via => :scp, :recursive=>true
  end

  task :js , :roles => [:web] do
    paths = get_top_level_directories("#{build_to}/public/javascripts")
    paths = paths | get_top_level_directories("#{build_to}/plugins/cms/resources/public/javascripts") if defined? "#{cms}"
    paths << "#{build_to}/public/javascripts/"
    if defined? "#{plugins}"
      plugins.each do |plugin|
        paths << "#{build_to}/plugins/#{plugin}/resources/public/javascripts"
      end
    end
    Dir.mkdir("#{build_to}/public/javascripts/build") rescue ""
    paths.each do |bundle_directory|
      puts bundle_directory
      bundle_name = bundle_directory.gsub(/(cms)|(\/plugins)|(resources)|(public)|(javascripts)|(\/)/i, "")
      bundle_name = if(bundle_name.index(".") == 0) then bundle_name[1..bundle_name.length] else bundle_name end
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
    upload "#{build_to}/public/javascripts/build", "#{deploy_to}/public/javascripts/", :via => :scp, :recursive=>true

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



end

