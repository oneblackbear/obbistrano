Capistrano::Configuration.instance(:must_exist).load do

  #### Performs the initial setup for tasks ####
  task :config_setup do
    set :root_pass, root rescue nil
    set :environment, environment rescue set :environment, "production"
  end

 
  #### Slicehost Namespace.... Allows Auto Creation of DNS ####
 
  namespace :slicehost do
 
    desc "Sets up slicehost DNS for each of the servers specified with a role of web."
    task :setup do
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
    task :setup do
      puts "*** You need to specify a github login and token to run this operation" if !defined? "#{github_login}" || !defined? "#{github_token}"
      exit if !defined? "#{github_login}" || !defined? "#{github_token}"
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
      app:ssh_key
      server_ssh_key = capture("cat .ssh/id_rsa.pub")
      server_ssh_key
      api.add_key({:title=>"#{host}",:key=>server_ssh_key})
    end
    

  end
  
  namespace :app do  
  
    task :config_check do
      config_setup
      databases rescue set(:databases, ["#{application}"])
      aliases rescue set(:aliases, []);
    end
  
    task :needs_root do
      config_check
      puts "*** This operation needs root access - Please pass in a root password using -s root=password" if !defined? "#{root_pass}"
      exit if !defined? "#{root_pass}"
    end
  
  

    # =============================================================================
    # DEPLOYING APPLICATIONS
    # =============================================================================
  
    task :deploy do
      config_check
      deploy_check
      php_wax_deploy if defined? "#{phpwax}"
      cms_deploy if defined? "#{cms}"
      css_build
      js_build
    end
  
    task :deploy_check do 
      fetch "repository" rescue abort "You have not specified a repository for this application"
      git_deploy if repository.include? "git"
      svn_deploy if repository.include? "svn"
    end
    
    task :syncdb do
      logger.level = -1
      run "cd #{deploy_to} && script/syncdb #{environment}"
      logger.level=2
      logger.info "Application database has been synchronised"
    end
  
    task :git_deploy do
      logger.level = 2
      logger.info "Deploying application from #{repository} on branch #{branch}"
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
      begin
        run "cd #{deploy_to} && git checkout -b #{branch} origin/#{branch}"
      rescue
        run "cd #{deploy_to} && git pull origin #{branch}"
        run "cd #{deploy_to} && git checkout #{branch}"
        run "cd #{deploy_to} && git checkout #{commit}" if defined? "#{commit}"
      end
      
      logger.info "Application has been updated on branch #{branch}"
    end
  
    task :svn_deploy do
      run "svn export #{repository} #{deploy_to} --force"
    end
  
    task :cms_deploy do
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
    
  
    task :php_wax_deploy do
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
  
  
    task :css_build
      run "cd #{deploy_to} && rm -f public/stylesheets/build.css"
      Dir.glob("**/*.css").each do |f|  
        run "cd #{deploy_to} && cat #{f} >> public/stylesheets/build.css" 
      end
    end
    
    task :js_build
      run "cd #{deploy_to} && rm -f public/javascripts/build.js"
      Dir.glob("**/*.js").each do |f|  
        run "cd #{deploy_to} && cat #{f} >> public/javascripts/build.js" 
      end
    end
    ####### ##############
  
  
    # =============================================================================
    # GENERAL ADMIN FOR APPLICATIONS
    # =============================================================================
    
    desc "Restarts the Apache Server. Requires root password to access."
    task :restart do
      config_check
      needs_root
      with_user("root", "#{root_pass}") do 
        run "/etc/rc.d/init.d/httpd restart"
      end
    end
  
    desc "Clears the application's cache files from tmp/cache."
    task :clearcache do
      run "cd #{deploy_to} && rm -f tmp/cache/*"
    end
  
    desc "Clears the application's log files from tmp/log."
    task :clearlogs do
      run "cd #{deploy_to} && rm -f tmp/log/*"
    end
  
    
  
    # =============================================================================
    # USER AND APPLICATION SETUP AND INITIALISATION
    # =============================================================================
  
    task :setup do
      config_check
      try_login
      setup_mysql
      vhost
      ssh_key
    end
  
    
    task :setup_user do
      needs_root
      set :user_to_add, "#{user}"
      set :passwd_to_add, "#{password}"
      with_user("root", "#{root_pass}") do 
        run "useradd -p `openssl passwd #{passwd_to_add}` #{user_to_add}"
      end
    end
  
    task :setup_mysql do
      needs_root
      set :user_to_add, "#{user}"
      set :passwd_to_add, "#{password}"
      with_user("root", "#{root_pass}") do
        "#{databases}".each do |db|
          begin
            run "mysql -uroot -p#{root_pass} -e \"CREATE USER '#{user_to_add}'@'localhost' IDENTIFIED BY '#{passwd_to_add}';\""
            run "mysql -uroot -p#{root_pass} -e 'CREATE DATABASE #{db}'"
            run "musql -uroot -p#{root_pass} -e \"GRANT ALL PRIVILEGES ON `#{db}` . * TO '#{user_to_add}'@'localhost' IDENTIFIED BY '#{passwd_to_add}';\""
          rescue
            logger.info "Database #{db} already exists"
          end
        end
      end
    
    end
  
    task :try_login do
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
  
    desc "Creates or gets an ssh key for the application"
    task :ssh_key do 
      config_check
      begin
        run "cat .ssh/id_rsa.pub"
      rescue
        run "mkdir -p .ssh/"
        run "ssh-keygen -t rsa -f .ssh/id_rsa -N ''"
        run "cat .ssh/id_rsa.pub"
      end
    end
  
    desc "Creates an Apache virtual host file"
    task :vhost do
      config_check
      needs_root
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
      restart
    end
    
    
  
    # =============================================================================
    # +MIGRATING+ APPLICATIONS
    # =============================================================================
  
    task :copy_site do 
      config_check
      needs_root
      backup
      print "==== Which server would you like to copy #{application} to? [Full Domain Name] "
      line = STDIN.gets.strip
      begin      
        new_server = options["servers"][line]["domain"] 
      rescue 
        puts "*** Can't find that new server in the config"
        exit
      end
      with_user("root", "#{root_pass}") do
        run "rsync -avzh . -e ssh root@#{new_server}:/backup/#{application}/ --exclude 'tmp/*' --exclude '.git/*'"
      end
      options["apps"]["#{application}"]["server"] = line
      config_write
      try_login
      restore
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
    task :default do
      logger.level=-1
      app.deploy
    end
  end
  
  namespace :setup do
    desc "Sets up the server with a user, home directory and mysql login."
    task :default do
      app.setup
    end
  end

end




