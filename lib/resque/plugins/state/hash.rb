require 'securerandom'

module Resque
  module Plugins
    module State
      # Resque::Plugins::State::Hash is a Hash object that has helper methods
      # for dealing with the common status attributes. It also has a number of
      # class methods for creating/updating/retrieving status objects from Redis
      class Hash < ::Hash
        # Create a status, a new UUID, passing the message to the status
        # Returns the UUID of the new status.
        def self.create(uuid, *messages)
          set(uuid, *messages)
          redis.zadd(set_key, Time.now.to_i, uuid)
          if @expire_in
            redis.zremrangebyscore(
              set_key, 0, Time.now.to_i - @expire_in
            )
          end
          uuid
        end

        # Get a status by UUID. Returns a Resque::Plugins::State::Hash
        def self.get(uuid)
          val = redis.get(status_key(uuid))
          val ? Resque::Plugins::State::Hash.new(uuid, decode(val)) : nil
        end

        # Get statuses by UUID. Returns array of Resque::Plugins::State::Hash
        def self.mget(uuids)
          return [] if uuids.empty?
          status_keys = uuids.map { |u| status_key(u) }
          vals = redis.mget(*status_keys)

          uuids.zip(vals).map do |uuid, val|
            val ? Resque::Plugins::State::Hash.new(uuid, decode(val)) : nil
          end
        end

        # set a status by UUID. <tt>messages</tt> can be any number of strings
        # or hashes that are merged in order to create a single status.
        def self.set(uuid, *messages)
          val = Resque::Plugins::State::Hash.new(uuid, *messages)
          redis.set(status_key(uuid), encode(val))
          redis.expire(status_key(uuid), expire_in) if expire_in
          val
        end

        # clear statuses from redis passing an optional range. See `statuses`
        # for info about ranges
        def self.clear(range_start = nil, range_end = nil)
          status_ids(range_start, range_end).each do |id|
            remove(id)
          end
        end

        def self.clear_completed(range_start = nil, range_end = nil)
          status_ids(range_start, range_end).select do |id|
            if get(id).completed?
              remove(id)
              true
            else
              false
            end
          end
        end

        def self.clear_failed(range_start = nil, range_end = nil)
          status_ids(range_start, range_end).select do |id|
            if get(id).failed?
              remove(id)
              true
            else
              false
            end
          end
        end

        def self.count
          redis.zcard(set_key)
        end

        def self.remove(uuid)
          redis.del(status_key(uuid))
          redis.zrem(set_key, uuid)
        end

        # Return <tt>num</tt> Resque::Plugins::State::Hash objects in reverse
        # chronological order.
        # By default returns the entire set.
        # @param [Numeric] range_start The optional starting range
        # @param [Numeric] range_end The optional ending range
        # @example retuning the last 20 statuses
        #   Resque::Plugins::State::Hash.statuses(0, 20)
        def self.statuses(range_start = nil, range_end = nil)
          ids = status_ids(range_start, range_end)
          mget(ids).compact || []
        end

        # Return the <tt>num</tt> most recent status/job UUIDs in reverse
        # chronological order.
        def self.status_ids(range_start = nil, range_end = nil)
          if range_end && range_start
            # Because we want a reverse chronological order, we need to get a
            # range starting by the higest negative number. The ordering is
            # transparent from the API user's perspective so we need to convert
            # the passed params
            (redis.zrevrange(set_key, range_start.abs, (range_end || 1).abs) || [])
          else
            # Because we want a reverse chronological order, we need to get a
            # range starting by the higest negative number.
            redis.zrevrange(set_key, 0, -1) || []
          end
        end

        # Kill the job at UUID on its next iteration this works by adding the UUID to a
        # kill list (a.k.a. a list of jobs to be killed. Each iteration the job checks
        # if it _should_ be killed by calling <tt>tick</tt> or <tt>at</tt>. If so, it raises
        # a <tt>Resque::Plugins::State::Killed</tt> error and sets the status to 'killed'.
        def self.kill(uuid)
          redis.sadd(kill_key, uuid)
        end

        # Remove the job at UUID from the kill list
        def self.killed(uuid)
          redis.srem(kill_key, uuid)
        end

        # Return the UUIDs of the jobs on the kill list
        def self.kill_ids
          redis.smembers(kill_key)
        end

        # Kills <tt>num</tt> jobs within range starting with the most recent first.
        # By default kills all jobs.
        # Note that the same conditions apply as <tt>kill</tt>, i.e. only jobs that check
        # on each iteration by calling <tt>tick</tt> or <tt>at</tt> are eligible to killed.
        # @param [Numeric] range_start The optional starting range
        # @param [Numeric] range_end The optional ending range
        # @example killing the last 20 submitted jobs
        #   Resque::Plugins::State::Hash.killall(0, 20)
        def self.killall(range_start = nil, range_end = nil)
          status_ids(range_start, range_end).collect do |id|
            kill(id)
          end
        end

        # Check whether a job with UUID is on the kill list
        def self.should_kill?(uuid)
          redis.sismember(kill_key, uuid)
        end

        # pause the job at UUID on its next iteration this works by adding the UUID to a
        # pause list (a.k.a. a list of jobs to be pauseed. Each iteration the job checks
        # if it _should_ be pauseed by calling <tt>tick</tt> or <tt>at</tt>. If so, it sleeps
        # for 10 seconds before checking again if it should continue sleeping
        def self.pause(uuid)
          redis.sadd(pause_key, uuid)
        end

        # Remove the job at UUID from the pause list
        def self.unpause(uuid)
          redis.srem(pause_key, uuid)
        end

        # Return the UUIDs of the jobs on the pause list
        def self.pause_ids
          redis.smembers(pause_key)
        end

        # pauses <tt>num</tt> jobs within range starting with the most recent first.
        # By default pauses all jobs.
        # Note that the same conditions apply as <tt>pause</tt>, i.e. only jobs that check
        # on each iteration by calling <tt>tick</tt> or <tt>at</tt> are eligible to pauseed.
        # @param [Numeric] range_start The optional starting range
        # @param [Numeric] range_end The optional ending range
        # @example pauseing the last 20 submitted jobs
        #   Resque::Plugins::State::Hash.pauseall(0, 20)
        def self.pauseall(range_start = nil, range_end = nil)
          status_ids(range_start, range_end).collect do |id|
            pause(id)
          end
        end

        # Check whether a job with UUID is on the pause list
        def self.should_pause?(uuid)
          redis.sismember(pause_key, uuid)
        end

        # revert the job at UUID on its next iteration this works by adding the UUID to a
        # revert list (a.k.a. a list of jobs to be reverted. Each iteration the job checks
        # if it _should_ be reverted by calling <tt>tick</tt> or <tt>at</tt>. If so, it sleeps
        # for 10 seconds before checking again if it should continue sleeping
        def self.revert(uuid)
          redis.sadd(revert_key, uuid)
        end

        # Remove the job at UUID from the revert list; needed to handle jobs
        # that don't support revert
        def self.no_revert(uuid)
          redis.srem(revert_key, uuid)
        end

        # Return the UUIDs of the jobs on the revert list
        def self.revert_ids
          redis.smembers(revert_key)
        end

        # Check whether a job with UUID is on the revert list
        def self.should_revert?(uuid)
          redis.sismember(revert_key, uuid)
        end

        # Set a lock key to allow jobs to run as singletons. Optional timeout in
        # seconds
        def self.lock(key, timeout = 3600)
          redis.setnx("_lock-#{key}", key)
          redis.expire("_lock-#{key}", timeout)
        end

        # Remove a key from the lock list
        def self.unlock(key)
          redis.srem("_lock-#{key}", key)
        end

        # Check whether a key on the wait list
        def self.locked?(key)
          redis.sismember("_lock-#{key}", key)
        end

        # The time in seconds that jobs and statuses should expire from Redis
        # (after the last time they are touched/updated)
        class << self
          attr_reader :expire_in
        end

        # Set the <tt>expire_in</tt> time in seconds
        def self.expire_in=(seconds)
          @expire_in = seconds.nil? ? nil : seconds.to_i
        end

        def self.status_key(uuid)
          "status:#{uuid}"
        end

        def self.set_key
          '_statuses'
        end

        def self.kill_key
          '_kill'
        end

        def self.pause_key
          '_pause'
        end

        def self.revert_key
          '_revert'
        end

        def self.generate_uuid
          SecureRandom.hex.to_s
        end

        def self.hash_accessor(name, options = {})
          options[:default] ||= nil
          coerce = options[:coerce] ? ".#{options[:coerce]}" : ''
          module_eval <<-EOT
          def #{name}
            value = (self['#{name}'] ? self['#{name}']#{coerce} : #{options[:default].inspect})
            yield value if block_given?
            value
          end

          def #{name}=(value)
            self['#{name}'] = value
          end

          def #{name}?
            !!self['#{name}']
          end
          EOT
        end

        # Proxy deprecated methods directly back to Resque itself.
        class << self
          [:redis, :encode, :decode].each do |method|
            define_method(method) { |*args| Resque.send(method, *args) }
          end
        end

        hash_accessor :uuid
        hash_accessor :name
        hash_accessor :status
        hash_accessor :message
        hash_accessor :time
        hash_accessor :options

        hash_accessor :num
        hash_accessor :total

        # Create a new Resque::Plugins::State::Hash object. If multiple
        # arguments are passed it is assumed the first argument is the UUID and
        # the rest are status objects. All arguments are subsequentily merged in
        # order. Strings are assumed to be messages.
        def initialize(*args)
          super nil
          base_status = {
            'time' => Time.now.to_i,
            'status' => Resque::Plugins::State::STATUS_QUEUED
          }
          base_status['uuid'] = args.shift if args.length > 1
          status_hash = args.inject(base_status) do |final, m|
            m = { 'message' => m } if m.is_a?(String)
            final.merge(m || {})
          end
          replace(status_hash)
        end

        # calculate the % completion of the job based on <tt>status</tt>,
        # <tt>num</tt> and <tt>total</tt>
        def pct_complete
          if completed?
            100
          elsif queued?
            0
          elsif failed?
            0
          else
            t = if total.nil?
                  1
                else total
                end
            (((num || 0).to_f / t.to_f) * 100).to_i
          end
        end

        # Return the time of the status initialization. If set returns a
        # <tt>Time</tt> object, otherwise returns nil
        def time
          time? ? Time.at(self['time']) : nil
        end

        Resque::Plugins::State::STATUSES.each do |status|
          define_method("#{status}?") do
            self['status'] === status
          end
        end

        # Can the job be killed? failed, completed, reverted, and killed jobs
        # can't be killed, for obvious reasons
        def killable?
          !failed? && !completed? && !killed? && !reverted?
        end

        # Can the job be paused? failed, completed, paused, reverted, and killed
        # jobs can't be paused, for obvious reasons
        def pausable?
          !failed? && !completed? && !killed? && !paused? && !reverted?
        end

        # Can the job be reverted? failed, completed, reverted, and killed jobs
        # can't be paused, for obvious reasons
        def pausable?
          !failed? && !completed? && !killed? && !reverted?
        end

        unless method_defined?(:to_json)
          def to_json(*_args)
            json
          end
        end

        # Return a JSON representation of the current object.
        def json
          h = dup
          h['pct_complete'] = pct_complete
          self.class.encode(h)
        end

        def inspect
          "#<Resque::Plugins::State::Hash #{super}>"
        end
      end
    end
  end
end
