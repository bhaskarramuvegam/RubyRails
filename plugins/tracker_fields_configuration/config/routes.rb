# config/routes.rb

RedmineApp::Application.routes.draw do
  get 'tracker_fields_configuration/project_fields',
      to: 'tracker_fields_configuration#project_fields',
      as: 'tracker_fields_configuration_project_fields'
end
