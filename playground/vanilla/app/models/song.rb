class Song < ApplicationRecord
  extend T::Sig

  belongs_to :composer
  has_many :video_clips

  enum genre: {fingerstyle: "fingerstyle", rock: "rock", classical: "classical"}
  enum tempo: %w[slow medium fast]

  sig { returns(String) }
  def display_name
    "#{title} by #{composer.name}"
  end

  sig { returns(Integer) }
  def duration_minutes
    3
  end
end
