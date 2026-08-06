# Redmine Child Status Sync Plugin
# This plugin automatically updates parent issue status when child issues change status

require File.expand_path('../lib/redmine_child_status_sync/issue_patch', __FILE__)
require_dependency 'issue'
Issue.send(:include, RedmineChildStatusSync::IssuePatch)

# Default forward-moving status flow. Only a status ahead of the parent's current
# status in this order will be synced up to the parent - this list is editable from
# the plugin settings page, so new statuses can be added without a code change.
DEFAULT_CHILD_STATUS_SYNC_STATUS_ORDER = [
  'New',
  'A&D In Progress',
  'A&D Completed',
  'UX/UI Design In Progress',
  'UX/UI Design Completed',
  'UI Development In Progress',
  'UI Development Completed',
  'Development In Progress',
  'Development Completed',
  'Code Under Review',
  'Code Reviewed',
  'Released to 203',
  'Local Testing In Progress',
  'Internal Demo Completed',
  'Local Testing Completed',
  'Released in UAT Server',
  'UAT Feedback Awaited',
  'UAT Observation Received',
  'UAT Signoff Received',
  'Released to Production'
].join("\n")

Redmine::Plugin.register :redmine_child_status_sync do
  name 'Child Status Sync Plugin'
  author 'Generated Plugin'
  description 'Automatically synchronizes parent issue status to match ANY status change in child issues'
  version '0.0.1'
  url 'http://example.com/plugin'
  author_url 'http://example.com/author'
  settings default: {
    'enabled' => '1',
    'enable_logging' => '1',
    'restricted_trackers' => 'Bug,CR_Bug',
    'status_order' => DEFAULT_CHILD_STATUS_SYNC_STATUS_ORDER,
    'restricted_statuses' => 'OnHold,Completed,Closed,Cancelled',
    'date_sync_child_trackers' => 'Task',
    'earliest_date_custom_fields' => 'Actual start date',
    'latest_date_custom_fields' => 'Actual end date',
    'sync_planned_dates' => '1'
  }, partial: 'settings/redmine_child_status_sync'
end