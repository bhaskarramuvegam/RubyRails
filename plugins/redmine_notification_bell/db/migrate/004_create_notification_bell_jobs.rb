class CreateNotificationBellJobs < ActiveRecord::Migration[5.2]
  def change
    create_table :notification_bell_jobs do |t|
      t.integer  :journal_id,  null: false
      t.string   :status,      null: false, default: 'pending'
      t.integer  :attempts,    null: false, default: 0
      t.text     :last_error
      t.datetime :run_at
      t.timestamps null: false
    end

    # Unique prevents duplicate jobs for the same journal (from both
    # after_commit and controller hooks firing for the same save).
    add_index :notification_bell_jobs, :journal_id, unique: true

    # Worker polls on (status, run_at) — keep this lean.
    add_index :notification_bell_jobs, [:status, :run_at]
  end
end
