require 'test_helper'

# rubocop:disable Metrics/ClassLength
class TestResquePluginsStatusHash < Minitest::Test
  describe 'Resque::Plugins::State::Hash' do
    before do
      Redis.current.flushdb
      Resque::Plugins::State::Hash.expire_in = nil
      @uuid = Resque::Plugins::State::Hash.create(
        Resque::Plugins::State::Hash.generate_uuid
      )
      Resque::Plugins::State::Hash.set(@uuid, 'my status')
      @uuid_with_json = Resque::Plugins::State::Hash.create(
        Resque::Plugins::State::Hash.generate_uuid, 'im' => 'json'
      )
    end

    describe '.get' do
      it 'return the status as a Resque::Plugins::State::Hash for the uuid' do
        status = Resque::Plugins::State::Hash.get(@uuid)
        assert status.is_a?(Resque::Plugins::State::Hash)
        assert_equal 'my status', status.message
      end

      it 'return nil if the status is not set' do
        assert_nil Resque::Plugins::State::Hash.get('invalid_uuid')
      end

      it 'decode encoded json' do
        assert_equal('json',
                     Resque::Plugins::State::Hash.get(@uuid_with_json)['im'])
      end
    end

    describe '.mget' do
      it 'return statuses array of Resque::Plugins::State::Hash for uuids' do
        uuid2 = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid
        )
        Resque::Plugins::State::Hash.set(uuid2, 'my status2')
        statuses = Resque::Plugins::State::Hash.mget([@uuid, uuid2])
        assert_equal 2, statuses.size
        assert statuses.all? { |s| s.is_a?(Resque::Plugins::State::Hash) }
        assert_equal ['my status', 'my status2'], statuses.map(&:message)
      end

      it 'return nil if a status is not set' do
        statuses = Resque::Plugins::State::Hash.mget(['invalid_uuid', @uuid])
        assert_equal 2, statuses.size
        assert_nil statuses[0]
        assert statuses[1].is_a?(Resque::Plugins::State::Hash)
        assert_equal 'my status', statuses[1].message
      end

      it 'decode encoded json' do
        assert_equal ['json'],
                     Resque::Plugins::State::Hash.mget(
                       [@uuid_with_json]
                     ).map { |h| h['im'] }
      end
    end

    describe '.set' do
      it 'set the status for the uuid' do
        assert Resque::Plugins::State::Hash.set(@uuid, 'updated')
        assert_equal 'updated', Resque::Plugins::State::Hash.get(@uuid).message
      end

      it 'return the status' do
        assert Resque::Plugins::State::Hash.set(
          @uuid, 'updated'
        ).is_a?(Resque::Plugins::State::Hash)
      end
    end

    describe '.create' do
      it 'add an item to a key set' do
        before = Resque::Plugins::State::Hash.status_ids.length
        Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid
        )
        after = Resque::Plugins::State::Hash.status_ids.length
        assert_equal 1, after - before
      end

      it 'return a uuid' do
        assert_match(/^\w{32}$/, Resque::Plugins::State::Hash.create(
                                   Resque::Plugins::State::Hash.generate_uuid
        ))
      end

      it 'store any status passed' do
        uuid = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid, 'initial status'
        )
        status = Resque::Plugins::State::Hash.get(uuid)
        assert status.is_a?(Resque::Plugins::State::Hash)
        assert_equal 'initial status', status.message
      end

      it 'expire keys if expire_in is set' do
        Resque::Plugins::State::Hash.expire_in = 1
        uuid = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid, 'new status'
        )
        assert_includes Resque::Plugins::State::Hash.status_ids, uuid
        assert_equal 'new status',
                     Resque::Plugins::State::Hash.get(uuid).message
        sleep 2
        Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid
        )
        refute_includes Resque::Plugins::State::Hash.status_ids, uuid
        assert_nil Resque::Plugins::State::Hash.get(uuid)
      end

      it 'store the options for the job created' do
        uuid = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid,
          'new', options: { 'test' => '123' }
        )
        assert uuid
        status = Resque::Plugins::State::Hash.get(uuid)
        assert status.is_a?(Resque::Plugins::State::Hash)
        assert_equal '123', status.options['test']
      end
    end

    describe '.clear' do
      before do
        Resque::Plugins::State::Hash.clear
      end

      it 'clear any statuses' do
        assert_nil Resque::Plugins::State::Hash.get(@uuid)
      end

      it 'clear any recent statuses' do
        assert Resque::Plugins::State::Hash.status_ids.empty?
      end
    end

    describe '.clear_completed' do
      before do
        @completed_status_id = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid, 'status' => 'completed'
        )
        @not_completed_status_id = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid
        )
        Resque::Plugins::State::Hash.clear_completed
      end

      it 'clear completed status' do
        assert_nil Resque::Plugins::State::Hash.get(@completed_status_id)
      end

      it 'not clear not-completed status' do
        status = Resque::Plugins::State::Hash.get(@not_completed_status_id)
        assert status.is_a?(Resque::Plugins::State::Hash)
      end
    end

    describe '.clear_failed' do
      before do
        @failed_status_id = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid, 'status' => 'failed'
        )
        @not_failed_status_id = Resque::Plugins::State::Hash.create(
          Resque::Plugins::State::Hash.generate_uuid
        )
        Resque::Plugins::State::Hash.clear_failed
      end

      it 'clear failed status' do
        assert_nil Resque::Plugins::State::Hash.get(@failed_status_id)
      end

      it 'not clear not-failed status' do
        status = Resque::Plugins::State::Hash.get(@not_failed_status_id)
        assert status.is_a?(Resque::Plugins::State::Hash)
      end
    end

    describe '.remove' do
      before do
        Resque::Plugins::State::Hash.remove(@uuid)
      end

      it 'clear specify status' do
        assert_nil Resque::Plugins::State::Hash.get(@uuid)
      end
    end

    describe '.status_ids' do
      before do
        @uuids = []
        30.times do
          Resque::Plugins::State::Hash.create(
            Resque::Plugins::State::Hash.generate_uuid
          )
        end
      end

      it 'return an array of job ids' do
        assert Resque::Plugins::State::Hash.status_ids.is_a?(Array)
        assert_equal 32, Resque::Plugins::State::Hash.status_ids.size # 30 + 2
      end

      it 'let you paginate through the statuses' do
        assert_equal Resque::Plugins::State::Hash.status_ids[0, 10],
                     Resque::Plugins::State::Hash.status_ids(0, 9)
        assert_equal Resque::Plugins::State::Hash.status_ids[10, 10],
                     Resque::Plugins::State::Hash.status_ids(10, 19)
      end
    end

    describe '.statuses' do
      it 'return an array status objects' do
        statuses = Resque::Plugins::State::Hash.statuses
        assert statuses.is_a?(Array)
        assert_equal [@uuid_with_json, @uuid].sort, statuses.map(&:uuid).sort
      end

      it 'return an empty array when no statuses are available' do
        Redis.current.flushdb
        statuses = Resque::Plugins::State::Hash.statuses
        assert_equal [], statuses
      end
    end

    Resque::Plugins::State::STATUSES.each do |status_code|
      describe ".#{status_code}?" do
        before do
          uuid = Resque::Plugins::State::Hash.create(
            Resque::Plugins::State::Hash.generate_uuid,
            'status' => status_code
          )
          @status = Resque::Plugins::State::Hash.get(uuid)
        end

        it 'return true for the current status' do
          assert @status.send("#{status_code}?"), status_code
        end

        it 'return false for other statuses' do
          other_codes = Resque::Plugins::State::STATUSES - [status_code]
          other_codes.each do |other_status_code|
            assert !@status.send("#{other_status_code}?"), other_status_code
          end
        end
      end
    end
  end
end
