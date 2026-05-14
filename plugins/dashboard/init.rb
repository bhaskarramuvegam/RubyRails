Redmine::Plugin.register :dashboard do
  name 'Dashboard plugin'
  author 'Siddhant'
  description 'This is a plugin for Redmine'
  version '0.0.1'
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'

  # Add settings to enable/disable the plugin and configure allowed custom queries
  settings :default => {
    'enabled' => '1',
    'allowed_query_ids' => []
  }, :partial => 'settings/dashboard_settings'

  # Only show menu if plugin is enabled in settings
  menu :top_menu, :dashboard, { :controller => 'dashboard', :action => 'index'},
    :caption => 'Dashboard',
    :if => Proc.new {
      User.current.logged? &&
      (Setting.plugin_dashboard['enabled'].to_s == '1')
    }
end
