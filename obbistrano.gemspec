# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{obbistrano}
  s.version = "1.1.58"
  s.authors = ["Ross Riley", "One Black Bear"]
  s.date = Time.now
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.description = %q{An extension to Capistrano to allow deploys to Slicehost for One Black Bear}
  s.email = %q{ross@oneblackbear.com}
  s.files = ["README.textile", "obbistrano.gemspec", "lib/obbistrano.rb","lib/githubapi.rb", "lib/slicehost.rb", "lib/obbistrano_tasks.rb", "lib/templates/apache_vhost.erb"] 
  s.homepage = %q{http://github.com/oneblackbear/obbistrano}
  s.rubygems_version = %q{1.3.0}
  s.summary = %q{Adds extra namespaces to Capistrano to allow simple setup, deploys and maintenance.}
  if s.respond_to? :specification_version then
      current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
      s.specification_version = 2

      if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
        s.add_runtime_dependency(%q<capistrano>, [">= 2.5"])
        s.add_runtime_dependency(%q<activeresource>, [">= 2"])
        s.add_runtime_dependency(%q<httparty>, [">= 0.4.3"])
      else
        s.add_dependency(%q<capistrano>, [">= 2.5"])
        s.add_dependency(%q<activeresource>, [">= 2"])
        s.add_dependency(%q<httparty>, [">= 0.4.3"])
      end
    else
      s.add_dependency(%q<capistrano>, [">= 2.5"])
      s.add_dependency(%q<activeresource>, [">= 2"])
      s.add_dependency(%q<httparty>, [">= 0.4.3"])
    end
end