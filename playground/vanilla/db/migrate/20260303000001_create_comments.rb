class CreateComments < ActiveRecord::Migration[6.0]
  def change
    create_table :comments do |t|
      t.text :body, null: false
      t.references :task
      t.timestamps
    end
  end
end
