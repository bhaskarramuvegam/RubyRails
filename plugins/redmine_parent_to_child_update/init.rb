# Redmine Parent to Child Update Plugin
# This plugin asks user if they want to create a child issue when creating a parent issue
# If yes, it replicates all parent fields to the child issue
# This applies recursively for sub-child creation

require File.expand_path('../lib/redmine_parent_to_child_update/issue_patch', __FILE__)
require File.expand_path('../lib/redmine_parent_to_child_update/hooks', __FILE__)
require_dependency 'issue'

Issue.send(:include, RedmineParentToChildUpdate::IssuePatch)

Redmine::Plugin.register :redmine_parent_to_child_update do
  name 'Parent to Child Update Plugin'
  author 'Development Team'
  description 'Automatically ask users to create child issues when creating parent issues with field replication'
  version '1.0.0'
  url 'http://example.com/plugin'
  author_url 'http://example.com/author'
  
  settings default: {
    'enabled' => '1',
    'enable_logging' => '1',
    'auto_replicate_fields' => '1',
    'parent_issue_types' => 'Change Request,CR,Bug,Feature,Task,Support',
    'replicated_fields' => 'priority,assigned_to,category,fixed_version,description,due_date,start_date,estimated_hours,custom_fields',
    'append_required_fields' => '1',
    'create_additional_children' => '1',
    'additional_child_trackers' => 'Development Task,Testing Task',
    'create_dev_test_tasks' => '0',
    'dev_test_task_tracker' => 'Task',
    # Hash: parent_tracker_id (string) => comma-separated child tracker names
    # e.g. { "3" => "User Story,Task", "5" => "Task" }
    'popup_child_trackers_by_parent' => {},
    # Hash: tracker_id (string) => array of custom_field_id strings to show in popup
    # e.g. { "3" => ["10", "11"], "5" => ["12"] }
    'tracker_popup_fields' => {},
    # Comma-separated field names to exclude from popup (matched case-insensitively by name)
    'popup_excluded_fields' => 'Release Details',
    # Comma-separated tracker names that trigger the child-creation chain popup (CR → US → Task)
    'popup_parent_trackers' => 'Change Request,User Story'
  }, partial: 'settings/redmine_parent_to_child_update_settings'
end
