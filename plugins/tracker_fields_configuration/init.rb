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
require File.expand_path('../lib/tracker_fields_configuration/hidden_fields_hooks', __FILE__)

Redmine::Plugin.register :tracker_fields_configuration do
  name 'Tracker Fields Configuration'
  author 'Development Team'
  description 'Promote selected custom fields into the standard fields area of the issue form, and hide/unhide fields, configurable per project and tracker.'
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
    'project_tracker_after' => {},
    # Which fields are hidden entirely - a separate feature from the two
    # above, read/written independently of them.
    # Hash: project_id (string) => tracker_id (string) => [field_key (string), ...]
    # field_key is "cf_<id>" for a custom field, "std_<key>" for a standard
    # field, or "ext_<key>" for an admin-registered field from another
    # plugin (see project_tracker_extra_fields below).
    'project_tracker_hidden_fields' => {},
    # Admin-registered fields from other plugins (e.g. Redmine Agile's
    # Sprint field) that aren't Redmine CustomFields, so can't be
    # auto-discovered from Tracker#custom_fields like the others above.
    # Hash: project_id (string) => tracker_id (string) => [key (string), ...]
    'project_tracker_extra_fields' => {},
    # Display label for each registered extra field above.
    # Hash: project_id (string) => tracker_id (string) => { key (string) => label (string) }
    'project_tracker_extra_field_labels' => {}
  }, partial: 'settings/tracker_fields_configuration_settings'
end
