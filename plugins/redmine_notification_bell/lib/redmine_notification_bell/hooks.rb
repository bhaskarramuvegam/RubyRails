module RedmineNotificationBell
  class Hooks < Redmine::Hook::ViewListener

    # ── View hooks ──────────────────────────────────────────────

    def view_layouts_base_html_head(context = {})
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
      return '' unless User.current.logged?

      context[:controller].render_to_string(
        partial: 'notification_bells/bell_widget',
        locals:  {}
      )
    end

    # ── Controller hooks — reliable journal creation detection ───
    #
    # Using controller hooks instead of a Journal model patch because
    # Redmine's plugin loading order can cause after_commit patches to
    # silently not register in production. Controller hooks are Redmine's
    # official extension point and are guaranteed to fire.

    # Fires after a user updates an issue (most common path for @mentions)
    def controller_issues_edit_after_save(context = {})
      journal = context[:journal]
      return unless journal.present?

      Rails.logger.info "[NotificationBell] controller_issues_edit_after_save: journal #{journal.id}"
      NotificationBell.create_for_mentions(journal)
    rescue => e
      Rails.logger.error "[NotificationBell] controller_issues_edit_after_save error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    # Fires after a user edits an existing journal note via the journal UI
    def controller_journals_new_after_save(context = {})
      journal = context[:journal]
      return unless journal.present?

      Rails.logger.info "[NotificationBell] controller_journals_new_after_save: journal #{journal.id}"
      NotificationBell.create_for_mentions(journal)
    rescue => e
      Rails.logger.error "[NotificationBell] controller_journals_new_after_save error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end
  end
end
