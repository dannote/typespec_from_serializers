# frozen_string_literal: true

# Example showcasing automatic type inference and the 'type' syntax sugar
class TaskSerializer < BaseSerializer
  extend T::Sig

  # SQL schema + enum inference - zero config needed!
  attributes :id, :title, :description, :created_at, :updated_at, :status, :priority

  # Type syntax sugar - simple and clean
  attribute :assignee_name, type: :string
  def assignee_name = task.assignee&.full_name || "Unassigned"

  attribute :overdue?, type: :boolean
  def overdue? = task.due_date && task.due_date < Date.today

  attribute :notes, type: :string, optional: true
  def notes = task.internal_notes

  attribute :external_id, type: "string | int32"
  def external_id = task.external_system_id || task.legacy_id

  # Sorbet auto-infers complex shape types
  attribute :watchers
  sig { returns(T::Array[{id: Integer, email: String}]) }
  def watchers = task.watchers.map { |w| {id: w.id, email: w.email} }
end
