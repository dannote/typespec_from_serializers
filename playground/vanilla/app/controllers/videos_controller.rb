class VideosController < ApplicationController
  # List all video clips ordered by creation date.
  def index
    render_page videos: VideoWithSongSerializer.many(VideoClip.order(:created_at))
  end

  # Get a single video clip by ID.
  def show
    render_page video: VideoWithSongSerializer.one(VideoClip.find(params[:id]))
  end
end
