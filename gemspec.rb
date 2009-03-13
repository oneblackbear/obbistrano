# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{obbistrano}
  s.version = "1.0.0"
  s.authors = ["Ross Riley", "One Black Bear"]
  s.date = Time.now
  s.description = %q{An extension to Capistrano to allow deploys to Slicehost for One Black Bear}
  s.email = %q{ross@oneblackbear.com}
  s.files = ["README.txt", "capfile", "templates/*"] 
  s.homepage = %q{http://github.com/oneblackbear/obbistrano}
  s.rubygems_version = %q{1.3.0}
  s.summary = %q{Adds extra namespaces to Capistrano to allow simple setup, deploys and maintenance.}
  s.add_dependency('capistrano', '>= 2')
  s.add_dependency('activeresource', '>= 2')
end