# Redmine Child Status Sync - Issue Patch
# This module patches the Issue model to automatically sync parent status
# when child issues are updated to ANY status

module RedmineChildStatusSync
  module IssuePatch
    def self.included(base)
      base.send(:include, InstanceMethods)
      base.class_eval do
        after_save :sync_parent_status_on_child_update
      end
    end

    module InstanceMethods
      private

      def sync_parent_status_on_child_update
        # Check if plugin is enabled
        unless Setting.plugin_redmine_child_status_sync['enabled'] == '1'
          return
        end

        # Check if debug logging is enabled
        debug_logging = Setting.plugin_redmine_child_status_sync['enable_logging'] == '1'

        Rails.logger.info("===== CHILD STATUS SYNC DEBUG START =====") if debug_logging
        Rails.logger.info("Issue ID: #{id}, Parent ID: #{parent_id}") if debug_logging

        parent_issues = collect_parent_issues
        if parent_issues.empty?
          Rails.logger.info("SKIPPED: No parent issues found") if debug_logging
          return
        end

        Rails.logger.info("Found parent issue IDs: #{parent_issues.map(&:id).join(', ')}") if debug_logging

        # Only proceed if status was actually changed
        unless status_changed?
          Rails.logger.info("SKIPPED: status_id not changed") if debug_logging
          return
        end

        Rails.logger.info("Status changed: #{status_change_from} → #{status_id}") if debug_logging

        parent_issues.each do |parent_issue|
          next unless parent_issue

          Rails.logger.info("Processing parent issue ##{parent_issue.id}") if debug_logging

          if parent_issue.status_id != status_id
            Rails.logger.info("Status mismatch: Parent #{parent_issue.status_id} != Child #{status_id}") if debug_logging
            Rails.logger.info("Attempting to update parent status...") if debug_logging

            begin
              parent_issue.update_column(:status_id, status_id)
              Rails.logger.info("SUCCESS: Updated parent issue ##{parent_issue.id} status") if debug_logging

              # Get status name for logging
              status_name = IssueStatus.find_by(id: status_id)&.name || "Unknown Status"
              Rails.logger.info("Child Status Sync: Updated parent issue ##{parent_issue.id} status to '#{status_name}' because child ##{id} was updated to this status")
            rescue => e
              Rails.logger.error("ERROR updating parent issue ##{parent_issue.id} status: #{e.message}")
              Rails.logger.error(e.backtrace.join("\n"))
            end
          else
            Rails.logger.info("Parent ##{parent_issue.id} already has same status, no update needed") if debug_logging
          end
        end

        Rails.logger.info("===== CHILD STATUS SYNC DEBUG END =====") if debug_logging
      end

      def status_changed?
        if respond_to?(:saved_change_to_status_id?)
          saved_change_to_status_id?
        else
          status_id_changed?
        end
      end

      def status_change_from
        if respond_to?(:status_id_before_last_save)
          status_id_before_last_save
        elsif respond_to?(:status_id_previous_change)
          status_id_previous_change&.first
        else
          status_id_was
        end
      end

      def collect_parent_issues
        queue = []
        collected = []
        visited_ids = []

        if respond_to?(:parent_issues)
          queue += parent_issues.to_a
        elsif respond_to?(:parents)
          queue += parents.to_a
        elsif respond_to?(:parent) && parent.present?
          queue << parent
        elsif parent_id.present?
          queue << Issue.find_by(id: parent_id)
        end

        while issue = queue.shift
          next unless issue
          next if visited_ids.include?(issue.id)

          visited_ids << issue.id
          collected << issue

          if issue.respond_to?(:parent_issues)
            queue.concat(issue.parent_issues.to_a)
          elsif issue.respond_to?(:parents)
            queue.concat(issue.parents.to_a)
          elsif issue.respond_to?(:parent) && issue.parent.present?
            queue << issue.parent
          elsif issue.parent_id.present?
            queue << Issue.find_by(id: issue.parent_id)
          end
        end

        collected
      end
    end
  end
end