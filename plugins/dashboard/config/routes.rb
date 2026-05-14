# plugins/dashboard/config/routes.rb

RedmineApp::Application.routes.draw do
  resources :dashboard, only: [:index] do
    collection do
      # Allow both GET and POST for bar_charts
      match :bar_charts, via: [:get, :post] # This will map to /dashboard/bar_charts
      # Allow both GET and POST for pie_charts
      match :pie_charts, via: [:get, :post] # This will map to /dashboard/pie_charts
    end
  end
end
