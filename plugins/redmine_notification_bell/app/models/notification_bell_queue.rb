class NotificationBellQueue < ActiveRecord::Base
  self.table_name = 'notification_bell_jobs'

  PENDING    = 'pending'.freeze
  PROCESSING = 'processing'.freeze
  DONE       = 'done'.freeze
  FAILED     = 'failed'.freeze
end
