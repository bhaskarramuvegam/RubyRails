module RedmineNotificationBell
  class Hooks < Redmine::Hook::ViewListener

    def view_layouts_base_html_head(context = {})
      return '' unless NotificationBell.plugin_enabled?

      plugin_settings = begin
        Setting.plugin_redmine_notification_bell
      rescue
        {}
      end

      sound_enabled  = plugin_settings['sound_enabled'].to_s == '1'
      max_items      = plugin_settings['max_notifications'].to_i
      max_items      = 20 unless max_items.between?(1, 100)
      preview_length = plugin_settings['preview_length'].to_i
      preview_length = 100 unless preview_length.between?(20, 300)

      config_js = <<~JS
        <script>
          window.NotificationBellConfig = {
            soundEnabled:     #{sound_enabled ? 'true' : 'false'},
            maxNotifications: #{max_items},
            previewLength:    #{preview_length}
          };
        </script>
      JS

      config_js +
        stylesheet_link_tag('notification_bell', plugin: 'redmine_notification_bell') +
        javascript_include_tag('notification_bell', plugin: 'redmine_notification_bell')
    end

    def view_layouts_base_body_bottom(context = {})
      return '' unless NotificationBell.plugin_enabled?
      return '' unless User.current.logged?

      context[:controller].render_to_string(
        partial: 'notification_bells/bell_widget',
        locals:  {}
      )
    end

    # Backup path for 000_redmine_x_ux_upgrade which overrides the issues
    # controller, potentially bypassing Journal model callbacks.
    # The unique index on notification_bell_jobs.journal_id ensures the
    # after_commit + this hook never produce duplicate jobs.
    def controller_issues_edit_after_save(context = {})
      journal = context[:journal]
      return unless journal.present?
      NotificationBell.enqueue_for_mentions(journal)
    rescue => e
      Rails.logger.error "[NotificationBell] controller_issues_edit_after_save error: #{e.message}"
    end

    def controller_journals_new_after_save(context = {})
      journal = context[:journal]
      return unless journal.present?
      NotificationBell.enqueue_for_mentions(journal)
    rescue => e
      Rails.logger.error "[NotificationBell] controller_journals_new_after_save error: #{e.message}"
    end

    def controller_journals_edit_after_save(context = {})
      journal = context[:journal]
      return unless journal.present?
      return if journal.notes.blank?
      NotificationBell.enqueue_for_mentions(journal)
    rescue => e
      Rails.logger.error "[NotificationBell] controller_journals_edit_after_save error: #{e.message}"
    end
  end
end
