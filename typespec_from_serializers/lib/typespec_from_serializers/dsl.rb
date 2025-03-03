# frozen_string_literal: true

require "active_support/concern"

# Internal: A DSL to specify types for serializer attributes.
module TypeSpecFromSerializers
  module DSL
    extend ActiveSupport::Concern

    module ClassMethods
      # Override: Capture the name of the model related to the serializer.
      #
      # name - An alias for the internal object in the serializer.
      # model - The name of an ActiveRecord model to infer types from the schema.
      # typespec_from - The name of a TypeScript model to infer types from.
      def object_as(name, model: nil, typespec_from: nil)
        # NOTE: Avoid taking memory for type information that won't be used.
        if Rails.env.development?
          model ||= name.is_a?(Symbol) ? name : try(:_serializer_model_name) || name
          define_singleton_method(:_serializer_model_name) { model }
          define_singleton_method(:_serializer_typespec_from) { typespec_from } if typespec_from
        end

        super(name)
      end

      # Public: Shortcut for typing a serializer attribute.
      #
      # It specifies the type for a serializer method that will be defined
      # immediately after calling this method.
      def type(type, **options)
        attribute type: type, **options
      end

    private

      # Override: Remove unnecessary options in production, types are only
      # used when generating code in development.
      unless Rails.env.development?
        def add_attribute(name, type: nil, optional: nil, **options)
          super(name, **options)
        end
      end
    end
  end
end
