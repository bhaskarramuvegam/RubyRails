# Redmine Child Status Sync Plugin
# This plugin automatically updates parent issue status when child issues change status

require File.expand_path('../lib/redmine_child_status_sync/issue_patch', __FILE__)
require_dependency 'issue'
Issue.send(:include, RedmineChildStatusSync::IssuePatch)

Redmine::Plugin.register :redmine_child_status_sync do
  name 'Child Status Sync Plugin'
  author 'Generated Plugin'
  description 'Automatically synchronizes parent issue status to match ANY status change in child issues'
  version '0.0.1'
  url 'http://example.com/plugin'
  author_url 'http://example.com/author'
  settings default: { 'enabled' => '1', 'enable_logging' => '1' }, partial: 'settings/redmine_child_status_sync'
end