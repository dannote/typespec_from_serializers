if Rails.env.development? && defined?(TypesFromSerializers)
  TypesFromSerializers.config do |config|
    config.sql_to_typescript_type_mapping.default = :any
  end
end
