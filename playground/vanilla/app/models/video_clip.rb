class VideoClip < ApplicationRecord
  extend T::Sig

  belongs_to :song
  has_one :composer, through: :song

  sig { returns(T.nilable(String)) }
  def youtube_url
    "https://www.youtube.com/watch?v=#{youtube_id}" if youtube_id
  end

  sig { returns(T::Array[String]) }
  def tags
    ["music", "video", "classical"]
  end
end
