# config/routes.rb

RedmineApp::Application.routes.draw do
  namespace :redmine_parent_to_child_update do
    resources :child_issues, only: [] do
      collection do
        get :get_trackers, path: 'trackers/:issue_id'
        post :create_child, path: 'create/:issue_id'
        get :list_children, path: 'children/:issue_id'
      end
    end
  end
end
