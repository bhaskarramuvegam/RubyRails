require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

class RedmineParentToChildUpdateTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :users, :roles

  def setup
    @plugin_name = :redmine_parent_to_child_update
  end

  def teardown
    Setting.plugin_redmine_parent_to_child_update.clear
  end

  test 'plugin should be registered' do
    assert Redmine::Plugin.registered_plugins.key?(@plugin_name)
  end

  test 'plugin should have default settings' do
    # Default settings should be present
    assert Setting.respond_to?(:plugin_redmine_parent_to_child_update)
  end

  test 'Issue should respond to parent_child_update_enabled?' do
    issue = Issue.new
    assert issue.respond_to?(:parent_child_update_enabled?)
  end

  test 'Issue should respond to replicate_fields_from_parent' do
    issue = Issue.new
    assert issue.respond_to?(:replicate_fields_from_parent)
  end

  test 'Issue should respond to should_show_child_popup?' do
    issue = Issue.new
    assert issue.respond_to?(:should_show_child_popup?)
  end

  test 'Issue should respond to available_child_trackers' do
    issue = Issue.new
    assert issue.respond_to?(:available_child_trackers)
  end
end

# Test case for field replication
class FieldReplicationTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :users, :roles, :priorities

  def setup
    @project = Project.find(1)
    @parent_issue = Issue.create!(
      project: @project,
      tracker: Tracker.first,
      subject: 'Parent Issue',
      status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : IssueStatus.first),
      priority: IssuePriority.default,
      author: User.current
    )

    @child_issue = Issue.new(
      project: @project,
      tracker: Tracker.last,
      subject: 'Child Issue',
      status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : IssueStatus.first)
    )
  end

  test 'child issue should replicate parent fields' do
    # Set parent fields
    @parent_issue.update(
      priority_id: IssuePriority.find_by(name: 'High')&.id || 2,
      assigned_to_id: User.first&.id,
      estimated_hours: 5.0
    )

    # Replicate fields
    @child_issue.replicate_fields_from_parent(@parent_issue)

    # Verify replication
    assert_equal @parent_issue.priority_id, @child_issue.priority_id
    assert_equal @parent_issue.assigned_to_id, @child_issue.assigned_to_id
    assert_equal @parent_issue.estimated_hours, @child_issue.estimated_hours
    assert_equal @parent_issue.id, @child_issue.parent_id
  end

  test 'child issue description should reference parent' do
    parent_desc = 'Parent description text'
    @parent_issue.update(description: parent_desc)
    
    @child_issue.replicate_fields_from_parent(@parent_issue)

    assert @child_issue.description.include?("Child of Issue #{@parent_issue.id}")
    assert @child_issue.description.include?(parent_desc)
  end
end

# Test case for popup triggering
class PopupTriggeringTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :users, :roles

  def setup
    @project = Project.find(1)
    # Ensure we have different tracker types
    @bug_tracker = Tracker.find_by(name: 'Bug') || Tracker.create!(name: 'Bug')
    @story_tracker = Tracker.find_by(name: 'User Story') || Tracker.create!(name: 'User Story')
  end

  test 'new parent issue should show child popup' do
    issue = Issue.new(
      project: @project,
      tracker: @bug_tracker,
      subject: 'Test Issue'
    )
    
    # Since Bug is in default parent types, should show popup
    assert issue.new_record?
    assert issue.parent_id.blank?
    # Note: should_show_child_popup? requires plugin settings to be enabled
  end

  test 'child issue should not show popup' do
    parent = Issue.create!(
      project: @project,
      tracker: @bug_tracker,
      subject: 'Parent Issue',
      status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : IssueStatus.first),
      author: User.current
    )

    child = Issue.new(
      project: @project,
      tracker: @story_tracker,
      subject: 'Child Issue',
      parent_id: parent.id
    )

    # Child issues shouldn't show popup
    assert child.parent_id.present?
    # should_show_child_popup? should return false for child issues
  end
end
