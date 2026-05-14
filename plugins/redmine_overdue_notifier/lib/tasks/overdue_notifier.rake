namespace :redmine_overdue_notifier do
  desc "Sends email notifications for overdue issues in explicitly selected projects only"
  task send_notifications: :environment do
    settings = Setting.plugin_redmine_overdue_notifier
    enabled = settings['enabled'] == '1'
    project_ids = settings['project_ids'] || []

    unless enabled
      Rails.logger.info "OverdueNotifier: Plugin is disabled in settings. Skipping notification task."
      puts "OverdueNotifier is disabled in plugin settings."
      next
    end

    if project_ids.empty?
      Rails.logger.warn "OverdueNotifier: No projects selected in plugin settings."
      puts "No projects configured to send overdue notifications. Configure it in plugin settings."
      next
    end

    # No recursion — only explicitly selected projects
    projects = Project.where(id: project_ids)

    Rails.logger.info "OverdueNotifier: Processing #{projects.size} explicitly selected project(s)..."

    projects.each do |project|
      Rails.logger.info "OverdueNotifier: Checking project '#{project.name}' (##{project.id})..."

      overdue_issues = project.issues
        .where("#{Issue.table_name}.due_date IS NOT NULL AND #{Issue.table_name}.due_date <= ? AND #{Issue.table_name}.assigned_to_id IS NOT NULL", Date.current)
        .joins(:status)
        .where(issue_statuses: { is_closed: false })

      if overdue_issues.empty?
        Rails.logger.info "OverdueNotifier: No overdue issues found for project '#{project.name}'."
        next
      end

      Rails.logger.info "OverdueNotifier: Found #{overdue_issues.count} overdue issue(s) for '#{project.name}'."

      overdue_issues.each do |issue|
        recipients = [issue.assigned_to, issue.author].compact.uniq

        recipients.each do |user|
          if user.mail.present?
            Rails.logger.info "OverdueNotifier: Sending notification for issue ##{issue.id} ('#{issue.subject}') to #{user.name} (#{user.mail})"
            OverdueNotifierMailer.overdue_notification(user, issue).deliver_now
          else
            Rails.logger.warn "OverdueNotifier: No email found for user #{user.name} (ID: #{user.id}). Skipping."
          end
        end
      end

      Rails.logger.info "OverdueNotifier: Completed notifications for project '#{project.name}'."
    end

    Rails.logger.info "OverdueNotifier: All configured projects processed."
    puts "OverdueNotifier: Email notifications completed."
  end
end

