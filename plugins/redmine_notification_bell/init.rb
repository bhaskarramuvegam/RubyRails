Redmine::Plugin.register :redmine_notification_bell do
  name        'Redmine Notification Bell'
  author      'Vegam'
  description '@mention notifications — zero impact on Redmine HTTP response time'
  version     '2.0.0'
  url         'https://vegam.co'
  author_url  'https://vegam.co'

  requires_redmine version_or_higher: '4.0.0'

  settings default: {
    'sound_enabled'     => '1',
    'max_notifications' => '20',
    'preview_length'    => '100'
  }, partial: 'settings/redmine_notification_bell'
end

require_relative 'lib/redmine_notification_bell/worker'
require_relative 'lib/redmine_notification_bell/journal_patch'
require_relative 'lib/redmine_notification_bell/hooks'

# Passenger forks the master process into worker processes.
# Threads started before the fork are dead in child processes.
# on_event(:starting_worker_process) fires inside each child AFTER the fork,
# so the worker thread is alive in the correct process.
if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |_forked|
    RedmineNotificationBell::Worker.start!
  end
else
  Rails.configuration.after_initialize do
    RedmineNotificationBell::Worker.start! unless Rails.env.test?
  end
end
