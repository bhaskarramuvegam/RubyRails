class DashboardController < ApplicationController # Assuming your controller is named DashboardController
  unloadable

  # Apply common data fetching and filter application to all relevant actions.
  before_action :fetch_common_data, only: [:index, :pie_charts, :bar_charts]
  before_action :apply_filters,      only: [:index, :pie_charts, :bar_charts]

  # The main dashboard entry point.
  def index
    # Redirect to a default chart view (e.g., pie charts) or render a landing page.
    # For now, let's assume you want to redirect to pie charts if no specific action is taken.
    render :index
  end

  # Action to display only pie charts.
  def pie_charts
    Rails.logger.debug "PIE CHARTS CALLED"

    # For pie charts, we use only the standard parameters from the form,
    # and not custom queries, as per the existing logic.
    @filtered_issues = filter_issues_with_standard_params

    # Prepare pie chart specific data.
    @pie_chart_data = {
      status:    group_counts(@filtered_issues, &:status),
      tracker:   group_counts(@filtered_issues, &:tracker),
      priority:  group_counts(@filtered_issues, &:priority),
      assignee:  group_counts(@filtered_issues) { |i| i.assigned_to&.name || 'Unassigned' },
      project:   group_counts(@filtered_issues) { |i| i.project&.name || 'No Project' }
    }

    # Also prepare raw issue data for the table at the bottom of the pie charts page.
    @raw_issue_data = @filtered_issues.map do |issue|
      {
        id: issue.id,
        project: issue.project.name,
        tracker: issue.tracker.name,
        status: issue.status.name,
        subject: issue.subject,
        assigned_to: issue.assigned_to&.name.presence || 'Unassigned',
        updated_on: issue.updated_on.strftime("%Y-%m-%d %H:%M:%S")
      }
    end

    # Determine if any charts should be shown for the pie chart page
    @show_pie_charts = @pie_chart_data.values.any? { |data_array| data_array.any? }
    Rails.logger.debug "Dashboard Debug: Number of filtered issues for pie charts: #{@filtered_issues.count}"

    render :pie_charts # Render the pie_charts.html.erb view
  end

  # Action to display only bar charts.
  def bar_charts
    Rails.logger.debug "BAR CHARTS CALLED"

    # This will hold the final set of issues after all filtering.
    @filtered_issues = []

    # If a custom query is selected, start with issues from that query.
    if @selected_custom_query_id.present? && @selected_custom_query_id > 0
      @custom_query = @custom_queries.find { |q| q.id == @selected_custom_query_id }

      if @custom_query
        Rails.logger.debug "Dashboard Debug: Custom Query selected: #{@custom_query.name} (ID: #{@selected_custom_query_id})"

        # Apply the custom query's filter. This returns an ActiveRecord::Relation or an Array.
        issues_scope_from_custom_query = apply_custom_query_filter(@custom_query)

        # Now, apply any additional standard filters on top of the custom query results.
        # This unified method handles both ActiveRecord::Relation and Array inputs.
        @filtered_issues = filter_issues_on_scope(issues_scope_from_custom_query)

      else
        Rails.logger.debug "Dashboard Debug: Custom query with ID #{@selected_custom_query_id} not found."
        flash.now[:error] = "The selected custom query was not found. Displaying all issues (if no other filters)."
        # If custom query not found, fall back to showing issues based on standard filters only
        @filtered_issues = filter_issues_on_scope(Issue.all)
      end
    else
      Rails.logger.debug "Dashboard Debug: No custom query selected. Applying standard filters directly."
      # If no custom query is selected, just use the standard filters on all issues.
      @filtered_issues = filter_issues_on_scope(Issue.all)
    end

    # Prepare bar chart specific data only if issues were found
    if @filtered_issues.any?
      # Group and count issues by assignee, then sort in descending order by value
      @assignee_bar_chart_data = group_counts(@filtered_issues) { |i| i.assigned_to&.name || 'Unassigned' }
                                 .sort_by { |item| -item[:value] } # Sort descending by count

      # Group and count issues by project, then sort in descending order by value
      @project_bar_chart_data = group_counts(@filtered_issues) { |i| i.project&.name || 'No Project' }
                                .sort_by { |item| -item[:value] } # Sort descending by count

      # Prepare raw issue data for the table
      @raw_issue_data = @filtered_issues.map do |issue|
        {
          id: issue.id,
          project: issue.project.name,
          tracker: issue.tracker.name,
          status: issue.status.name,
          subject: issue.subject,
          assigned_to: issue.assigned_to&.name.presence || 'Unassigned',
          updated_on: issue.updated_on # Keep as a Time/DateTime object for time_ago_in_words
        }
      end
      @show_bar_charts = true # Set to true to render charts and table
    else
      # If no issues, ensure chart data variables are empty arrays
      @assignee_bar_chart_data = []
      @project_bar_chart_data = []
      @raw_issue_data = []
      @show_bar_charts = false # Explicitly set to false if no issues
      Rails.logger.debug "Dashboard Debug: No issues found after filtering. Not rendering charts."
    end

    Rails.logger.debug "Dashboard Debug: Selected Project IDs: #{@selected_project_ids.inspect}"
    Rails.logger.debug "Dashboard Debug: Selected Status IDs: #{@selected_status_ids.inspect}"
    Rails.logger.debug "Dashboard Debug: Selected Custom Query ID: #{@selected_custom_query_id.inspect}"
    Rails.logger.debug "Dashboard Debug: Number of filtered issues: #{@filtered_issues.count}"
    if @filtered_issues.empty?
      Rails.logger.debug "Dashboard Debug: No issues found. Check your filter parameters and issue data. @show_bar_charts is #{@show_bar_charts}"
    end

    render :bar_charts # Render the bar_charts.html.erb view
  end

  private

  # Fetches common data needed across dashboard views (filters, dropdown options).
  def fetch_common_data
    @projects            = Project.active.visible.order(:name)
    @trackers            = Tracker.order(:position)
    @issue_statuses      = IssueStatus.order(:position)
    @open_statuses       = @issue_statuses.reject(&:is_closed?)
    @closed_statuses     = @issue_statuses.select(&:is_closed?)
    @authors             = User.active.order(:firstname, :lastname)
    @assignees           = User.active.order(:firstname, :lastname)
    @issue_priorities    = IssuePriority.order(:position)
    @issue_categories    = IssueCategory.all.distinct.order(:name)
    @versions            = Version.all.distinct.order(:name)
    @custom_queries      = available_custom_queries # This will now be filtered by name
  end

  # Applies filters based on request parameters.
  # This populates @selected_..._ids variables.
  def apply_filters
    permitted = dashboard_params

    @selected_project_ids          = Array(permitted[:project_ids]).map(&:to_i).reject(&:zero?).uniq
    @selected_tracker_ids          = Array(permitted[:tracker_ids]).map(&:to_i).reject(&:zero?).uniq
    @selected_author_ids           = Array(permitted[:author_ids]).map(&:to_i).reject(&:zero?).uniq
    @selected_assigned_to_ids      = Array(permitted[:assigned_to_ids]).map(&:to_i).reject(&:zero?).uniq
    @selected_priority_ids         = Array(permitted[:priority_ids]).map(&:to_i).reject(&:zero?).uniq
    @selected_category_ids         = Array(permitted[:category_ids]).map(&:to_i).reject(&:zero?).uniq
    @selected_fixed_version_ids    = Array(permitted[:fixed_version_ids]).map(&:to_i).reject(&:zero?).uniq
    @selected_status_ids           = Array(permitted[:status_ids]).map(&:to_i).uniq

    @selected_start_date = permitted[:start_date].presence
    @selected_due_date   = permitted[:due_date].presence
    @selected_custom_query_id = permitted[:custom_query_id].to_i.presence

    # Logic for default open/closed statuses
    if permitted[:default_open_statuses] == "1"
      @selected_status_ids.concat(@open_statuses.map(&:id))
    end
    if permitted[:default_closed_statuses] == "1"
      @selected_status_ids.concat(@closed_statuses.map(&:id))
    end
    @selected_status_ids.uniq!

    # If no specific status is selected, and defaults aren't checked, select all statuses
    unless permitted[:status_ids].present? || permitted[:default_open_statuses] == "1" || permitted[:default_closed_statuses] == "1"
      @selected_status_ids = @issue_statuses.map(&:id)
    end
  end

  # Filters issues based on standard parameters set by apply_filters.
  # This method is specifically for scenarios where only standard filters are applied (e.g., pie charts).
  def filter_issues_with_standard_params
    issues_query = Issue.includes(:project, :status, :tracker, :priority, :author, :assigned_to, :category, :fixed_version)

    issues_query = issues_query.where(project_id: @selected_project_ids) if @selected_project_ids.any?
    issues_query = issues_query.where(tracker_id: @selected_tracker_ids) if @selected_tracker_ids.any?
    issues_query = issues_query.where(status_id: @selected_status_ids) if @selected_status_ids.any?
    issues_query = issues_query.where(author_id: @selected_author_ids) if @selected_author_ids.any?
    issues_query = issues_query.where(assigned_to_id: @selected_assigned_to_ids) if @selected_assigned_to_ids.any?
    issues_query = issues_query.where(priority_id: @selected_priority_ids) if @selected_priority_ids.any?
    issues_query = issues_query.where(category_id: @selected_category_ids) if @selected_category_ids.any?
    issues_query = issues_query.where(fixed_version_id: @selected_fixed_version_ids) if @selected_fixed_version_ids.any?
    issues_query = issues_query.where("start_date >= ?", @selected_start_date) if @selected_start_date.present?
    issues_query = issues_query.where("due_date <= ?", @selected_due_date) if @selected_due_date.present?

    # Apply order and limit here, then convert to array
    issues_query.order(updated_on: :desc).limit(1000).to_a
  end

  # Filters issues based on standard parameters, but takes an initial scope.
  # This is used for bar charts to refine issues from a custom query or all issues.
  def filter_issues_on_scope(initial_scope)
    # If initial_scope is an Array, convert it to an ActiveRecord::Relation based on IDs.
    # This ensures we can consistently apply ActiveRecord query methods.
    issues_query = initial_scope.is_a?(ActiveRecord::Relation) ? initial_scope : Issue.where(id: initial_scope.map(&:id))

    # Eager load associations for performance
    issues_query = issues_query.includes(:project, :status, :tracker, :priority, :author, :assigned_to, :category, :fixed_version)

    # Apply standard filters
    issues_query = issues_query.where(project_id: @selected_project_ids) if @selected_project_ids.any?
    issues_query = issues_query.where(tracker_id: @selected_tracker_ids) if @selected_tracker_ids.any?
    issues_query = issues_query.where(status_id: @selected_status_ids) if @selected_status_ids.any?
    issues_query = issues_query.where(author_id: @selected_author_ids) if @selected_author_ids.any?
    issues_query = issues_query.where(assigned_to_id: @selected_assigned_to_ids) if @selected_assigned_to_ids.any?
    issues_query = issues_query.where(priority_id: @selected_priority_ids) if @selected_priority_ids.any?
    issues_query = issues_query.where(category_id: @selected_category_ids) if @selected_category_ids.any?
    issues_query = issues_query.where(fixed_version_id: @selected_fixed_version_ids) if @selected_fixed_version_ids.any?
    issues_query = issues_query.where("start_date >= ?", @selected_start_date) if @selected_start_date.present?
    issues_query = issues_query.where("due_date <= ?", @selected_due_date) if @selected_due_date.present?

    # Apply order and final limit, then convert to array.
    # The limit of 1000 is applied here as the last step of filtering.
    issues_query.order(updated_on: :desc).limit(1000).to_a
  end


  # Groups and counts issues for chart data.
  # Note: This method no longer sorts by name, as the final sort will be by value in the caller.
  def group_counts(issues, &block)
    return [] if issues.blank?
    issues.group_by(&block)
          .transform_values(&:count)
          .map do |key, count|
            name_string = case
                          when key.nil? then 'Unassigned'
                          when key.respond_to?(:name) then key.name.to_s
                          else key.to_s
                          end
            { name: name_string, value: count }
          end
  end

  # Applies custom query filter.
  # This method specifically calls Redmine's Query#issues and handles its potential return types.
  def apply_custom_query_filter(custom_query)
    begin
      # Redmine's custom_query.issues method is powerful; it might return an ActiveRecord::Relation
      # or, in more complex cases (e.g., with custom field filters not easily translated to SQL),
      # it might return a plain Array after internal filtering.
      issues_scope = custom_query.issues(include_subprojects: true)

      # We do NOT apply limit/to_a here. We just return whatever custom_query.issues gives us.
      # The subsequent `filter_issues_on_scope` will handle the conversion to ActiveRecord::Relation
      # if needed, and apply the final limit and conversion to array.
      issues_scope

    rescue => e
      Rails.logger.error "Error applying custom query filter (ID: #{custom_query.id}): #{e.message}"
      [] # Return an empty array on error
    end
  end

  # Defines permitted parameters for the dashboard form.
  def dashboard_params
    params.permit(
      :start_date,
      :due_date,
      :custom_query_id,
      :default_open_statuses,
      :default_closed_statuses,
      project_ids: [],
      tracker_ids: [],
      author_ids: [],
      assigned_to_ids: [],
      priority_ids: [],
      category_ids: [],
      fixed_version_ids: [],
      status_ids: []
    )
  end

  # Fetches and filters available custom queries.
  def available_custom_queries
    # Read allowed custom query IDs from plugin settings (admin configurable)
    allowed_query_ids = Setting.plugin_dashboard['allowed_query_ids']
    allowed_query_ids = Array(allowed_query_ids).map(&:to_s)

    IssueQuery.visible.sorted.to_a.select do |query|
      allowed_query_ids.include?(query.id.to_s)
    end
  end
end