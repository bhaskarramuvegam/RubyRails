# Tracker Fields Configuration - Controller
#
# Serves the per-project tracker/custom-field table on demand for the
# plugin's admin settings page. This exists purely to avoid rendering
# every project's full tracker x custom-field matrix on a single page
# load - some trackers here have 50-80+ custom fields, and with many
# projects that becomes a page too large for the browser to parse.
class TrackerFieldsConfigurationController < ApplicationController
  before_action :require_admin_user
  before_action :find_project, only: [:project_fields, :project_hidden_fields]
  before_action :find_projects, only: [:bulk_fields, :bulk_hidden_fields]

  def project_fields
    render partial: 'tracker_fields_configuration/project_fields', locals: { project: @project }
  end

  # Independent of project_fields above - serves the hide/unhide table for
  # the same project, not the field-promotion table.
  def project_hidden_fields
    render partial: 'tracker_fields_configuration/project_hidden_fields', locals: { project: @project }
  end

  # Bulk multi-project panel for field promotion: the union of trackers
  # enabled on any of the given projects, so an admin can configure once
  # and apply it to every checked project (parent + cascaded sub-projects)
  # at once. Rendered with data attributes only, no name= attributes - the
  # settings page's JS mirrors the visible selections into real form
  # inputs per checked project, since which projects are "checked" can
  # change without another request.
  def bulk_fields
    trackers = TrackerFieldsConfiguration.trackers_for_projects(@project_ids)
    render partial: 'tracker_fields_configuration/bulk_fields',
           locals: { project_ids: @project_ids, trackers: trackers }
  end

  # Same idea as bulk_fields above, for the hide/unhide feature.
  def bulk_hidden_fields
    trackers = TrackerFieldsConfiguration.trackers_for_projects(@project_ids)
    render partial: 'tracker_fields_configuration/bulk_hidden_fields',
           locals: { project_ids: @project_ids, trackers: trackers }
  end

  private

  def require_admin_user
    render_403 unless User.current.admin?
  end

  def find_project
    @project = Project.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_projects
    @project_ids = Array(params[:project_ids]).map(&:to_i).select { |id| id > 0 }.uniq
  end
end
