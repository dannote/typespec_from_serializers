class SongSerializer < BaseSerializer
  attributes(
    :id,
    :title,
    :genre,
    :tempo,
    :display_name,
    :duration_minutes,
  )

  has_one :composer, serializer: ComposerSerializer
end
