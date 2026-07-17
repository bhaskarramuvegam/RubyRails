Rails.application.routes.draw do
  get  '/notification_bells',               to: 'notification_bells#index'
  get  '/notification_bells/count',         to: 'notification_bells#count'
  get  '/notification_bells/mention_users', to: 'notification_bells#mention_users'
  post '/notification_bells/read_all',      to: 'notification_bells#mark_all_read'
  post '/notification_bells/:id/read',      to: 'notification_bells#mark_read'
end
