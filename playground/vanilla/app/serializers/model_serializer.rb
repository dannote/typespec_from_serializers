class ModelSerializer < BaseSerializer
  object_as :model, typespec_from: :AnyModel

  attributes(
    :id,
    :title,
  )
end
