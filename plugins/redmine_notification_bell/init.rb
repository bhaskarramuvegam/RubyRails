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

require_relative 'lib/redmine_notification_bell/journal_patch'
require_relative 'lib/redmine_notification_bell/hooks'
