# frozen_string_literal: true

class Task < ApplicationRecord
  # Enums are automatically inferred and converted to TypeSpec union types
  enum status: {
    pending: 0,
    in_progress: 1,
    completed: 2,
    cancelled: 3
  }

  enum priority: {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }

  belongs_to :assignee, class_name: "User", optional: true
  has_many :watchers, class_name: "User"
end
