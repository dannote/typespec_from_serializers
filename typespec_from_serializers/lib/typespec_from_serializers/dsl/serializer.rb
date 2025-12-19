# frozen_string_literal: true

require "active_support/concern"

# Internal: A DSL to specify types for serializer attributes.
module TypeSpecFromSerializers
  module DSL
    module Serializer
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

        # Public: Declare type for an attribute or method return value.
        #
        # type    - Symbol for attribute type, or Class/Sorbet type for method return
        # options - Additional options passed to `attribute` when type is a Symbol
        #
        # Examples
        #
        #   type :string           # Attribute type
        #   type String            # Method return type
        #   type T.nilable(String) # Sorbet type
        #
        def type(type, **options)
          type.is_a?(Symbol) ? attribute(type: type, **options) : @_pending_return_type = type
        end

        # Internal: Captures pending type declaration when method is defined.
        def method_added(method_name)
          super
          if (pending_type = @_pending_return_type)
            return_type_registry[method_name] = pending_type
            @_pending_return_type = nil
          end
        end

        # Internal: Registry storing method return type declarations.
        def return_type_registry
          @return_type_registry ||= {}
        end

        # Public: Retrieve declared return type for a method.
        def type_for_method(method_name)
          return_type_registry[method_name.to_sym]
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
end
