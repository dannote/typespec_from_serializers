# frozen_string_literal: true

class TasksController < ApplicationController
  def index
    render json: TaskSerializer.many(Task.all)
  end

  def show
    render json: TaskSerializer.one(Task.find(params[:id]))
  end
end
