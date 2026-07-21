# Redmine Child Status Sync Plugin - Unit Tests
# Tests the automatic parent status synchronization functionality

require File.expand_path('../../../../../test/test_helper', __FILE__)

class ChildStatusSyncTest < ActiveSupport::TestCase
  def setup
    # Disable email deliveries for tests
    ActionMailer::Base.perform_deliveries = false
    ActionMailer::Base.deliveries.clear

    # Ensure the plugin patch is included
    Issue.send(:include, RedmineChildStatusSync::IssuePatch) unless Issue.included_modules.include?(RedmineChildStatusSync::IssuePatch)

    # Create test data
    @project = Project.find_by(identifier: 'test-project') || Project.create!(name: 'Test Project', identifier: 'test-project', is_public: true)
    @tracker = Tracker.find_by(name: 'Task') || Tracker.create!(name: 'Task')
    @bug_tracker = Tracker.find_by(name: 'Bug') || Tracker.create!(name: 'Bug')
    @cr_bug_tracker = Tracker.find_by(name: 'CR_Bug') || Tracker.create!(name: 'CR_Bug')

    # Create issue statuses
    @new_status = IssueStatus.find_by(name: 'New') || IssueStatus.create!(name: 'New', is_closed: false)
    @dev_in_progress_status = IssueStatus.find_by(name: 'Development In Progress') || IssueStatus.create!(name: 'In Progress', is_closed: false)
    @dev_in_progress_status.update(name: 'Development In Progress') if @dev_in_progress_status.name != 'Development In Progress'
    @dev_completed_status = IssueStatus.find_by(name: 'Development Completed') || IssueStatus.create!(name: 'Development Completed', is_closed: false)

    # Ensure the plugin settings match plugin defaults for these tests, regardless of whatever
    # is already persisted in the test database from a previous run.
    Setting.plugin_redmine_child_status_sync = Setting.plugin_redmine_child_status_sync.merge(
      'restricted_trackers' => 'Bug,CR_Bug',
      'restricted_statuses' => 'OnHold,Completed,Closed,Cancelled',
      'status_order' => [
        'New', 'A&D In Progress', 'A&D Completed', 'UX/UI Design In Progress', 'UX/UI Design Completed',
        'UI Development In Progress', 'UI Development Completed', 'Development In Progress', 'Development Completed',
        'Code Under Review', 'Code Reviewed', 'Released to 203', 'Local Testing In Progress', 'Internal Demo Completed',
        'Local Testing Completed', 'Released in UAT Server', 'UAT Feedback Awaited', 'UAT Observation Received',
        'UAT Signoff Received', 'Released to Production'
      ].join("\n")
    )

    # Create parent issue
    @parent_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Parent Task',
      status: @new_status
    )
  end

  test "parent status updates when child status changes to Development In Progress" do
    # Create child issue with New status
    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    # Verify initial state
    assert_equal @new_status.id, @parent_issue.reload.status_id
    assert_equal @new_status.id, child_issue.reload.status_id

    # Update child status to Development In Progress
    child_issue.status = @dev_in_progress_status
    child_issue.save!

    # Verify parent status was updated
    @parent_issue.reload
    assert_equal @dev_in_progress_status.id, @parent_issue.status_id,
                 "Parent issue status should be updated to Development In Progress"
  end

  test "parent status does not update if child is not changing to Development In Progress" do
    # Create child issue
    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    # Update child to a different status (not Development In Progress)
    different_status = IssueStatus.find_by(name: 'Resolved') || IssueStatus.create!(name: 'Resolved', is_closed: true)
    child_issue.status = different_status
    child_issue.save!

    # Verify parent status remains unchanged
    @parent_issue.reload
    assert_equal @new_status.id, @parent_issue.status_id,
                 "Parent issue status should not change when child moves to different status"
  end

  test "no sync occurs for issues without parent" do
    # Create standalone issue (no parent)
    standalone_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Standalone Task',
      status: @new_status
    )

    # Update status to Development In Progress
    standalone_issue.status = @dev_in_progress_status
    standalone_issue.save!

    # Should not cause any errors - no parent to sync
    assert true # Test passes if no exception is raised
  end

  test "parent status sync only happens when status actually changes" do
    # Create child issue already in Development In Progress
    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @dev_in_progress_status,
      parent_id: @parent_issue.id
    )

    # Update parent to Development In Progress manually first
    @parent_issue.update(status: @dev_in_progress_status)
    @parent_issue.reload

    # Save child again (no status change)
    child_issue.save!

    # Parent should still be in Development In Progress
    @parent_issue.reload
    assert_equal @dev_in_progress_status.id, @parent_issue.status_id
  end

  test "handles case when Development In Progress status does not exist" do
    # Remove the Development In Progress status
    dev_status = IssueStatus.find_by(name: 'Development In Progress')
    dev_status.destroy if dev_status

    # Create child issue
    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    # Try to update child status - should not cause errors
    child_issue.status = @new_status # Any status change
    child_issue.save!

    # Should not cause any errors even if status doesn't exist
    assert true # Test passes if no exception is raised
  end

  test "handles case when parent issue does not exist" do
    # Create child issue with invalid parent_id
    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @new_status,
      parent_id: 99999 # Non-existent parent
    )

    # Update child status to Development In Progress
    child_issue.status = @dev_in_progress_status
    child_issue.save!

    # Should not cause errors even if parent doesn't exist
    assert true # Test passes if no exception is raised
  end

  test "updates all parent issues when child contains multiple parents" do
    second_parent = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Second Parent Task',
      status: @new_status
    )

    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    # Simulate a multi-parent issue relationship if supported by the environment
    child_issue.define_singleton_method(:parents) do
      [@parent_issue, second_parent]
    end

    child_issue.status = @dev_in_progress_status
    child_issue.save!

    assert_equal @dev_in_progress_status.id, @parent_issue.reload.status_id,
                 "First parent issue status should be updated"
    assert_equal @dev_in_progress_status.id, second_parent.reload.status_id,
                 "Second parent issue status should be updated"
  end

  test "parent status does not update when child tracker is Bug" do
    child_issue = Issue.create!(
      project: @project,
      tracker: @bug_tracker,
      subject: 'Bug Child',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = @dev_in_progress_status
    child_issue.save!

    @parent_issue.reload
    assert_equal @new_status.id, @parent_issue.status_id,
                 "Parent issue status should not change when a Bug child changes status"
  end

  test "parent status does not update when child tracker is CR_Bug" do
    child_issue = Issue.create!(
      project: @project,
      tracker: @cr_bug_tracker,
      subject: 'CR_Bug Child',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = @dev_in_progress_status
    child_issue.save!

    @parent_issue.reload
    assert_equal @new_status.id, @parent_issue.status_id,
                 "Parent issue status should not change when a CR_Bug child changes status"
  end

  test "parent status still updates for non-restricted trackers like Task" do
    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Task Child',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = @dev_in_progress_status
    child_issue.save!

    @parent_issue.reload
    assert_equal @dev_in_progress_status.id, @parent_issue.status_id,
                 "Parent issue status should still update for non-restricted trackers"
  end

  test "restricted trackers setting is case-insensitive and trims whitespace" do
    Setting.plugin_redmine_child_status_sync = Setting.plugin_redmine_child_status_sync.merge('restricted_trackers' => ' bug , cr_bug ')

    child_issue = Issue.create!(
      project: @project,
      tracker: @bug_tracker,
      subject: 'Bug Child',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = @dev_in_progress_status
    child_issue.save!

    @parent_issue.reload
    assert_equal @new_status.id, @parent_issue.status_id,
                 "Restricted tracker matching should be case-insensitive and whitespace-tolerant"
  end

  test "blank restricted trackers setting allows all trackers to sync" do
    Setting.plugin_redmine_child_status_sync = Setting.plugin_redmine_child_status_sync.merge('restricted_trackers' => '')

    child_issue = Issue.create!(
      project: @project,
      tracker: @bug_tracker,
      subject: 'Bug Child',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = @dev_in_progress_status
    child_issue.save!

    @parent_issue.reload
    assert_equal @dev_in_progress_status.id, @parent_issue.status_id,
                 "With no restricted trackers configured, all trackers should sync as before"
  end

  test "parent status does not move backward when child regresses in the status order" do
    # Parent is already further along than the child is about to become
    @parent_issue.update_column(:status_id, @dev_completed_status.id)

    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @dev_in_progress_status,
      parent_id: @parent_issue.id
    )

    # Child regresses to an earlier status in the configured order
    child_issue.status = @new_status
    child_issue.save!

    @parent_issue.reload
    assert_equal @dev_completed_status.id, @parent_issue.status_id,
                 "Parent should not be moved backward when the child regresses to an earlier status in the configured order"
  end

  test "parent status still moves forward when child advances further in the status order" do
    @parent_issue.update_column(:status_id, @new_status.id)

    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @dev_in_progress_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = @dev_completed_status
    child_issue.save!

    @parent_issue.reload
    assert_equal @dev_completed_status.id, @parent_issue.status_id,
                 "Parent should move forward when the child advances further along the configured order"
  end

  test "falls back to allowing sync when a status is not part of the configured order" do
    custom_status = IssueStatus.find_by(name: 'Totally Custom Status') || IssueStatus.create!(name: 'Totally Custom Status', is_closed: false)

    @parent_issue.update_column(:status_id, @dev_completed_status.id)

    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = custom_status
    child_issue.save!

    @parent_issue.reload
    assert_equal custom_status.id, @parent_issue.status_id,
                 "When the new status isn't part of the configured order, sync should proceed as before"
  end

  %w[OnHold Completed Closed Cancelled].each do |restricted_status_name|
    test "parent status does not update when child moves to restricted status #{restricted_status_name}" do
      status = IssueStatus.find_by(name: restricted_status_name) || IssueStatus.create!(name: restricted_status_name, is_closed: false)

      child_issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        subject: 'Child Task',
        status: @new_status,
        parent_id: @parent_issue.id
      )

      child_issue.status = status
      child_issue.save!

      @parent_issue.reload
      assert_equal @new_status.id, @parent_issue.status_id,
                   "Parent issue status should not change when child moves to restricted status #{restricted_status_name}"
    end
  end

  test "blank restricted statuses setting allows all statuses to sync" do
    Setting.plugin_redmine_child_status_sync = Setting.plugin_redmine_child_status_sync.merge('restricted_statuses' => '')
    onhold_status = IssueStatus.find_by(name: 'OnHold') || IssueStatus.create!(name: 'OnHold', is_closed: false)

    child_issue = Issue.create!(
      project: @project,
      tracker: @tracker,
      subject: 'Child Task',
      status: @new_status,
      parent_id: @parent_issue.id
    )

    child_issue.status = onhold_status
    child_issue.save!

    @parent_issue.reload
    assert_equal onhold_status.id, @parent_issue.status_id,
                 "With no restricted statuses configured, all statuses should sync as before"
  end
end