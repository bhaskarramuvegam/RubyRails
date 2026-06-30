Rails.application.routes.draw do
  get  '/notification_bells',          to: 'notification_bells#index'
  get  '/notification_bells/count',    to: 'notification_bells#count'
  post '/notification_bells/read_all', to: 'notification_bells#mark_all_read'
  post '/notification_bells/:id/read', to: 'notification_bells#mark_read'
end
