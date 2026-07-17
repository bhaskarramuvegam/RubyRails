class NotificationBellsController < ApplicationController
  before_action :require_login

  rescue_from StandardError do |e|
    Rails.logger.error "[NotificationBell] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: { error: 'Notification service unavailable', detail: e.message }, status: :internal_server_error
  end

  def index
    notifications = NotificationBell
                      .for_user(User.current)
                      .includes(:issue)
                      .order(created_at: :desc)
                      .limit(NotificationBell.max_per_user)

    render json: {
      notifications: notifications.map(&:as_json),
      unread_count:  NotificationBell.for_user(User.current).unread.count
    }
  end

  def count
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma']        = 'no-cache'
    response.headers['Expires']       = '0'
    render json: { unread_count: NotificationBell.for_user(User.current).unread.count }
  end

  def mark_read
    notification = NotificationBell.find_by(id: params[:id], user_id: User.current.id)
    if notification
      notification.update_column(:read, true)
      render json: { success: true, unread_count: NotificationBell.for_user(User.current).unread.count }
    else
      render json: { success: false }, status: :not_found
    end
  end

  def mark_all_read
    NotificationBell.for_user(User.current).unread.update_all(read: true)
    render json: { success: true, unread_count: 0 }
  end

  # Returns up to 10 active users whose login starts with the query string.
  # Used by the @mention autocomplete in note textareas.
  # Logins in Redmine are full email addresses (e.g. balaji.j@vegam.co).
  # We match on the local part (before @) and return only the local part
  # as the mention token, since that is what create_for_mentions expects.
  def mention_users
    q = params[:q].to_s.strip.downcase
    return render(json: []) if q.length < 1

    users = User.active
                .where('login LIKE ?', "#{q}%")
                .order(:login)
                .limit(10)

    render json: users.map { |u|
      local = u.login.split('@').first
      { login: local, name: u.name, label: "#{u.name}  @#{local}" }
    }
  end
end
