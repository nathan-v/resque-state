require 'resque'

# Resque root module
module Resque
  autoload :JobWithState, "#{File.dirname(__FILE__)}/job_with_state"
  # Resque::Plugins root module
  module Plugins
    autoload :State, "#{File.dirname(__FILE__)}/plugins/state"
  end
end
