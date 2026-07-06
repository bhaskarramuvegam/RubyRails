module RedmineNotificationBell
  module JournalPatch
    def self.included(base)
      base.after_commit :nb_detect_mentions,        on: :create
      base.after_commit :nb_detect_mentions_update, on: :update
    end

    private

    def nb_detect_mentions
      NotificationBell.create_for_mentions(self)
    rescue => e
      Rails.logger.error "[NotificationBell] nb_detect_mentions raised: #{e.class}: #{e.message}"
    end

    def nb_detect_mentions_update
      return unless previous_changes.key?('notes')
      return if notes.blank?
      NotificationBell.create_for_mentions(self)
    rescue => e
      Rails.logger.error "[NotificationBell] nb_detect_mentions_update raised: #{e.class}: #{e.message}"
    end
  end
end

Rails.configuration.to_prepare do
  unless Journal.ancestors.include?(RedmineNotificationBell::JournalPatch)
    Journal.include(RedmineNotificationBell::JournalPatch)
    Rails.logger.error "[NotificationBell] JournalPatch applied — after_commit on create+update registered"
  end
end
