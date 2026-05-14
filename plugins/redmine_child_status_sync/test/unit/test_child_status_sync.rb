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
    @tracker = Tracker.find_by(name: 'Bug') || Tracker.create!(name: 'Bug')

    # Create issue statuses
    @new_status = IssueStatus.find_by(name: 'New') || IssueStatus.create!(name: 'New', is_closed: false)
    @dev_in_progress_status = IssueStatus.find_by(name: 'Development In Progress') || IssueStatus.create!(name: 'In Progress', is_closed: false)
    @dev_in_progress_status.update(name: 'Development In Progress') if @dev_in_progress_status.name != 'Development In Progress'

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
end