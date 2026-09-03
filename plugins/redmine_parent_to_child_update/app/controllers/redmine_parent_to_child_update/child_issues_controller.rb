# Redmine Parent to Child Update - Child Issues Controller
# This controller handles AJAX requests for child issue operations

module RedmineParentToChildUpdate
  class ChildIssuesController < ApplicationController
    before_action :find_issue, only: [:get_trackers, :get_required_fields, :create_child, :list_children]

    accept_api_auth :create_child

    # All supported standard Redmine issue fields for the popup.
    # Add new entries here as Redmine gains new fields — they auto-appear in admin config.
    NO_INHERIT_DATE_ASSIGNEE_PATTERN = /task/i

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
      'is_private'       => { name: ->{ l(:field_is_private)      }, format: 'bool'   },
      'parent_issue_id'  => { name: ->{ l(:field_parent_issue)    }, format: 'text'   },
    }.freeze

    # Return fields (standard + custom) to display in the child-creation popup.
    def get_required_fields
      return render_404 unless @issue
      return render_403 unless User.current.allowed_to?(:add_issues, @issue.project)

      tracker_id = params[:tracker_id].to_i
      return render json: { fields: [] } unless tracker_id > 0

      tracker = Tracker.find_by(id: tracker_id)
      return render json: { fields: [] } unless tracker

      # Don't inherit dates, assignee or estimated hours when either the child
      # tracker OR the parent tracker is Task-level — both need independent scheduling.
      no_inherit = tracker.name.match?(NO_INHERIT_DATE_ASSIGNEE_PATTERN) ||
                   @issue.tracker.name.match?(NO_INHERIT_DATE_ASSIGNEE_PATTERN)

      begin
        plugin_settings  = Setting.plugin_redmine_parent_to_child_update || {}

        # ── Workflow field permissions for current user + child tracker ──────────
        # The popup creates a NEW issue, so only the initial status column applies.
        # In Redmine's Fields permissions grid the relevant column is the one for
        # the tracker's default/initial status (old_status_id = default_status_id).
        # Rules stored for other statuses ("In Progress", "Resolved", …) apply only
        # when EDITING an existing issue already in that status — not for creation.
        # Rule priority: hidden(3) > readonly(2) > required(1).
        workflow_rules = begin
          role_ids = User.current.roles_for_project(@issue.project)
                         .select { |r| r.builtin == 0 }.map(&:id)

          # Use the status_id param if the user already changed the Status dropdown
          # in the popup; otherwise fall back to the tracker's own default status.
          # Redmine 4.0+ stores a per-tracker default_status_id on the Tracker model.
          selected_status_id = params[:status_id].to_i
          workflow_status_id = if selected_status_id > 0
                                 selected_status_id
                               elsif tracker.respond_to?(:default_status_id) && tracker.default_status_id.to_i > 0
                                 tracker.default_status_id.to_i
                               elsif tracker.respond_to?(:default_status) && tracker.default_status
                                 tracker.default_status.id.to_i
                               else
                                 IssueStatus.find_by(is_default: true)&.id.to_i ||
                                 IssueStatus.order(:position).first&.id.to_i || 0
                               end

          rule_priority = { 'hidden' => 3, 'readonly' => 2, 'required' => 1 }
          rules = {}
          if role_ids.any? && workflow_status_id > 0
            WorkflowPermission
              .where(tracker_id: tracker_id, role_id: role_ids,
                     old_status_id: workflow_status_id)
              .pluck(:field_name, :rule)
              .each do |field_name, rule|
                next if rule.blank?
                existing = rules[field_name]
                if existing.nil? || rule_priority[rule].to_i > rule_priority[existing].to_i
                  rules[field_name] = rule
                end
              end
          end
          Rails.logger.warn("[PCU] workflow: tracker=#{tracker_id} status=#{workflow_status_id} roles=#{role_ids} rules=#{rules}")
          rules
        rescue => e
          Rails.logger.warn("[PCU] workflow error: #{e.message}")
          {}
        end

        # ── Applicable standard fields for this tracker ──────────────────────
        # Only status, priority, assignee, author, description are universally present.
        # All other standard fields (category, version, dates, etc.) must be in
        # tracker.core_fields — exactly the same gate Redmine uses on the issue form.
        tracker_core = tracker.respond_to?(:core_fields) ? Array(tracker.core_fields).map(&:to_s) : []
        # is_private is always available on every tracker (Redmine core field)
        always_std   = %w[status_id priority_id assigned_to_id description is_private parent_issue_id]
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

        # ── TrackerFieldsConfiguration integration ────────────────────────────
        # If the TFC plugin is active: apply its hidden-field rules so fields
        # the admin hid for this project+tracker are also hidden in the popup,
        # and collect any registered "extra fields" (Sprint, Color, etc.) so
        # they appear in the popup as editable inputs.
        tfc_extra_fields = []  # [{key:, label:, format:, possible_values:}]
        tfc_active = begin
          defined?(TrackerFieldsConfiguration) && TrackerFieldsConfiguration.enabled?
        rescue
          false
        end
        if tfc_active
          pid_s = project_id.to_s
          tid_s = tracker_id.to_s

          # Remove std fields TFC has hidden for this project+tracker
          tfc_hidden_std = TrackerFieldsConfiguration.hidden_standard_field_keys(pid_s, tid_s) rescue []
          applicable_std_keys -= tfc_hidden_std

          # Remove custom fields TFC has hidden
          tfc_hidden_cf_ids = (TrackerFieldsConfiguration.hidden_custom_field_ids(pid_s, tid_s) rescue []).map(&:to_i)
          applicable_cfs    = applicable_cfs.reject { |cf| tfc_hidden_cf_ids.include?(cf.id) }
          applicable_cf_map = applicable_cfs.index_by(&:id)

          # TFC field promotion ordering: build a map of cf_id => after_std_key
          tfc_after = TrackerFieldsConfiguration.after_fields_for(pid_s, tid_s) rescue {}

          # Collect registered extra fields (plugin-injected: Sprint, Color, etc.)
          (TrackerFieldsConfiguration.extra_fields_for(pid_s, tid_s) rescue []).each do |ef|
            next if (TrackerFieldsConfiguration.hidden_field_keys(pid_s, tid_s) rescue []).include?("ext_#{ef[:key]}")
            tfc_extra_fields << {
              key:            ef[:key],
              label:          ef[:label].to_s,
              format:         ef[:key] == 'color' ? 'color' : 'text',
              possible_values: []
            }
          end
        else
          tfc_after  = {}
        end

        # ── Detect plugin-injected fields directly from the Issue model ───────
        # These fields (Sprint, Color, Watchers) are added by external plugins
        # (e.g. Redmine Agile). We detect them by checking whether the Issue
        # model responds to the relevant attribute/method, so they appear even
        # when TFC has not registered them as extra fields.
        extra_key_set = tfc_extra_fields.map { |e| e[:key] }.to_set

        # Watchers — always available in Redmine core
        unless extra_key_set.include?('watcher_user_ids')
          watcher_members = @issue.project.members.includes(:user).map { |m|
            { value: m.user_id.to_s, label: m.user.name }
          }
          tfc_extra_fields << {
            key: 'watcher_user_ids', label: 'Watchers', format: 'multiselect',
            possible_values: watcher_members
          }
        end

        # Color — Redmine Agile adds a `color` attribute to Issue
        if !extra_key_set.include?('color') && @issue.respond_to?(:color)
          tfc_extra_fields << { key: 'color', label: 'Color', format: 'color', possible_values: [] }
        end

        # Sprint — Redmine Agile: try common model names for sprint options
        if !extra_key_set.include?('agile_sprint_id') && !extra_key_set.include?('sprint_id')
          sprint_attr = [:agile_sprint_id, :sprint_id].find { |a| @issue.respond_to?(a) }
          if sprint_attr
            sprint_options = begin
              sprint_class = ['AgileSprint', 'AgileVersion', 'Sprint'].map { |n|
                Object.const_get(n) rescue nil
              }.compact.first
              if sprint_class && sprint_class.respond_to?(:where)
                sprint_class.where(project_id: @issue.project.id).map { |s|
                  { value: s.id.to_s, label: s.name.to_s }
                }
              else
                []
              end
            rescue
              []
            end
            tfc_extra_fields << {
              key: sprint_attr.to_s, label: 'Sprint', format: 'select',
              possible_values: sprint_options
            }
          end
        end

        # ── Determine display order ───────────────────────────────────────────
        # Fields are always auto-detected from Redmine's tracker+project configuration.
        # If TFC has "after" promotion rules, interleave CFs after their anchor std field;
        # otherwise fall back to tracker position order.
        if tfc_after.any?
          ordered_ids = applicable_std_keys.map { |k| "std_#{k}" }
          tfc_after.each do |cf_id_s, after_key|
            cf_id = cf_id_s.to_i
            next unless applicable_cf_map.key?(cf_id)
            anchor = "std_#{after_key}"
            idx = ordered_ids.index(anchor)
            if idx
              ordered_ids.insert(idx + 1, cf_id_s) unless ordered_ids.include?(cf_id_s)
            else
              ordered_ids << cf_id_s unless ordered_ids.include?(cf_id_s)
            end
          end
          applicable_cfs.each do |cf|
            ordered_ids << cf.id.to_s unless ordered_ids.include?(cf.id.to_s)
          end
        else
          ordered_ids = applicable_std_keys.map { |k| "std_#{k}" } +
                        applicable_cfs.map { |cf| cf.id.to_s }
        end
        # Always append TFC extra fields (Sprint, Color, etc.) at the end
        tfc_extra_fields.each { |ef| ordered_ids << "ext_#{ef[:key]}" }

        # ── Build field objects in order ─────────────────────────────────────
        all_fields = ordered_ids.filter_map do |fid|
          if fid.start_with?('std_')
            key  = fid.sub('std_', '')
            defn = STANDARD_POPUP_FIELDS[key]
            next unless defn
            field_name = defn[:name].respond_to?(:call) ? defn[:name].call : defn[:name]
            wf_rule = workflow_rules[key].to_s
            next if wf_rule == 'hidden'
            opts = { id: "std_#{key}", std_key: key, name: field_name,
                     field_format: defn[:format], possible_values: [],
                     default_value: '', value: '', is_standard: true,
                     is_required: (wf_rule == 'required'),
                     is_readonly: (wf_rule == 'readonly') }
            case key
            when 'status_id'
              statuses = begin IssueStatus.respond_to?(:sorted) ? IssueStatus.sorted : IssueStatus.order(:position)
                         rescue; IssueStatus.all; end
              opts[:possible_values] = statuses.map { |s| { value: s.id.to_s, label: s.name } }
              default_status = (IssueStatus.find_by(is_default: true) rescue nil) || IssueStatus.first
              opts[:value] = default_status&.id.to_s || ''
            when 'estimated_hours' then opts[:value] = no_inherit ? '' : @issue.estimated_hours.to_s
            when 'start_date'      then opts[:value] = no_inherit ? '' : (@issue.start_date&.to_s || '')
            when 'due_date'        then opts[:value] = no_inherit ? '' : (@issue.due_date&.to_s || '')
            when 'done_ratio'      then opts[:value] = @issue.done_ratio.to_s
            when 'description'     then opts[:value] = @issue.description.to_s
            when 'assigned_to_id'
              opts[:possible_values] = @issue.project.members.includes(:user)
                .map { |m| { value: m.user_id.to_s, label: m.user.name } }
              opts[:value] = no_inherit ? '' : @issue.assigned_to_id.to_s
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
            when 'is_private'
              opts[:possible_values] = [{ value: '0', label: 'No' }, { value: '1', label: 'Yes' }]
              opts[:value] = @issue.is_private? ? '1' : '0'
            when 'parent_issue_id'
              opts[:value]      = @issue.id.to_s
              opts[:is_readonly] = true
            end
            opts
          elsif fid.start_with?('ext_')
            # TFC extra field (Sprint, Color, or any other plugin-injected field)
            ef_key = fid.sub(/\Aext_/, '')
            ef = tfc_extra_fields.find { |e| e[:key] == ef_key }
            next unless ef
            { id: "ext_#{ef_key}", name: ef[:label], field_format: ef[:format],
              possible_values: ef[:possible_values], default_value: '',
              value: '', is_required: false, is_readonly: false,
              is_standard: false, is_extra: true, ext_key: ef_key }
          else
            cf_id = fid.sub(/\Acf_/, '').to_i
            next unless cf_id > 0
            cf = applicable_cf_map[cf_id]   # nil if not applicable to this project
            next unless cf
            cf_wf_rule = workflow_rules[cf.id.to_s].to_s
            next if cf_wf_rule == 'hidden'
            # Build possible_values in the format the popup JS expects:
            #   'list' format  → plain strings (JS: o.value=v; o.textContent=v)
            #   'select' format → {value:, label:} objects (JS: pv.value||pv, pv.label||pv)
            pv_format = cf.field_format
            pv = case cf.field_format
                 when 'list'
                   raw = cf.possible_values
                   vals = raw.is_a?(Array) ? raw.map(&:to_s).reject(&:empty?) :
                          raw.to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
                   Rails.logger.warn("[PCU-CF] CF #{cf.id} '#{cf.name}' list raw=#{raw.inspect} vals=#{vals.inspect}")
                   vals
                 when 'enumeration'
                   # Enumeration CFs are validated by enumeration ID, not name.
                   # Use 'select' format so the popup submits the ID as value.
                   pv_format = 'select'
                   cf.respond_to?(:enumerations) ?
                     cf.enumerations.active.map { |e| { value: e.id.to_s, label: e.name.to_s } } :
                     []
                 when 'user'
                   pv_format = 'select'
                   @issue.project.members.includes(:user).map { |m|
                     { value: m.user_id.to_s, label: m.user.name }
                   }
                 when 'version'
                   pv_format = 'select'
                   @issue.project.shared_versions.open.map { |v|
                     { value: v.id.to_s, label: v.name }
                   }
                 else
                   []
                 end
            raw_val = @issue.custom_field_value(cf.id)
            val_str = raw_val.is_a?(Array) ? Array(raw_val).reject(&:empty?).first.to_s : raw_val.to_s
            # Never pre-fill context-dependent fields from parent — the parent's value
            # may not be valid for the child's project/tracker.
            if %w[user version list enumeration].include?(cf.field_format)
              val_str = cf.default_value.to_s
            end
            # For Task trackers, don't inherit Actual date custom fields from parent
            if no_inherit && cf.field_format == 'date' && cf.name.to_s.match?(/actual/i)
              val_str = ''
            end
            { id: cf.id, name: cf.name, field_format: (pv.any? ? pv_format : cf.field_format),
              possible_values: pv,
              default_value: cf.default_value.to_s,
              value: val_str,
              is_required: (cf_wf_rule == 'required' || (cf_wf_rule.empty? && cf.is_required)),
              is_readonly: (cf_wf_rule == 'readonly'),
              is_standard: false }
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
          author_id: User.current.id,
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
            when 'is_private'       then primary_child.is_private       = (value == '1')
            end
          end
        end

        # Apply TFC extra field values (Sprint, Color, etc.) submitted from the popup.
        # Extra fields are plugin-injected attributes — try setting them as Issue attributes
        # (e.g. sprint_id, color) if the model responds to the setter; otherwise skip.
        if params[:ext_fields].is_a?(ActionController::Parameters) || params[:ext_fields].is_a?(Hash)
          params[:ext_fields].each do |key, value|
            if key.to_s == 'watcher_user_ids'
              # value may be a single id string or an array (from multiselect [])
              Array(value).map(&:to_i).select { |uid| uid > 0 }.each do |uid|
                u = User.find_by(id: uid)
                primary_child.add_watcher(u) if u
              end
              next
            end
            next if value.blank?
            setter = :"#{key}="
            primary_child.send(setter, value) if primary_child.respond_to?(setter)
          end
        end

        # Apply all custom field values via custom_field_values= (Redmine's in-memory setter).
        # This is the ONLY correct path — mixing AR .build with the hash setter causes
        # Redmine's save to use whichever wins, leading to stale/invalid values persisting.
        begin
          popup_submitted = (params[:custom_field_values].presence || {})
          merged_cf_values = {}
          # 1. Blank all context-dependent fields (list/enumeration/user/version) to clear
          #    any Redmine-initialised defaults that are invalid for this tracker/project.
          tracker.custom_fields.where(type: 'IssueCustomField').each do |cf|
            next unless %w[list enumeration user version].include?(cf.field_format)
            merged_cf_values[cf.id.to_s] = ''
          end
          # 2. Overlay with whatever the user actually submitted in the popup (wins over blanks).
          popup_submitted.each do |cf_id, value|
            merged_cf_values[cf_id.to_s] = value
          end
          primary_child.custom_field_values = merged_cf_values if merged_cf_values.any?
        rescue => e
          Rails.logger.warn("[PCU] cf values error: #{e.message}")
        end

        # DEBUG — log all custom values about to be saved
        Rails.logger.warn("[PCU-DEBUG] === custom_field_values before save ===")
        primary_child.custom_field_values.each do |cfv|
          Rails.logger.warn("[PCU-DEBUG]   cf_id=#{cfv.custom_field_id} name=#{cfv.custom_field&.name} format=#{cfv.custom_field&.field_format} value=#{cfv.value.inspect}")
        end rescue nil
        Rails.logger.warn("[PCU-DEBUG] === custom_values (AR) before save ===")
        primary_child.custom_values.each do |cv|
          Rails.logger.warn("[PCU-DEBUG]   cf_id=#{cv.custom_field_id} name=#{cv.custom_field&.name} format=#{cv.custom_field&.field_format} value=#{cv.value.inspect}")
        end rescue nil

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
          Rails.logger.warn("[PCU-DEBUG] Save failed: #{primary_child.errors.full_messages.inspect}")
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
