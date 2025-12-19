# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[6.0]
  def change
    create_table :tasks do |t|
      t.string :title, null: false
      t.text :description
      t.integer :status, default: 0, null: false
      t.integer :priority, default: 0, null: false
      t.date :due_date
      t.text :internal_notes
      t.string :external_system_id
      t.integer :legacy_id
      t.references :assignee, foreign_key: {to_table: :users}

      t.timestamps
    end
  end
end
