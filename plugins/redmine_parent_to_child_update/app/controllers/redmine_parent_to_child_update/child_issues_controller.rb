# Redmine Parent to Child Update - Child Issues Controller
# This controller handles AJAX requests for child issue operations

module RedmineParentToChildUpdate
  class ChildIssuesController < ApplicationController
    before_action :find_issue, only: [:get_trackers, :get_required_fields, :create_child, :list_children]

    accept_api_auth :create_child

    # All supported standard Redmine issue fields for the popup.
    # Add new entries here as Redmine gains new fields — they auto-appear in admin config.
    STANDARD_POPUP_FIELDS = {
      'status_id'        => { name: ->{ l(:field_status)          }, format: 'select' },
      'description'      => { name: ->{ l(:field_description)     }, format: 'text'   },
      'priority_id'      => { name: ->{ l(:field_priority)        }, format: 'select' },
      'assigned_to_id'   => { name: ->{ l(:field_assigned_to)     }, format: 'select' },
      'category_id'      => { name: ->{ l(:field_category)        }, format: 'select' },
      'fixed_version_id' => { name: ->{ l(:field_fixed_version)   }, format: 'select' },
      'start_date'       => { name: ->{ l(:field_start_date)      }, format: 'date'   },
      'due_date'         => { name: ->{ l(:field_due_date)        }, format: 'date'   },
      'estimated_hours'  => { name: ->{ l(:field_estimated_hours) }, format: 'float'  },
      'done_ratio'       => { name: ->{ l(:field_done_ratio)      }, format: 'int'    },
    }.freeze

    # Return fields (standard + custom) to display in the child-creation popup.
    def get_required_fields
      return render_404 unless @issue
      return render_403 unless User.current.allowed_to?(:add_issues, @issue.project)

      tracker_id = params[:tracker_id].to_i
      return render json: { fields: [] } unless tracker_id > 0

      tracker = Tracker.find_by(id: tracker_id)
      return render json: { fields: [] } unless tracker

      begin
        plugin_settings  = Setting.plugin_redmine_parent_to_child_update || {}
        popup_fields_cfg = plugin_settings['tracker_popup_fields'] || {}
        configured_ids   = Array(popup_fields_cfg[tracker_id.to_s]).map(&:to_s).uniq

        if configured_ids.empty?
          # Never configured → default to ALL fields for this tracker
          tracker_core = tracker.respond_to?(:core_fields) ? Array(tracker.core_fields).map(&:to_s) : []
          always_std   = %w[status_id description priority_id]
          std_keys     = STANDARD_POPUP_FIELDS.keys.select { |k| always_std.include?(k) || tracker_core.include?(k) }
          cf_ids       = tracker.custom_fields.map(&:id)
        else
          std_keys = configured_ids.select { |v| v.start_with?('std_') }.map { |v| v.sub('std_', '') }
          cf_ids   = configured_ids.map { |v| v.sub(/\Acf_/, '').to_i }.select { |v| v > 0 }.uniq
        end

        # ── Standard fields ──────────────────────────────────────────────────
        std_fields = std_keys.filter_map do |key|
          defn = STANDARD_POPUP_FIELDS[key]
          next unless defn

          opts = {
            id:              "std_#{key}",
            std_key:         key,
            name:            defn[:name].respond_to?(:call) ? defn[:name].call : defn[:name],
            field_format:    defn[:format],
            possible_values: [],
            default_value:   '',
            value:           '',
            is_required:     false,
            is_standard:     true
          }

          case key
          when 'status_id'
            statuses = begin
              IssueStatus.respond_to?(:sorted) ? IssueStatus.sorted : IssueStatus.order(:position)
            rescue
              IssueStatus.all
            end
            opts[:possible_values] = statuses.map { |s| { value: s.id.to_s, label: s.name } }
            default_status = begin
              IssueStatus.find_by(is_default: true)
            rescue
              nil
            end || IssueStatus.first
            opts[:value] = default_status&.id.to_s || ''
          when 'estimated_hours'
            opts[:value] = @issue.estimated_hours.to_s
          when 'start_date'
            opts[:value] = @issue.start_date&.to_s || ''
          when 'due_date'
            opts[:value] = @issue.due_date&.to_s || ''
          when 'done_ratio'
            opts[:value] = @issue.done_ratio.to_s
          when 'description'
            opts[:value] = @issue.description.to_s
          when 'assigned_to_id'
            opts[:possible_values] = @issue.project.members.includes(:user)
              .map { |m| { value: m.user_id.to_s, label: m.user.name } }
            opts[:value] = @issue.assigned_to_id.to_s
          when 'priority_id'
            opts[:possible_values] = IssuePriority.active
              .map { |p| { value: p.id.to_s, label: p.name } }
            opts[:value] = @issue.priority_id.to_s
          when 'category_id'
            opts[:possible_values] = @issue.project.issue_categories
              .map { |c| { value: c.id.to_s, label: c.name } }
            opts[:value] = @issue.category_id.to_s
          when 'fixed_version_id'
            opts[:possible_values] = @issue.project.shared_versions.open
              .map { |v| { value: v.id.to_s, label: v.name } }
            opts[:value] = @issue.fixed_version_id.to_s
          end

          opts
        end

        # ── Custom fields ────────────────────────────────────────────────────
        all_tracker_cfs = tracker.custom_fields.to_a
        configured_cfs  = all_tracker_cfs.select { |cf| cf_ids.include?(cf.id) }
        cf_fields = configured_cfs.map do |cf|
          {
            id:              cf.id,
            name:            cf.name,
            field_format:    cf.field_format,
            possible_values: cf.field_format == 'list' ? cf.possible_values : [],
            default_value:   cf.default_value.to_s,
            value:           @issue.custom_field_value(cf.id).to_s,
            is_required:     cf.is_required,
            is_standard:     false
          }
        end

        render json: { fields: std_fields + cf_fields }
      rescue => e
        Rails.logger.error("PCU get_required_fields error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: "Failed to load fields: #{e.message}", fields: [] }, status: :internal_server_error
      end
    end

    # Get available trackers for child creation
    def get_trackers
      return render_404 unless @issue
      return render_403 unless User.current.allowed_to?(:add_issues, @issue.project)

      available_trackers = @issue.available_child_trackers
      
      render json: available_trackers.map { |t| { id: t.id, name: t.name } }
    end

    # Create a child issue
    def create_child
      return render_404 unless @issue
      return render_403 unless User.current.allowed_to?(:add_issues, @issue.project)

      tracker_id = params[:tracker_id].to_i
      subject = params[:subject]
      description = params[:description].to_s

      unless tracker_id > 0 && subject.present?
        return render json: { error: 'Invalid parameters' }, status: :bad_request
      end

      begin
        tracker = Tracker.find(tracker_id)
        unless @issue.project.trackers.exists?(id: tracker.id)
          return render json: { error: 'Tracker is not included in the list' }, status: :unprocessable_entity
        end

        created_children = []

        primary_child = Issue.new(
          project: @issue.project,
          tracker: tracker,
          subject: subject,
          description: description,
          status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : (begin; IssueStatus.find_by(is_default: true); rescue ActiveRecord::StatementInvalid; nil; end) || IssueStatus.first),
          priority: @issue.priority,
          author_id: @issue.author_id,
          parent_id: @issue.id
        )
        primary_child.replicate_fields_from_parent(@issue)

        # Apply standard field values submitted from the popup
        if params[:std_fields].is_a?(ActionController::Parameters) || params[:std_fields].is_a?(Hash)
          params[:std_fields].each do |key, value|
            next if value.blank?
            case key.to_s
            when 'status_id'        then primary_child.status_id        = value.to_i
            when 'estimated_hours'  then primary_child.estimated_hours  = value.to_f
            when 'start_date'       then primary_child.start_date       = value
            when 'due_date'         then primary_child.due_date         = value
            when 'done_ratio'       then primary_child.done_ratio       = value.to_i.clamp(0, 100)
            when 'description'      then primary_child.description      = value
            when 'assigned_to_id'   then primary_child.assigned_to_id   = value.to_i
            when 'priority_id'      then primary_child.priority_id      = value.to_i
            when 'category_id'      then primary_child.category_id      = value.to_i
            when 'fixed_version_id' then primary_child.fixed_version_id = value.to_i
            end
          end
        end

        # Apply custom field values submitted from the popup
        if params[:custom_field_values].is_a?(ActionController::Parameters) || params[:custom_field_values].is_a?(Hash)
          params[:custom_field_values].each do |cf_id, value|
            next if value.blank?
            cv = primary_child.custom_values.find { |v| v.custom_field_id == cf_id.to_i } ||
                 primary_child.custom_values.build(custom_field_id: cf_id.to_i)
            cv.value = value
          end
        end
        if primary_child.save
          created_children << primary_child
        else
          return render json: { error: primary_child.errors.full_messages.join(', ') }, status: :unprocessable_entity
        end

        additional_ids = Array(params[:additional_child_tracker_ids]).map(&:to_i).select { |id| id > 0 }
        additional_ids.each do |additional_id|
          next if additional_id == tracker.id
          next unless @issue.project.trackers.exists?(id: additional_id)

          additional_tracker = Tracker.find(additional_id)
          additional_child = Issue.new(
            project: @issue.project,
            tracker: additional_tracker,
            subject: "#{subject} - #{additional_tracker.name}",
            description: description,
            status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : (begin; IssueStatus.find_by(is_default: true); rescue ActiveRecord::StatementInvalid; nil; end) || IssueStatus.first),
            priority: @issue.priority,
            author_id: @issue.author_id,
            parent_id: primary_child.id
          )
          additional_child.replicate_fields_from_parent(@issue)
          if additional_child.save(validate: false)
            created_children << additional_child
          else
            Rails.logger.error("Error creating additional child issue: #{additional_child.errors.full_messages.join(', ')}")
          end
        end

        # ── Chain popup logic ──────────────────────────────────────────────────
        # Check if the newly created child's tracker has child types configured.
        # If yes → redirect to the child's page with popup auto-open (chain continues).
        # If no  → stay on current page and re-open popup (loop for more siblings).
        trackers_map = Setting.plugin_redmine_parent_to_child_update['popup_child_trackers_by_parent'] || {}
        child_tracker_filter = trackers_map[primary_child.tracker_id.to_s].to_s.strip

        if child_tracker_filter.present?
          # Child has grandchild types configured → set session and redirect to child
          session[:redmine_parent_to_child_show_prompt_for] = primary_child.id
          render json: {
            children:    created_children.map { |c| { id: c.id, subject: c.subject, url: issue_path(c) } },
            redirect_to: issue_path(primary_child)
          }, status: :created
        else
          # No further chain → loop: stay on same page, re-open popup for next sibling
          render json: {
            children: created_children.map { |c| { id: c.id, subject: c.subject, url: issue_path(c) } },
            loop:     true
          }, status: :created
        end
      rescue => e
        Rails.logger.error("Error creating child issue: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end
    end

    # Get child issues of a parent
    def list_children
      return render_404 unless @issue
      return render_403 unless User.current.allowed_to?(:view_issues, @issue.project)

      children = @issue.descendants

      render json: children.map { |c| { 
        id: c.id, 
        subject: c.subject, 
        status: c.status.name,
        tracker: c.tracker.name
      } }
    end

    private

    def find_issue
      @issue = Issue.find(params[:issue_id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
end
