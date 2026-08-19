# Redmine Parent to Child Update - Issue Patch
# This module patches the Issue model to support parent-to-child field replication

module RedmineParentToChildUpdate
  module IssuePatch
    def self.included(base)
      base.send(:include, InstanceMethods)
      base.class_eval do
        # Store whether this is a child creation and parent reference
        attr_accessor :parent_to_replicate
        attr_accessor :replicate_parent_fields
      end
    end

    module InstanceMethods
      # Check if plugin is enabled.
      # Defaults to enabled — only disabled when the admin explicitly sets 'enabled' to '0'.
      # This handles fresh installs where the settings row may not exist in the DB yet.
      def parent_child_update_enabled?
        s = Setting.plugin_redmine_parent_to_child_update
        s.nil? || s['enabled'] != '0'
      end

      # Get enabled parent issue types
      def parent_issue_types
        types = Setting.plugin_redmine_parent_to_child_update['parent_issue_types']
        types ||= 'Change Request,CR,Bug,Feature,Task,Support'
        types.split(',').map(&:strip)
      end

      # Replicate parent fields to child using configured fields and required-field append
      def replicate_fields_from_parent(parent_issue)
        return unless parent_child_update_enabled?
        return unless parent_issue

        debug_logging = Setting.plugin_redmine_parent_to_child_update['enable_logging'] == '1'
        fields = replicated_field_keys

        Rails.logger.info("Parent to Child: Replicating fields from parent issue ##{parent_issue.id} to child") if debug_logging

        fields.each do |field|
          begin
            case field
            when 'priority'
              self.priority_id = parent_issue.priority_id
            when 'assigned_to'
              self.assigned_to_id = parent_issue.assigned_to_id
            when 'category'
              self.category_id = parent_issue.category_id
            when 'fixed_version'
              self.fixed_version_id = parent_issue.fixed_version_id
            when 'description'
              self.description = "[Child of Issue #{parent_issue.id}]\n\n" + parent_issue.description.to_s
            when 'due_date'
              self.due_date = parent_issue.due_date
            when 'start_date'
              self.start_date = parent_issue.start_date
            when 'estimated_hours'
              self.estimated_hours = parent_issue.estimated_hours
            when 'custom_fields'
              copy_custom_values_from_parent(parent_issue, debug_logging)
            when 'author'
              self.author_id = parent_issue.author_id
            when 'subject'
              self.subject = parent_issue.subject
            end
            Rails.logger.info("  Replicated field #{field}") if debug_logging
          rescue => e
            Rails.logger.warn("Error replicating field #{field}: #{e.message}") if debug_logging
          end
        end

        append_required_custom_fields(parent_issue, debug_logging) if append_required_fields?

        Rails.logger.info("Parent to Child: Field replication completed for child issue") if debug_logging
      end

      def replicated_field_keys
        default_fields = %w[priority assigned_to category fixed_version description due_date start_date estimated_hours custom_fields author]
        raw = Setting.plugin_redmine_parent_to_child_update['replicated_fields']
        keys = raw.to_s.split(',').map(&:strip).reject(&:blank?).map(&:downcase)
        keys.empty? ? default_fields : keys
      end

      def append_required_fields?
        Setting.plugin_redmine_parent_to_child_update['append_required_fields'] == '1'
      end

      def copy_custom_values_from_parent(parent_issue, debug_logging)
        return unless parent_issue.respond_to?(:custom_values) && parent_issue.custom_values.present?

        parent_issue.custom_values.each do |parent_cv|
          custom_field_id = parent_cv.custom_field_id
          value = parent_cv.value
          next unless custom_field_id.present?

          begin
            if self.new_record?
              # For new records, build custom_values association directly so values persist on save
              child_cv = self.custom_values.build
              child_cv.custom_field_id = custom_field_id
              child_cv.value = value
            else
              # For existing records, use the setter
              self.custom_field_value(custom_field_id, value) if self.respond_to?('custom_field_value')
            end
            Rails.logger.info("  Copied custom field ID #{custom_field_id}: #{value}") if debug_logging
          rescue => e
            Rails.logger.warn("Error copying custom field #{custom_field_id}: #{e.message}") if debug_logging
          end
        end
      end

      def append_required_custom_fields(parent_issue, debug_logging)
        return unless respond_to?(:custom_fields) && self.custom_fields.present?

        # Iterate over the child's custom fields and append required ones from parent
        self.custom_fields.each do |cf|
          next unless cf.respond_to?(:is_required) ? cf.is_required : cf.required?
          value = parent_issue.custom_field_value(cf.id)
          # Fall back to the field's default_value when the parent doesn't have this field
          value = cf.default_value if value.nil?
          # Use empty string so the custom_value record is present (avoids "cannot be blank" on missing records)
          value = '' if value.nil?

          begin
            if self.new_record?
              # For new records, build custom_values association directly
              child_cv = self.custom_values.find { |cv| cv.custom_field_id == cf.id }
              if child_cv.nil?
                child_cv = self.custom_values.build
                child_cv.custom_field_id = cf.id
              end
              child_cv.value = value
            else
              # For existing records, use the setter
              self.custom_field_value(cf.id, value) if self.respond_to?('custom_field_value')
            end
            Rails.logger.info("  Appended required custom field #{cf.name}: #{value}") if debug_logging
          rescue => e
            Rails.logger.warn("Error appending required custom field #{cf.name}: #{e.message}") if debug_logging
          end
        end
      end

      # Tracker names that trigger the primary child-creation popup.
      # Reads from plugin settings; falls back to the hard-coded default list.
      def popup_parent_tracker_names
        ['Change Request', 'User Story']
      end

      # Check if this issue should trigger the primary child creation popup
      def should_show_child_popup?
        return false unless parent_child_update_enabled?
        return false if parent_id.present? # This is already a child
        return false unless new_record?    # Only on creation
        return false unless tracker

        popup_parent_tracker_names.any? { |name| name.casecmp?(tracker.name) }
      end

      # Check if this issue should trigger the additional-task-only popup
      # (fires for any non-primary-popup tracker that has dev/test tasks or additional children configured)
      def should_show_additional_child_popup?
        return false unless parent_child_update_enabled?
        return false if parent_id.present?
        return false unless new_record?
        return false unless tracker
        # Don't show for trackers that already get the primary popup
        return false if popup_parent_tracker_names.any? { |name| name.casecmp?(tracker.name) }

        create_dev_test_tasks? || additional_child_trackers.any?
      end

      # Get available issue types for child creation
      def available_child_trackers
        return [] unless project

        project.trackers.select { |t| t.id != tracker&.id }
      end

      def create_additional_children_enabled?
        Setting.plugin_redmine_parent_to_child_update['create_additional_children'] == '1'
      end

      def create_dev_test_tasks?
        Setting.plugin_redmine_parent_to_child_update['create_dev_test_tasks'] == '1'
      end

      def additional_child_tracker_names
        raw = Setting.plugin_redmine_parent_to_child_update['additional_child_trackers']
        raw.to_s.split(',').map(&:strip).reject(&:blank?)
      end

      def additional_child_trackers
        return [] unless project && create_additional_children_enabled?

        allowed_names = additional_child_tracker_names
        return [] if allowed_names.empty?

        project.trackers.select { |t| allowed_names.include?(t.name) }
      end
    end
  end
end
