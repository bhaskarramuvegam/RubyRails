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
      'priority_id'      => { name: ->{ l(:field_priority)        }, format: 'select' },
      'assigned_to_id'   => { name: ->{ l(:field_assigned_to)     }, format: 'select' },
      'author_id'        => { name: ->{ l(:field_author)          }, format: 'select' },
      'category_id'      => { name: ->{ l(:field_category)        }, format: 'select' },
      'fixed_version_id' => { name: ->{ l(:field_fixed_version)   }, format: 'select' },
      'start_date'       => { name: ->{ l(:field_start_date)      }, format: 'date'   },
      'due_date'         => { name: ->{ l(:field_due_date)        }, format: 'date'   },
      'estimated_hours'  => { name: ->{ l(:field_estimated_hours) }, format: 'float'  },
      'done_ratio'       => { name: ->{ l(:field_done_ratio)      }, format: 'int'    },
      'description'      => { name: ->{ l(:field_description)     }, format: 'text'   },
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

        # Excluded field names (admin config, matched by name case-insensitively)
        excluded_names = (plugin_settings['popup_excluded_fields'] || 'Release Details')
                           .split(',').map(&:strip).reject(&:empty?).map(&:downcase)

        # ── Applicable standard fields for this tracker ──────────────────────
        # Only status, priority, assignee, author, description are universally present.
        # All other standard fields (category, version, dates, etc.) must be in
        # tracker.core_fields — exactly the same gate Redmine uses on the issue form.
        tracker_core = tracker.respond_to?(:core_fields) ? Array(tracker.core_fields).map(&:to_s) : []
        always_std   = %w[status_id priority_id assigned_to_id author_id description]
        applicable_std_keys = STANDARD_POPUP_FIELDS.keys.select { |k|
          always_std.include?(k) || tracker_core.include?(k)
        }

        # Additionally hide category/version when the project has none configured —
        # prevents an empty dropdown that can never be filled.
        if applicable_std_keys.include?('category_id') &&
           @issue.project.issue_categories.empty?
          applicable_std_keys -= ['category_id']
        end
        if applicable_std_keys.include?('fixed_version_id') &&
           !@issue.project.shared_versions.open.exists?
          applicable_std_keys -= ['fixed_version_id']
        end

        # ── Applicable custom fields: tracker CFs enabled for this project ───
        # Scope to IssueCustomField only — ProjectCustomField and VersionCustomField
        # (shown under "Projects" / "Milestones" tabs in admin) must never appear in
        # the issue popup even if they share the same join table rows.
        # Redmine's is_for_all=true → all projects; false → only listed projects.
        project_id = @issue.project.id
        applicable_cfs = tracker.custom_fields.where(type: 'IssueCustomField')
                                .order(:position).select { |cf|
          cf.is_for_all? || cf.project_ids.include?(project_id)
        }
        applicable_cf_map = applicable_cfs.index_by(&:id)  # id => cf

        # ── Determine display order ───────────────────────────────────────────
        # Stored ids use "std_<key>" for standard fields and plain "<cf_id>" for custom fields.
        configured_ids = Array(popup_fields_cfg[tracker_id.to_s]).map(&:to_s).uniq

        if configured_ids.any?
          # Admin has explicitly saved a field config for this tracker.
          # Show ONLY those fields (filtered to ones applicable to this project).
          # No auto-append — fields not in the saved config are intentionally excluded.
          # New std fields are still auto-added; new CFs are NOT (admin must add them explicitly).
          ordered_ids = configured_ids.select { |fid|
            if fid.start_with?('std_')
              applicable_std_keys.include?(fid.sub('std_', ''))
            else
              cf_id = fid.sub(/\Acf_/, '').to_i
              applicable_cf_map.key?(cf_id)
            end
          }
          # Auto-append standard fields that are newly applicable (tracker core_fields change)
          # but do NOT auto-append custom fields — admin controls those explicitly.
          in_order = ordered_ids.to_set
          applicable_std_keys.each do |k|
            fid = "std_#{k}"; ordered_ids << fid unless in_order.include?(fid)
          end
        else
          # No config saved yet: show all applicable std fields + all applicable CFs
          ordered_ids = applicable_std_keys.map { |k| "std_#{k}" } +
                        applicable_cfs.map { |cf| cf.id.to_s }
        end

        # ── Build field objects in order ─────────────────────────────────────
        all_fields = ordered_ids.filter_map do |fid|
          if fid.start_with?('std_')
            key  = fid.sub('std_', '')
            defn = STANDARD_POPUP_FIELDS[key]
            next unless defn
            field_name = defn[:name].respond_to?(:call) ? defn[:name].call : defn[:name]
            next if excluded_names.include?(field_name.to_s.downcase)
            opts = { id: "std_#{key}", std_key: key, name: field_name,
                     field_format: defn[:format], possible_values: [],
                     default_value: '', value: '', is_required: false, is_standard: true }
            case key
            when 'status_id'
              statuses = begin IssueStatus.respond_to?(:sorted) ? IssueStatus.sorted : IssueStatus.order(:position)
                         rescue; IssueStatus.all; end
              opts[:possible_values] = statuses.map { |s| { value: s.id.to_s, label: s.name } }
              default_status = (IssueStatus.find_by(is_default: true) rescue nil) || IssueStatus.first
              opts[:value] = default_status&.id.to_s || ''
            when 'estimated_hours' then opts[:value] = @issue.estimated_hours.to_s
            when 'start_date'      then opts[:value] = @issue.start_date&.to_s || ''
            when 'due_date'        then opts[:value] = @issue.due_date&.to_s || ''
            when 'done_ratio'      then opts[:value] = @issue.done_ratio.to_s
            when 'description'     then opts[:value] = @issue.description.to_s
            when 'assigned_to_id'
              opts[:possible_values] = @issue.project.members.includes(:user)
                .map { |m| { value: m.user_id.to_s, label: m.user.name } }
              opts[:value] = @issue.assigned_to_id.to_s
            when 'author_id'
              opts[:possible_values] = @issue.project.members.includes(:user)
                .map { |m| { value: m.user_id.to_s, label: m.user.name } }
              opts[:value] = User.current.id.to_s
            when 'priority_id'
              opts[:possible_values] = IssuePriority.active.map { |p| { value: p.id.to_s, label: p.name } }
              opts[:value] = @issue.priority_id.to_s
            when 'category_id'
              opts[:possible_values] = @issue.project.issue_categories.map { |c| { value: c.id.to_s, label: c.name } }
              opts[:value] = @issue.category_id.to_s
            when 'fixed_version_id'
              opts[:possible_values] = @issue.project.shared_versions.open.map { |v| { value: v.id.to_s, label: v.name } }
              opts[:value] = @issue.fixed_version_id.to_s
            end
            opts
          else
            cf_id = fid.sub(/\Acf_/, '').to_i
            next unless cf_id > 0
            cf = applicable_cf_map[cf_id]   # nil if not applicable to this project
            next unless cf
            next if excluded_names.include?(cf.name.to_s.downcase)
            pv = case cf.field_format
                 when 'list'
                   Array(cf.possible_values).map(&:to_s).reject(&:empty?)
                 when 'enumeration'
                   # CustomFieldEnumeration-backed list
                   cf.respond_to?(:enumerations) ?
                     cf.enumerations.active.map { |e| e.name.to_s } :
                     Array(cf.possible_values).map(&:to_s).reject(&:empty?)
                 else
                   []
                 end
            raw_val = @issue.custom_field_value(cf.id)
            val_str = raw_val.is_a?(Array) ? Array(raw_val).reject(&:empty?).first.to_s : raw_val.to_s
            { id: cf.id, name: cf.name, field_format: pv.any? ? 'list' : cf.field_format,
              possible_values: pv,
              default_value: cf.default_value.to_s,
              value: val_str,
              is_required: cf.is_required, is_standard: false }
          end
        end

        render json: { fields: all_fields }
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
            when 'author_id'        then primary_child.author_id        = value.to_i
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
          # save_attachments expects a Hash but params[:attachments] is ActionController::Parameters
          # in Rails 5+, which fails the is_a?(Hash) check inside save_attachments silently.
          # Use Attachment.create! directly instead.
          if params[:attachments].present?
            params[:attachments].each do |_idx, att_params|
              file = att_params[:file]
              next unless file.respond_to?(:read)
              begin
                Attachment.create!(
                  container:   primary_child,
                  file:        file,
                  filename:    att_params[:filename].presence || file.original_filename,
                  description: att_params[:description].to_s,
                  author:      User.current
                )
              rescue => e
                Rails.logger.error("PCU attachment error: #{e.message}")
              end
            end
          end
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
        # Chain: Change Request → User Story → Task (hardcoded, ends at Task)
        # skip_chain=1 → "Save Tracker" button: no chain
        # skip_chain=0 → "Save & Create Child Tracker": navigate to child show page
        #   so the auto-popup fires there for the next level
        skip_chain         = params[:skip_chain].to_s == '1'
        chain_parents      = ['change request', 'user story']
        # Chain continues if user clicked "Save & Create Child" AND the newly created
        # child is itself a chain-parent tracker (i.e. User Story, not Task)
        child_is_chain_parent = chain_parents.any? { |n| n.casecmp?(primary_child.tracker.name) }

        if !skip_chain && child_is_chain_parent
          session[:redmine_parent_to_child_show_prompt_for] = primary_child.id
          render json: {
            children:    created_children.map { |c| { id: c.id, subject: c.subject, url: issue_path(c) } },
            redirect_to: issue_path(primary_child)
          }, status: :created
        else
          render json: {
            children: created_children.map { |c| { id: c.id, subject: c.subject, url: issue_path(c) } }
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
