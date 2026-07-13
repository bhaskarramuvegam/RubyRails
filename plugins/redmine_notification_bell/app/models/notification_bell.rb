class NotificationBell < ActiveRecord::Base
  belongs_to :user,    optional: true
  belongs_to :journal, optional: true
  belongs_to :issue,   optional: true

  scope :unread,   -> { where(read: false) }
  scope :for_user, ->(user) { where(user_id: user.id) }

  DEFAULT_MAX     = 20
  DEFAULT_PREVIEW = 100

  def self.plugin_enabled?
    Setting.plugin_redmine_notification_bell['plugin_enabled'].to_s == '1'
  rescue
    true
  end

  def self.max_per_user
    val = Setting.plugin_redmine_notification_bell['max_notifications'].to_i
    val.between?(1, 100) ? val : DEFAULT_MAX
  rescue
    DEFAULT_MAX
  end

  def self.preview_length
    val = Setting.plugin_redmine_notification_bell['preview_length'].to_i
    val.between?(20, 300) ? val : DEFAULT_PREVIEW
  rescue
    DEFAULT_PREVIEW
  end

  # Fast path called in the HTTP request cycle.
  # Validates the journal has @mentions, then inserts ONE row into the async
  # queue (~1ms).  The unique index on journal_id silently discards any
  # duplicate enqueue attempts (after_commit + controller hook both fire for
  # the same save; only one job ends up being processed).
  def self.enqueue_for_mentions(journal)
    return unless plugin_enabled?
    return unless journal.notes.present?
    return unless journal.journalized_type == 'Issue'
    return unless journal.notes.match?(/(?<!\S)@[\w.\-]+/)

    NotificationBellQueue.create!(
      journal_id: journal.id,
      status:     NotificationBellQueue::PENDING
    )
    Rails.logger.info "[NotificationBell] Enqueued job for journal #{journal.id}"
  rescue ActiveRecord::RecordNotUnique
    # Duplicate — after_commit and controller hook both fired. Safe to ignore.
  rescue => e
    Rails.logger.error "[NotificationBell] enqueue_for_mentions error: #{e.class}: #{e.message}"
  end

  # Worker path: called by NotificationBellWorker in a background thread,
  # fully decoupled from the HTTP request/response cycle.
  def self.create_for_mentions(journal)
    return unless journal.notes.present?
    return unless journal.journalized_type == 'Issue'

    issue = Issue.find_by(id: journal.journalized_id)
    return unless issue

    logins = journal.notes.scan(/(?<!\S)@([\w.\-]+)/).flatten.uniq
    Rails.logger.info "[NotificationBell] create_for_mentions: journal=#{journal.id} issue=##{issue.id} logins=#{logins.inspect}"
    return if logins.empty?

    note_index = Journal
                   .where(journalized_type: 'Issue', journalized_id: issue.id)
                   .where('created_on < :t OR (created_on = :t AND id <= :id)',
                          t: journal.created_on, id: journal.id)
                   .count

    author_name  = journal.user&.name.to_s
    note_preview = journal.notes.to_s.gsub(/\r?\n/, ' ').squish.truncate(preview_length)
    max_notif    = max_per_user

    logins.each do |login|
      mentioned_user = User.active.find_by(login: login) ||
                       User.active.where('login LIKE ?', "#{login}@%").first
      unless mentioned_user
        Rails.logger.warn "[NotificationBell] No active user for login='#{login}'"
        next
      end

      next if mentioned_user.id == journal.user_id
      next if exists?(user_id: mentioned_user.id, journal_id: journal.id)

      notification = nil
      transaction(requires_new: true) do
        notification = create(
          user_id:       mentioned_user.id,
          journal_id:    journal.id,
          issue_id:      issue.id,
          note_index:    note_index,
          issue_subject: issue.subject.to_s.truncate(120),
          author_name:   author_name,
          note_preview:  note_preview,
          read:          false
        )
      end

      if notification&.persisted?
        Rails.logger.info "[NotificationBell] Created notification #{notification.id} for #{mentioned_user.login}"
        excess = where(user_id: mentioned_user.id)
                   .order(created_at: :desc, id: :desc)
                   .offset(max_notif)
                   .pluck(:id)
        where(id: excess).delete_all if excess.any?
      else
        Rails.logger.error "[NotificationBell] create failed: #{notification&.errors&.full_messages}"
      end
    end
  rescue => e
    Rails.logger.error "[NotificationBell] create_for_mentions error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
  end

  def issue_url
    "/issues/#{issue_id}#note-#{note_index}"
  end

  def as_json(*)
    {
      id:            id,
      read:          read,
      issue_id:      issue_id,
      issue_subject: issue_subject,
      author_name:   author_name,
      note_preview:  note_preview.to_s,
      note_index:    note_index,
      journal_id:    journal_id,
      created_at:    created_at.utc.iso8601,
      url:           issue_url
    }
  end
end
