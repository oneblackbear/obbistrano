# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{obbistrano}
  s.version = "1.1.156"
  s.authors = ["Ross Riley", "One Black Bear"]
  s.license = 'MIT'
  s.date = Time.now
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.description = %q{An extension to Capistrano to handle deploys for One Black Bear}
  s.email = %q{ross@oneblackbear.com}
  s.files = ["README.textile", "obbistrano.gemspec", "lib/obbistrano.rb", "lib/obbistrano_tasks.rb", "lib/templates/apache_vhost.erb"]
  s.homepage = %q{http://github.com/oneblackbear/obbistrano}
  s.rubygems_version = %q{1.3.0}
  s.summary = %q{Adds extra namespaces to Capistrano to allow simple setup, deploys and maintenance.}


  s.add_dependency 'capistrano', "~> 2.13.5"
  s.add_dependency 'colored', ">= 1.2.0"
  s.add_dependency 'inifile', ">= 2.0.2"
  s.add_dependency 'capistrano-maintenance', '0.0.2'

end