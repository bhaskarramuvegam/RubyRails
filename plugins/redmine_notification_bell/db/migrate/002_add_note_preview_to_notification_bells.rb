class AddNotePreviewToNotificationBells < ActiveRecord::Migration[5.2]
  def change
    add_column :notification_bells, :note_preview, :string, default: '', null: false
  end
end
