module RedmineNotificationBell
  module JournalPatch
    def self.included(base)
      # after_create fires after INSERT, still inside the outer transaction.
      # Each notification INSERT is wrapped in a savepoint (requires_new: true)
      # in create_for_mentions so a failure there cannot abort the issue-save
      # transaction in PostgreSQL.
      base.after_create :nb_detect_mentions
    end

    private

    def nb_detect_mentions
      NotificationBell.create_for_mentions(self)
    rescue => e
      Rails.logger.error "[NotificationBell] nb_detect_mentions raised: #{e.class}: #{e.message}"
    end
  end
end

Rails.configuration.to_prepare do
  unless Journal.ancestors.include?(RedmineNotificationBell::JournalPatch)
    Journal.include(RedmineNotificationBell::JournalPatch)
    Rails.logger.error "[NotificationBell] JournalPatch applied to Journal — after_create :nb_detect_mentions registered"
  end
end
