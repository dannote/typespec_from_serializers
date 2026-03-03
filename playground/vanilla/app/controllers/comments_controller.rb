# frozen_string_literal: true

class CommentsController < ApplicationController
  def index
    render json: []
  end

  def create
    render json: {}
  end
end
