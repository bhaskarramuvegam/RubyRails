# Redmine Child Status Sync - Issue Patch
# This module patches the Issue model to automatically sync parent status
# when child issues are updated to ANY status

module RedmineChildStatusSync
  module IssuePatch
    def self.included(base)
      base.send(:include, InstanceMethods)
      base.class_eval do
        after_save :sync_parent_status_on_child_update
        after_save :sync_parent_dates_on_child_update
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
        Rails.logger.info("Issue ID: #{id}, Parent ID: #{parent_id}, Tracker: #{tracker&.name}") if debug_logging

        # Restricted trackers (e.g. Bug, CR_Bug) never propagate their status to parent issues.
        # This keeps auto status sync limited to the Task -> User Story -> CR flow.
        if restricted_tracker?
          Rails.logger.info("SKIPPED: Tracker '#{tracker&.name}' is restricted from updating parent status") if debug_logging
          return
        end

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

        # Restricted statuses (e.g. OnHold, Completed, Closed, Cancelled) never propagate to parents,
        # regardless of tracker or position in the status order.
        if restricted_status?(status_id)
          new_status_name = IssueStatus.find_by(id: status_id)&.name
          Rails.logger.info("SKIPPED: Status '#{new_status_name}' is restricted from updating parent status") if debug_logging
          return
        end

        parent_issues.each do |parent_issue|
          next unless parent_issue

          Rails.logger.info("Processing parent issue ##{parent_issue.id}") if debug_logging

          if parent_issue.status_id != status_id
            Rails.logger.info("Status mismatch: Parent #{parent_issue.status_id} != Child #{status_id}") if debug_logging

            unless forward_status_transition?(parent_issue.status_id, status_id)
              Rails.logger.info("SKIPPED parent ##{parent_issue.id}: new status is not ahead of the parent's current status in the configured status order") if debug_logging
              next
            end

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

      # Keeps a parent issue's date fields as a running (never-shrinking) envelope over its child tasks:
      #   - Actual/Planned Start Date on the parent = EARLIEST such date ever pushed up by a child task
      #   - Actual/Planned End Date on the parent   = LATEST such date ever pushed up by a child task
      # This is a ratchet, not a live recompute: a child's new value is compared directly against
      # whatever the parent currently holds, and the parent is only moved when the child is MORE
      # extreme (earlier start / later end). A child later moving to a LESS extreme date never pulls
      # the parent back in - the parent simply keeps the widest start/end window any child has ever
      # reported, exactly like a single child's dates widening the parent and staying put once other
      # updates fall back inside that window.
      # Only issues whose tracker is listed in "date_sync_child_trackers" (default: Task) count as
      # child tasks that can push the envelope; a Bug/CR_Bug child never affects a parent's dates.
      # Which custom fields count as "earliest" vs "latest" is configurable from the plugin settings
      # page - adding a future date field is a settings change, not a code change. Planned Start/End
      # Date map to Redmine's built-in start_date/due_date columns.
      def sync_parent_dates_on_child_update
        unless Setting.plugin_redmine_child_status_sync['enabled'] == '1'
          return
        end

        debug_logging = Setting.plugin_redmine_child_status_sync['enable_logging'] == '1'

        unless date_sync_child_tracker?
          Rails.logger.info("SKIPPED date sync: tracker '#{tracker&.name}' does not count as a child task for date sync") if debug_logging
          return
        end

        parent_issues = collect_parent_issues
        if parent_issues.empty?
          Rails.logger.info("SKIPPED date sync: no parent issues found") if debug_logging
          return
        end

        earliest_date_custom_field_names.each do |field_name|
          ratchet_custom_field_up(parent_issues, field_name, :earliest, debug_logging)
        end

        latest_date_custom_field_names.each do |field_name|
          ratchet_custom_field_up(parent_issues, field_name, :latest, debug_logging)
        end

        if sync_planned_dates?
          ratchet_native_date_up(parent_issues, :start_date, 'Planned Start Date', :earliest, debug_logging)
          ratchet_native_date_up(parent_issues, :due_date, 'Planned End Date', :latest, debug_logging)
        end
      end

      def date_sync_child_tracker?
        date_sync_child_tracker_names.include?(tracker&.name.to_s.downcase)
      end

      def date_sync_child_tracker_names
        Setting.plugin_redmine_child_status_sync['date_sync_child_trackers'].to_s
               .split(',').map { |name| name.strip.downcase }.reject(&:blank?)
      end

      def earliest_date_custom_field_names
        Setting.plugin_redmine_child_status_sync['earliest_date_custom_fields'].to_s
               .split(/[\r\n,]+/).map(&:strip).reject(&:blank?)
      end

      def latest_date_custom_field_names
        Setting.plugin_redmine_child_status_sync['latest_date_custom_fields'].to_s
               .split(/[\r\n,]+/).map(&:strip).reject(&:blank?)
      end

      def sync_planned_dates?
        Setting.plugin_redmine_child_status_sync['sync_planned_dates'] == '1'
      end

      # Widens one custom date field on each parent to include this child's current value, but only
      # in the direction requested (:earliest pulls the parent's date backwards, :latest pushes it
      # forward) - never the reverse, so a child moving back inside the existing window is a no-op.
      def ratchet_custom_field_up(parent_issues, field_name, direction, debug_logging)
        custom_field = find_custom_field(field_name)
        unless custom_field
          Rails.logger.info("SKIPPED date sync: no custom field named '#{field_name}' found") if debug_logging
          return
        end

        child_value = parse_date_safe(raw_custom_field_value(self, custom_field.id))
        return if child_value.nil?

        parent_issues.each do |parent_issue|
          next unless parent_issue

          parent_value = parse_date_safe(raw_custom_field_value(parent_issue, custom_field.id))
          next unless date_extends_envelope?(child_value, parent_value, direction)

          begin
            write_custom_field_value(parent_issue, custom_field.id, child_value.to_s)
            Rails.logger.info("Child Status Sync: Set parent issue ##{parent_issue.id} '#{field_name}' to #{direction} value '#{child_value}' pushed by child ##{id}") if debug_logging
          rescue => e
            Rails.logger.error("ERROR updating parent issue ##{parent_issue.id} custom field '#{field_name}': #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))
          end
        end
      end

      # Same idea as ratchet_custom_field_up, but for Redmine's built-in start_date/due_date columns.
      def ratchet_native_date_up(parent_issues, column, label, direction, debug_logging)
        child_value = self[column]
        return if child_value.nil?

        parent_issues.each do |parent_issue|
          next unless parent_issue

          parent_value = parent_issue[column]
          next unless date_extends_envelope?(child_value, parent_value, direction)

          begin
            parent_issue.update_column(column, child_value)
            Rails.logger.info("Child Status Sync: Set parent issue ##{parent_issue.id} #{label} to #{direction} value '#{child_value}' pushed by child ##{id}") if debug_logging
          rescue => e
            Rails.logger.error("ERROR updating parent issue ##{parent_issue.id} #{label}: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))
          end
        end
      end

      # True when child_value would widen the parent's current envelope in the given direction:
      # an absent parent value is always widened; :earliest only moves the parent backwards in time,
      # :latest only moves it forwards.
      def date_extends_envelope?(child_value, parent_value, direction)
        return true if parent_value.nil?

        direction == :earliest ? child_value < parent_value : child_value > parent_value
      end

      def parse_date_safe(value)
        return nil if value.blank?

        value.is_a?(Date) ? value : Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Case-insensitive custom field lookup by name, matching how tracker/status names are already
      # matched elsewhere in this plugin - a settings value like "Actual Start Date" must still find
      # a custom field actually named "Actual start date" (or any other casing) rather than silently
      # finding nothing and no-opping the whole date sync feature.
      def find_custom_field(field_name)
        CustomField.where('LOWER(name) = ?', field_name.to_s.strip.downcase).first
      end

      def raw_custom_field_value(issue, custom_field_id)
        CustomValue.find_by(customized_type: 'Issue', customized_id: issue.id, custom_field_id: custom_field_id)&.value
      end

      def write_custom_field_value(issue, custom_field_id, value)
        custom_value = CustomValue.find_or_initialize_by(
          customized_type: 'Issue',
          customized_id: issue.id,
          custom_field_id: custom_field_id
        )
        custom_value.value = value.to_s
        custom_value.save!
      end

      def restricted_tracker?
        restricted_names = Setting.plugin_redmine_child_status_sync['restricted_trackers'].to_s
                                   .split(',').map { |name| name.strip.downcase }.reject(&:blank?)
        return false if restricted_names.empty?

        restricted_names.include?(tracker&.name.to_s.downcase)
      end

      def restricted_status?(status_id_value)
        restricted_names = Setting.plugin_redmine_child_status_sync['restricted_statuses'].to_s
                                   .split(',').map { |name| name.strip.downcase }.reject(&:blank?)
        return false if restricted_names.empty?

        status_name = IssueStatus.find_by(id: status_id_value)&.name
        restricted_names.include?(status_name.to_s.downcase)
      end

      # Ordered list of status names configured on the plugin settings page (one per line).
      # Editing this list is how new statuses get slotted into the flow - no code change needed.
      def configured_status_order
        Setting.plugin_redmine_child_status_sync['status_order'].to_s
               .split(/\r?\n/).map(&:strip).reject(&:blank?)
      end

      def status_order_index(status_id_value)
        return nil unless status_id_value

        status_name = IssueStatus.find_by(id: status_id_value)&.name
        return nil unless status_name

        order = configured_status_order.map(&:downcase)
        index = order.index(status_name.downcase)
        index
      end

      # Only allow a parent's status to move forward through the configured order.
      # If either status isn't found in the configured list, fall back to allowing the sync,
      # since we have no ordering information to restrict on.
      def forward_status_transition?(from_status_id, to_status_id)
        from_index = status_order_index(from_status_id)
        to_index = status_order_index(to_status_id)

        return true if from_index.nil? || to_index.nil?

        to_index > from_index
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