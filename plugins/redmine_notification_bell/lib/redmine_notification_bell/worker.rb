module RedmineNotificationBell
  class Worker
    POLL_INTERVAL = 3    # seconds between queue polls
    MAX_ATTEMPTS  = 3    # give up after this many consecutive errors

    class << self
      def start!
        return if @started
        @started = true
        @thread  = Thread.new do
          Rails.logger.info "[NotificationBell] Worker started pid=#{Process.pid}"
          new.run
        end
        @thread.abort_on_exception = false
      end
    end

    def run
      loop do
        begin
          process_next_job
        rescue => e
          Rails.logger.error "[NotificationBell] Worker loop error: #{e.class}: #{e.message}"
        end
        sleep POLL_INTERVAL
      end
    end

    private

    def process_next_job
      job = nil

      ActiveRecord::Base.connection_pool.with_connection do
        # Lock a single pending/retryable job atomically.
        # FOR UPDATE SKIP LOCKED lets multiple Passenger workers run workers
        # concurrently without processing the same job twice.
        NotificationBellQueue.transaction do
          job = NotificationBellQueue
            .where(status: NotificationBellQueue::PENDING)
            .where('run_at IS NULL OR run_at <= ?', Time.now.utc)
            .order(:created_at)
            .limit(1)
            .lock('FOR UPDATE SKIP LOCKED')
            .first

          job&.update_columns(
            status:     NotificationBellQueue::PROCESSING,
            updated_at: Time.now.utc
          )
        end

        return unless job

        journal = Journal.find_by(id: job.journal_id)

        if journal.nil?
          job.update_columns(
            status:     NotificationBellQueue::FAILED,
            last_error: "Journal #{job.journal_id} not found",
            updated_at: Time.now.utc
          )
          Rails.logger.warn "[NotificationBell] Job #{job.id}: journal #{job.journal_id} missing"
          return
        end

        NotificationBell.create_for_mentions(journal)

        job.update_columns(
          status:     NotificationBellQueue::DONE,
          updated_at: Time.now.utc
        )
        Rails.logger.info "[NotificationBell] Job #{job.id} done (journal #{job.journal_id})"
      end
    rescue => e
      Rails.logger.error "[NotificationBell] Job #{job&.id} error: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      if job
        next_attempt = job.attempts + 1
        next_run_at  = next_attempt < MAX_ATTEMPTS ? Time.now.utc + (2**next_attempt * 15) : nil
        job.update_columns(
          status:     next_attempt >= MAX_ATTEMPTS ? NotificationBellQueue::FAILED : NotificationBellQueue::PENDING,
          attempts:   next_attempt,
          last_error: e.message.truncate(500),
          run_at:     next_run_at,
          updated_at: Time.now.utc
        )
      end
    end
  end
end
