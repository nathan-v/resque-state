if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter 'test'
    command_name 'Mintest'
  end
end

require 'bundler/setup'
require 'resque-state'
require 'minitest/autorun'
require 'mocha/setup'
require 'fakeredis'

Resque.redis = Redis.new

#### Fixtures

class WorkingJob
  include Resque::Plugins::State

  def perform
    total = options['num']
    (1..total).each do |num|
      at(num, total, "At #{num}")
    end
  end
end

class ErrorJob
  include Resque::Plugins::State

  def perform
    raise "I'm a bad little job"
  end
end

class ErrorJobOnFailure
  include Resque::Plugins::State

  def perform
    raise "I'm a bad little job"
  end

  def on_failure(_e, *_args)
    failed("I'm such a terrible failure")
  end
end

class KillableJob
  include Resque::Plugins::State

  def perform
    Resque.redis.set("#{uuid}:iterations", 0)
    100.times do |num|
      Resque.redis.incr("#{uuid}:iterations")
      at(num, 100, "At #{num} of 100")
    end
  end
end

class SleeperJob
  include Resque::Plugins::State

  def perform
    @testing = true
    Resque.redis.set("#{uuid}:iterations", 0)
    100.times do |num|
      Resque.redis.incr("#{uuid}:iterations")
      at(num, 100, "At #{num} of 100")
    end
  end
end

class BasicJob
  include Resque::Plugins::State
end

class FailureJob
  include Resque::Plugins::State

  def perform
    failed("I'm such a failure")
  end
end

class NeverQueuedJob
  include Resque::Plugins::State

  def self.before_enqueue(*_args)
    false
  end

  def perform
    # will never get called
  end
end
