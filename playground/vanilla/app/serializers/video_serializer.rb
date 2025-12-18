class VideoSerializer < BaseSerializer
  object_as :video_clip

  attributes(
    :id,
    :created_at,
    :title,
    :youtube_id,
    :youtube_url,
    :tags,
  )

  attribute :untyped_field_example do
  end
end
