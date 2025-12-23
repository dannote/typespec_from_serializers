class SongsController < ApplicationController
  def index
    render_page songs: SongSerializer.many(Song.order(:title))
  end

  def show
    render_page song: SongWithVideosSerializer.one(Song.find(params[:id]))
  end

  # Search songs with filters (demonstrates transitive params extraction)
  def search
    songs = Song.order(:title)
    songs = apply_filters(songs)
    render_page songs: SongSerializer.many(songs)
  end

  private

  def apply_filters(songs)
    songs = songs.where("title LIKE ?", "%#{search_params[:query]}%") if search_params[:query].present?
    songs = songs.where(composer_id: search_params[:composer_id]) if search_params[:composer_id].present?
    songs
  end

  type query: String, composer_id: Integer
  def search_params
    params.permit(:query, :composer_id)
  end
end
