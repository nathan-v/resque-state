# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: resque-state 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = 'resque-state'
  s.version = '1.0.0'

  s.required_rubygems_version = Gem::Requirement.new('>= 0') if s.respond_to? :required_rubygems_version=
  s.require_paths = ['lib']
  s.authors = ['Aaron Quint', 'Nathan V']
  s.date = '2016-08-27'
  s.description = 'resque-state is an extension to the resque queue system that provides simple trackable jobs. It provides a Resque::Plugins::State::Hash class which can set/get the statuses of jobs and a Resque::Plugins::State class that, when included, provides easily trackable/killable/pausable jobs.'
  s.email = 'nathan.v@gmail.com'
  s.extra_rdoc_files = [
    'LICENSE',
    'README.rdoc'
  ]
  s.files = [
    '.travis.yml',
    'Gemfile',
    'Gemfile.lock',
    'LICENSE',
    'README.rdoc',
    'Rakefile',
    'examples/sleep_job.rb',
    'init.rb',
    'lib/resque-state.rb',
    'lib/resque/job_with_state.rb',
    'lib/resque/plugins/state.rb',
    'lib/resque/plugins/state/hash.rb',
    'lib/resque/server/views/state.erb',
    'lib/resque/server/views/state_styles.erb',
    'lib/resque/server/views/statuses.erb',
    'lib/resque/state.rb',
    'lib/resque/state_server.rb',
    'resque-state.gemspec',
    'test/test_helper.rb',
    'test/test_resque_plugins_state.rb',
    'test/test_resque_plugins_state_hash.rb'
  ]
  s.homepage = 'http://github.com/nathan-v/resque-state'
  s.licenses = ['MIT']
  s.rubyforge_project = 'nathan-v'
  s.rubygems_version = '2.5.1'
  s.summary = 'resque-state is an extension to the resque queue system that provides simple trackable jobs.'

  if s.respond_to? :specification_version
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0')
      s.add_runtime_dependency('resque', ['~> 1.19'])
      s.add_development_dependency('jeweler', ['~> 2.1'])
    else
      s.add_dependency('resque', ['~> 1.19'])
      s.add_dependency('jeweler', ['~> 2.1'])
    end
  else
    s.add_dependency('resque', ['~> 1.19'])
    s.add_dependency('jeweler', ['~> 2.1'])
  end
end
