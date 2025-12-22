if Rails.env.development? && defined?(TypeSpecFromSerializers)
  TypeSpecFromSerializers.config do |config|
    config.sql_to_typespec_type_mapping.default = :any
  end
end
