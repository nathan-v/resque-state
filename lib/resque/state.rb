require 'resque'

module Resque
  autoload :JobWithState, "#{File.dirname(__FILE__)}/job_with_state"
  module Plugins
    autoload :State, "#{File.dirname(__FILE__)}/plugins/state"
  end
end
