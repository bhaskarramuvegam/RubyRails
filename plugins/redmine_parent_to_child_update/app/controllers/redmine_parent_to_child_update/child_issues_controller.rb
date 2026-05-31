# Redmine Parent to Child Update - Child Issues Controller
# This controller handles AJAX requests for child issue operations

module RedmineParentToChildUpdate
  class ChildIssuesController < ApplicationController
    before_action :find_issue, only: [:get_trackers, :create_child, :list_children]

    accept_api_auth :create_child

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
        if primary_child.save
          created_children << primary_child
        else
          return render json: { error: primary_child.errors.full_messages.join(', ') }, status: :unprocessable_entity
        end

        # Optionally create Development and Testing tasks under the primary child
        if Setting.plugin_redmine_parent_to_child_update['create_dev_test_tasks'] == '1'
          dev_cat = Category.find_by(name: 'Development', project_id: @issue.project.id) || Category.find_by(name: 'Development')
          test_cat = Category.find_by(name: 'Testing', project_id: @issue.project.id) || Category.find_by(name: 'Testing')

          ['Development', 'Testing'].each do |label|
            begin
              cat = (label == 'Development') ? dev_cat : test_cat
              child = Issue.new(
                project: @issue.project,
                tracker: tracker,
                subject: "#{subject} - #{label}",
                description: description,
                status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : (begin; IssueStatus.find_by(is_default: true); rescue ActiveRecord::StatementInvalid; nil; end) || IssueStatus.first),
                priority: @issue.priority,
                author_id: @issue.author_id,
                parent_id: primary_child.id,
                category_id: (cat && cat.id)
              )
              child.replicate_fields_from_parent(@issue)
              # override category if found
              child.category_id = cat.id if cat
              if child.save
                created_children << child
              else
                Rails.logger.error("Error creating auto #{label} child: #{child.errors.full_messages.join(', ')}")
              end
            rescue => e
              Rails.logger.error("Exception creating auto #{label} child: #{e.message}")
            end
          end
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
          if additional_child.save
            created_children << additional_child
          else
            Rails.logger.error("Error creating additional child issue: #{additional_child.errors.full_messages.join(', ')}")
          end
        end

        render json: {
          children: created_children.map { |c| { id: c.id, subject: c.subject, url: issue_path(c) } }
        }, status: :created
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
