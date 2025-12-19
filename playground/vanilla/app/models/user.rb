# frozen_string_literal: true

class User < ApplicationRecord
  has_many :assigned_tasks, class_name: "Task", foreign_key: :assignee_id
  has_many :watched_tasks, class_name: "Task", foreign_key: :watcher_id
end
