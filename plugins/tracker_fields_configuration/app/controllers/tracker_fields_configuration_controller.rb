# Tracker Fields Configuration - Controller
#
# Serves the per-project tracker/custom-field table on demand for the
# plugin's admin settings page. This exists purely to avoid rendering
# every project's full tracker x custom-field matrix on a single page
# load - some trackers here have 50-80+ custom fields, and with many
# projects that becomes a page too large for the browser to parse.
class TrackerFieldsConfigurationController < ApplicationController
  before_action :require_admin_user
  before_action :find_project

  def project_fields
    render partial: 'tracker_fields_configuration/project_fields', locals: { project: @project }
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
end
