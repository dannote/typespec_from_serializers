class BaseSerializer < Oj::Serializer
  include TypeSpecFromSerializers::DSL
end
