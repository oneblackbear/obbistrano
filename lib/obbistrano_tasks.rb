Capistrano::Configuration.instance(:must_exist).load do

  #### Performs the initial setup for tasks ####
  task :config_setup do
    set :root_pass, root rescue nil
  end

 
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
      API_PASSWORD = "#{slicehost_api_key}"
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

  
  namespace :app do  
  
    task :config_check do
      config_setup
      databases rescue set(:databases, ["#{application}"])
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
    end
  
    task :deploy_check do 
      fetch "repository" rescue abort "You have not specified a repository for this application"
      git_deploy if repository.include? "git"
      svn_deploy if repository.include? "svn"
    end
  
    task :git_deploy do
      logger.level = Capistrano::Logger::IMPORTANT # least verbose 
      begin
        run "ls #{deploy_to}/.git"
      rescue
        run "git init"
        run "git remote add origin #{repository}"
      end
      run "git pull origin #{branch}"
    end
  
    task :svn_deploy do
      run "svn export #{repository} #{deploy_to} --force"
    end
  
    task :cms_deploy do
      logger.level = Capistrano::Logger::IMPORTANT # least verbose 
      begin
        run "ls plugins/cms/.git"
      rescue
        run "mkdir -p plugins/cms"
        run "cd plugins/cms && git init"
        run "cd plugins/cms && git remote add origin git://github.com:phpwax/wildfire.git"
      end
      run "cd plugins/cms && git fetch"
      begin
        run "cd plugins/cms && git checkout -b #{cms} origin/#{cms}"
      rescue
        "cd plugins/cms && git checkout #{cms}"
      end
    end
  
    task :php_wax_deploy do
      logger.level = Capistrano::Logger::IMPORTANT # least verbose 
      begin
        run "ls wax/.git"
      rescue
        run "mkdir wax"
        run "cd wax && git init"
        run "cd wax && git remote add origin git://github.com/phpwax/phpwax.git"
      end
      run "cd wax && git fetch"
      begin
        run "cd wax && git checkout -b #{phpwax} origin/#{phpwax}"
      rescue
        "cd wax && git checkout #{phpwax}"
      end
    end
  
    ####### ##############
  
  
    # =============================================================================
    # GENERAL ADMIN FOR APPLICATIONS
    # =============================================================================
    
    desc "Restarts the Apache Server."
    task :restart do
      config_check
      needs_root
      with_user("root", "#{root_pass}") do 
        run "/etc/rc.d/init.d/httpd restart"
      end
    end
  
    task :clearcache do
      run "rm -f tmp/cache/*"
    end
  
    task :clearlogs do
      run "rm -f tmp/log/*"
    end
  
    
  
    # =============================================================================
    # USER AND APPLICATION SETUP AND INITIALISATION
    # =============================================================================
  
    desc "General setup task which creates a new user on the host, sets up a mysql database and login, creates an apache vhost file and finally generates an ssh key for the user."
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
      with_user("root", "#{root_pass}") do
        "#{databases}".each do |db|
          run "mysql -uroot -p#{root_pass} -e 'CREATE DATABASE #{db}'"
          run "musql -uroot -p#{root_pass} -e 'GRANT ALL PRIVILEGES ON `#{db}` . * TO '#{user_to_add}'@'localhost' IDENTIFIED BY '#{passwd_to_add}';"
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
        f = File.open('templates/apache_vhost.erb')
        contents = f.read
        f.close
        buffer = ERB.new(contents)
        config = buffer.result(binding())
        put config, "/etc/httpd/conf.d/#{application}-apache-vhost.conf"
      end
    
    end
    
    
  
    # =============================================================================
    # +MIGRATING+ APPLICATIONS
    # =============================================================================
  
    desc "Runs a backup of an application, copies to another server and then sets up on new server"
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




