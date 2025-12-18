class Composer < ApplicationRecord
  extend T::Sig

  has_many :songs
  has_many :video_clips, through: :songs

  sig { returns(String) }
  def name
    [first_name, last_name].compact.join(" ")
  end

  sig { returns(T.nilable(String)) }
  def bio
    "Composer from the classical era"
  end
end
