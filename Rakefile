$LOAD_PATH.unshift './lib'

require 'rake'
require 'resque-state'
require 'resque/tasks'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = 'resque-state'
    gem.version = Resque::Plugins::State::VERSION.dup
    gem.summary = %(resque-state is an extension to the resque queue system
      that provides simple trackable jobs.).gsub("\n", ' ').squeeze(' ')
    gem.description = %(resque-state is an extension to the resque queue
      system that provides simple trackable jobs. It provides a
      Resque::Plugins::State::Hash class which can set/get the statuses of jobs
      and a Resque::Plugins::State class that, when included, provides easily
      trackable/killable/pausable jobs.).gsub("\n", ' ').squeeze(' ')
    gem.email = 'nathan.v@gmail.com'
    gem.homepage = 'http://github.com/nathan-v/resque-state'
    gem.rubyforge_project = 'nathan-v'
    gem.authors = ['Aaron Quint', 'Nathan V']
    gem.licenses = 'MIT'
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20
    #  for additional settings
  end
  Jeweler::RubygemsDotOrgTasks.new
rescue LoadError
  puts 'Jeweler (or a dependency) not available. Install it with: gem install'\
  ' jeweler'.gsub("\n", ' ').squeeze(' ')
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

desc 'Generates a coverage report'
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task['test'].execute
end

task :test

task default: :coverage
