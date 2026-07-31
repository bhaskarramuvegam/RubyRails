# config/routes.rb

RedmineApp::Application.routes.draw do
  get 'tracker_fields_configuration/project_fields',
      to: 'tracker_fields_configuration#project_fields',
      as: 'tracker_fields_configuration_project_fields'

  get 'tracker_fields_configuration/project_hidden_fields',
      to: 'tracker_fields_configuration#project_hidden_fields',
      as: 'tracker_fields_configuration_project_hidden_fields'
end
