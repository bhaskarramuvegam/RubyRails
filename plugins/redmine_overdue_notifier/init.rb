
Redmine::Plugin.register :redmine_overdue_notifier do
  name 'Redmine Overdue Notifier plugin'
  author 'Your Name'
  description 'Sends email notifications for overdue issues'
  version '0.0.1'
  url 'https://your.plugin.url'
  author_url 'https://your.profile.url'

  settings default: { 
    'project_ids' => [],
    'enabled' => '0'
  }, partial: 'settings/overdue_notifier_settings'
end

