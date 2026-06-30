class CreateNotificationBells < ActiveRecord::Migration[5.2]
  def change
    create_table :notification_bells do |t|
      t.integer  :user_id,        null: false
      t.integer  :journal_id,     null: false
      t.integer  :issue_id,       null: false
      t.integer  :note_index,     null: false, default: 0
      t.string   :issue_subject,  null: false, default: ''
      t.string   :author_name,    null: false, default: ''
      t.boolean  :read,           null: false, default: false
      t.timestamps null: false
    end

    add_index :notification_bells, :user_id
    add_index :notification_bells, [:user_id, :read]
    add_index :notification_bells, :journal_id
  end
end
