module Resque
  # Add the class for stateful jobs
  class JobWithState
    include Resque::Plugins::State
  end
end
