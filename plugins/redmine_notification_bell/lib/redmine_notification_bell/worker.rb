module RedmineNotificationBell
  class Worker
    POLL_INTERVAL = 3
    MAX_ATTEMPTS  = 3

    class << self
      def start!
        return if @started
        @started = true
        @thread = Thread.new do
          Rails.logger.info "[NotificationBell] Worker started pid=#{Process.pid}"
          new.run
        end
        @thread.abort_on_exception = false
      end
    end

    def run
      loop do
        begin
          drain_queue
        rescue => e
          Rails.logger.error "[NotificationBell] Worker loop error: #{e.class}: #{e.message}"
        end
        sleep POLL_INTERVAL
      end
    end

    private

    # Process all pending jobs in one cycle instead of one-per-sleep.
    # Stops when no pending job is found.
    def drain_queue
      loop do
        processed = process_next_job
        break unless processed
      end
    end

    # Claims and processes one job. Returns true if a job was found, false if
    # the queue is empty. All DB work is inside with_connection so the rescue
    # block can safely call update_columns on the same checked-out connection.
    def process_next_job
      ActiveRecord::Base.connection_pool.with_connection do
        job = claim_next_job
        return false unless job

        begin
          journal = Journal.find_by(id: job.journal_id)

          if journal.nil?
            job.update_columns(
              status:     NotificationBellQueue::FAILED,
              last_error: "Journal #{job.journal_id} not found",
              updated_at: Time.now.utc
            )
            Rails.logger.warn "[NotificationBell] Job #{job.id}: journal #{job.journal_id} not found"
            return true
          end

          NotificationBell.create_for_mentions(journal)

          job.update_columns(status: NotificationBellQueue::DONE, updated_at: Time.now.utc)
          Rails.logger.info "[NotificationBell] Job #{job.id} done (journal #{job.journal_id})"
        rescue => e
          Rails.logger.error "[NotificationBell] Job #{job.id} error: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
          next_attempt = job.attempts + 1
          job.update_columns(
            status:     next_attempt >= MAX_ATTEMPTS ? NotificationBellQueue::FAILED : NotificationBellQueue::PENDING,
            attempts:   next_attempt,
            last_error: e.message.to_s.truncate(500),
            run_at:     next_attempt < MAX_ATTEMPTS ? Time.now.utc + (2**next_attempt * 15) : nil,
            updated_at: Time.now.utc
          )
        end

        true
      end
    end

    # Atomically marks one pending job as PROCESSING and returns it.
    # FOR UPDATE SKIP LOCKED prevents multiple Passenger worker processes
    # from claiming the same job simultaneously.
    def claim_next_job
      NotificationBellQueue.transaction do
        job = NotificationBellQueue
                .where(status: NotificationBellQueue::PENDING)
                .where('run_at IS NULL OR run_at <= ?', Time.now.utc)
                .order(:created_at)
                .limit(1)
                .lock('FOR UPDATE SKIP LOCKED')
                .first
        job&.update_columns(status: NotificationBellQueue::PROCESSING, updated_at: Time.now.utc)
        job
      end
    end
  end
end
