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
      # saved_changes is reliable in after_commit across all Rails 5.x/6.x versions.
      # previous_changes can be cleared before after_commit fires in some patch releases.
      return unless saved_changes.key?('notes')
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
