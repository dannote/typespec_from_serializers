class BaseSerializer < Oj::Serializer
  include TypeSpecFromSerializers::DSL::Serializer
end
