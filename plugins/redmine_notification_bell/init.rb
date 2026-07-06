Redmine::Plugin.register :redmine_notification_bell do
  name        'Redmine Notification Bell'
  author      'Vegam'
  description 'Bell icon notification system for @mention alerts in issue notes/comments'
  version     '1.0.0'
  url         'https://vegam.co'
  author_url  'https://vegam.co'

  requires_redmine version_or_higher: '4.0.0'

  settings default: {
    'sound_enabled'      => '1',
    'max_notifications'  => '20',
    'preview_length'     => '100'
  }, partial: 'settings/redmine_notification_bell'
end

require_relative 'lib/redmine_notification_bell/worker'
require_relative 'lib/redmine_notification_bell/journal_patch'
require_relative 'lib/redmine_notification_bell/hooks'

# Start the background notification worker.
#
# Passenger uses a forking model: master loads the app, then forks workers.
# Threads started before the fork are DEAD in child processes.
# PhusionPassenger.on_starting_worker_process fires inside each child AFTER
# the fork — the worker thread created here is alive in the right process.
#
# For non-Passenger servers (Puma, WEBrick, dev) use after_initialize, which
# runs once after the app has fully booted in the same process.
if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |_forked|
    RedmineNotificationBell::Worker.start!
  end
else
  Rails.configuration.after_initialize do
    RedmineNotificationBell::Worker.start! unless Rails.env.test?
  end
end
