# Resque root module
module Resque
  # Resque::Plugins root module
  module Plugins
    # Resque::Plugins::State is a module your jobs will include.
    # It provides helper methods for updating the status/etc from within an
    # instance as well as class methods for creating and queuing the jobs.
    #
    # All you have to do to get this functionality is include
    # Resque::Plugins::State and then implement a <tt>perform<tt> method.
    #
    # For example
    #
    #       class ExampleJob
    #         include Resque::Plugins::State
    #
    #         def perform
    #           num = options['num']
    #           i = 0
    #           while i < num
    #             i += 1
    #             at(i, num)
    #           end
    #           completed("Finished!")
    #         end
    #
    #       end
    #
    # This job would iterate num times updating the status as it goes. At the
    # end we update the status telling anyone listening to this job that its
    # complete.
    module State
      VERSION = '1.0.4'.freeze

      STATUS_QUEUED = 'queued'.freeze
      STATUS_WORKING = 'working'.freeze
      STATUS_COMPLETED = 'completed'.freeze
      STATUS_FAILED = 'failed'.freeze
      STATUS_KILLED = 'killed'.freeze
      STATUS_PAUSED = 'paused'.freeze
      STATUS_WAITING = 'waiting'.freeze
      STATUSES = [
        STATUS_QUEUED,
        STATUS_WORKING,
        STATUS_COMPLETED,
        STATUS_FAILED,
        STATUS_KILLED,
        STATUS_PAUSED,
        STATUS_WAITING
      ].freeze

      autoload :Hash, 'resque/plugins/state/hash'

      # The error class raised when a job is killed
      class Killed < RuntimeError; end
      class NotANumber < RuntimeError; end

      attr_reader :uuid, :options

      def self.included(base)
        base.extend(ClassMethods)
      end

      # Methods required for launching a state-ready job
      module ClassMethods
        # The default queue is :statused, this can be ovveridden in the specific
        # job class to put the jobs on a specific worker queue
        def queue
          :statused
        end

        # used when displaying the Job in the resque-web UI and identifiyng the
        # job type by status. By default this is the name of the job class, but
        # can be overidden in the specific job class to present a more user
        # friendly job name
        def name
          to_s
        end

        # Create is the primary method for adding jobs to the queue. This would
        # be called on the job class to create a job of that type. Any options
        # passed are passed to the Job instance as a hash of options. It returns
        # the UUID of the job.
        #
        # == Example:
        #
        #       class ExampleJob
        #         include Resque::Plugins::State
        #
        #         def perform
        #           job_status "Hey I'm a job num #{options['num']}"
        #         end
        #
        #       end
        #
        #       job_id = ExampleJob.create(:num => 100)
        #
        def create(options = {})
          enqueue(self, options)
        end

        # Adds a job of type <tt>klass<tt> to the queue with <tt>options<tt>.
        #
        # Returns the UUID of the job if the job was queued, or nil if the job
        # was rejected by a before_enqueue hook.
        def enqueue(klass, options = {})
          enqueue_to(Resque.queue_from_class(klass) || queue, klass, options)
        end

        # Adds a job of type <tt>klass<tt> to a specified queue with
        # <tt>options<tt>.
        #
        # Returns the UUID of the job if the job was queued, or nil if the job
        # was rejected by a before_enqueue hook.
        def enqueue_to(queue, klass, options = {})
          uuid = Resque::Plugins::State::Hash.generate_uuid
          Resque::Plugins::State::Hash.create uuid, options: options

          if Resque.enqueue_to(queue, klass, uuid, options)
            uuid
          else
            Resque::Plugins::State::Hash.remove(uuid)
            nil
          end
        end

        # Removes a job of type <tt>klass<tt> from the queue.
        #
        # The initially given options are retrieved from the status hash.
        # (Resque needs the options to find the correct queue entry)
        def dequeue(klass, uuid)
          status = Resque::Plugins::State::Hash.get(uuid)
          Resque.dequeue(klass, uuid, status.options)
        end

        # This is the method called by Resque::Worker when processing jobs. It
        # creates a new instance of the job class and populates it with the uuid
        # and options.
        #
        # You should not override this method, rahter the <tt>perform</tt>
        # instance method.
        def perform(uuid = nil, options = {})
          uuid ||= Resque::Plugins::State::Hash.generate_uuid
          instance = new(uuid, options)
          instance.safe_perform!
          instance
        end

        # Wrapper API to forward a Resque::Job creation API call into a
        # Resque::Plugins::State call.
        # This is needed to be used with resque scheduler
        # http://github.com/bvandenbos/resque-scheduler
        def scheduled(queue, _klass, *args)
          enqueue_to(queue, self, *args)
        end
      end

      # Create a new instance with <tt>uuid</tt> and <tt>options</tt>
      def initialize(uuid, options = {})
        @uuid    = uuid
        @options = options
        @logger = Resque.logger
      end

      # Run by the Resque::Worker when processing this job. It wraps the
      # <tt>perform</tt> method ensuring that the final status of the job is set
      # regardless of error. If an error occurs within the job's work, it will
      # set the status as failed and re-raise the error.
      def safe_perform!
        job_status('status' => STATUS_WORKING)
        messages = ['Job starting']
        @logger.info("#{@uuid}: #{messages.join(' ')}")
        perform
        if status && status.failed?
          on_failure(status.message) if respond_to?(:on_failure)
          return
        elsif status && !status.completed?
          completed
        end
        on_success if respond_to?(:on_success)
      rescue Killed
        Resque::Plugins::State::Hash.killed(uuid)
        on_killed if respond_to?(:on_killed)
      rescue => e
        failed("The task failed because of an error: #{e}")
        raise e unless respond_to?(:on_failure)
        on_failure(e)
      end

      # Set the jobs status. Can take an array of strings or hashes that are
      # merged (in order) into a final status hash.
      def status=(new_status)
        Resque::Plugins::State::Hash.set(uuid, *new_status)
      end

      # get the Resque::Plugins::State::Hash object for the current uuid
      def status
        Resque::Plugins::State::Hash.get(uuid)
      end

      def name
        "#{self.class.name}(#{options.inspect unless options.empty?})"
      end

      # Checks against the kill list if this specific job instance should be
      # killed on the next iteration
      def should_kill?
        Resque::Plugins::State::Hash.should_kill?(uuid)
      end

      # Checks against the pause list if this specific job instance should be
      # paused on the next iteration
      def should_pause?
        Resque::Plugins::State::Hash.should_pause?(uuid)
      end

      # Checks against the lock list if this specific job instance should wait
      # before starting
      def locked?(key)
        Resque::Plugins::State::Hash.locked?(key)
      end

      # set the status of the job for the current itteration. <tt>num</tt> and
      # <tt>total</tt> are passed to the status as well as any messages.
      # This will kill the job if it has been added to the kill list with
      # <tt>Resque::Plugins::State::Hash.kill()</tt>
      def at(num, total, *messages)
        if total.to_f <= 0.0
          raise(NotANumber,
                "Called at() with total=#{total} which is not a number")
        end
        tick({
               'num' => num,
               'total' => total
             }, *messages)
      end

      # sets the status of the job for the current itteration. You should use
      # the <tt>at</tt> method if you have actual numbers to track the iteration
      # count. This will kill or pause the job if it has been added to either
      # list with <tt>Resque::Plugins::State::Hash.pause()</tt> or
      # <tt>Resque::Plugins::State::Hash.kill()</tt> respectively
      def tick(*messages)
        kill! if should_kill?
        if should_pause?
          pause!
        else
          job_status({ 'status' => STATUS_WORKING }, *messages)
          @logger.info("Job #{@uuid}: #{messages.join(' ')}")
        end
      end

      # set the status to 'failed' passing along any additional messages
      def failed(*messages)
        job_status({ 'status' => STATUS_FAILED }, *messages)
        @logger.error("Job #{@uuid}: #{messages.join(' ')}")
      end

      # set the status to 'completed' passing along any addional messages
      def completed(*messages)
        job_status({
                     'status' => STATUS_COMPLETED,
                     'message' => "Completed at #{Time.now}"
                   }, *messages)
        @logger.info("Job #{@uuid}: #{messages.join(' ')}")
      end

      # kill the current job, setting the status to 'killed' and raising
      # <tt>Killed</tt>
      def kill!
        messages = ["Killed at #{Time.now}"]
        job_status('status' => STATUS_KILLED,
                   'message' => messages[0])
        @logger.error("Job #{@uuid}: #{messages.join(' ')}")
        raise Killed
      end

      # pause the current job, setting the status to 'paused' and sleeping 10
      # seconds
      def pause!
        Resque::Plugins::State::Hash.pause(uuid)
        messages = ["Paused at #{Time.now}"]
        job_status('status' => STATUS_PAUSED,
                   'message' => messages[0])
        raise Killed if @testing # Don't loop or complete during testing
        @logger.info("Job #{@uuid}: #{messages.join(' ')}")
        while should_pause?
          kill! if should_kill?
          sleep 10
        end
      end

      # lock against a provided or automatic key to prevent duplicate jobs
      def lock!(key = nil)
        lock = Digest::SHA1.hexdigest @options.to_json
        lock = key if key
        if locked?(lock)
          messages = ["Waiting at #{Time.now} due to existing job"]
          job_status('status' => STATUS_WAITING,
                     'message' => messages[0])
          while locked?(lock)
            kill! if should_kill?
            pause! if should_pause?
            sleep 10
          end
        else
          Resque::Plugins::State::Hash.lock(lock)
        end
      end

      # unlock the provided or automatic key at the end of a job
      def unlock!(key = nil)
        lock = Digest::SHA1.hexdigest @options.to_json
        lock = key if key
        Resque::Plugins::State::Hash.unlock(lock)
      end

      private

      def job_status(*args)
        self.status = [status, { 'name' => name }, args].flatten
      end
    end
  end
end
