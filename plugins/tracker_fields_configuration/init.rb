# Tracker Fields Configuration Plugin
#
# Lets an administrator "promote" selected custom fields so they render
# inside the standard fields area of the issue form (next to Priority,
# Assigned To, etc.) instead of down in the separate "Custom fields" box.
#
# Configuration is per project + per tracker, and is done entirely from
# Administration > Plugins > Tracker Fields Configuration. The settings
# page always reads the live list of projects, trackers and custom fields
# from Redmine itself, so newly added projects/trackers/fields show up
# automatically without any code changes.
#
# No database migration is used - configuration is stored using Redmine's
# built-in plugin settings mechanism (Setting.plugin_tracker_fields_configuration).

require File.expand_path('../lib/tracker_fields_configuration', __FILE__)
require File.expand_path('../lib/tracker_fields_configuration/hooks', __FILE__)

Redmine::Plugin.register :tracker_fields_configuration do
  name 'Tracker Fields Configuration'
  author 'Development Team'
  description 'Promote selected custom fields into the standard fields area of the issue form, configurable per project and tracker.'
  version '1.0.0'
  url 'http://example.com/plugin'
  author_url 'http://example.com/author'

  settings default: {
    'enabled' => '1',
    # Which custom fields are promoted, per project + tracker.
    # Hash: project_id (string) => tracker_id (string) => [custom_field_id (string), ...]
    'project_tracker_fields' => {},
    # Where each promoted custom field should be inserted, per project + tracker.
    # Hash: project_id (string) => tracker_id (string) => { custom_field_id (string) => standard_field_key (string) }
    'project_tracker_after' => {}
  }, partial: 'settings/tracker_fields_configuration_settings'
end
