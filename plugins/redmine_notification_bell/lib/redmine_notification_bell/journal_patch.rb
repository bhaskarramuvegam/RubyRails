module RedmineNotificationBell
  module JournalPatch
    def self.included(base)
      base.after_commit :nb_enqueue_mentions,        on: :create
      base.after_commit :nb_enqueue_mentions_update, on: :update
    end

    private

    def nb_enqueue_mentions
      NotificationBell.enqueue_for_mentions(self)
    rescue => e
      Rails.logger.error "[NotificationBell] nb_enqueue_mentions error: #{e.class}: #{e.message}"
    end

    def nb_enqueue_mentions_update
      return unless previous_changes.key?('notes')
      return if notes.blank?
      NotificationBell.enqueue_for_mentions(self)
    rescue => e
      Rails.logger.error "[NotificationBell] nb_enqueue_mentions_update error: #{e.class}: #{e.message}"
    end
  end
end

Rails.configuration.to_prepare do
  unless Journal.ancestors.include?(RedmineNotificationBell::JournalPatch)
    Journal.include(RedmineNotificationBell::JournalPatch)
    Rails.logger.info "[NotificationBell] JournalPatch applied"
  end
end
