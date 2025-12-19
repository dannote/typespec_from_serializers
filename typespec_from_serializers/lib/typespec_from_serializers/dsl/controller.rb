# frozen_string_literal: true

require "active_support/concern"

module TypeSpecFromSerializers
  module DSL
    # DSL for Rails controllers to declare parameter types
    module Controller
      extend ActiveSupport::Concern

      module ClassMethods
        # DSL for declaring method return types (same as serializer DSL)
        # Usage:
        #   type id: Integer, title: String
        #   def video_params
        #     # ...
        #   end
        def type(type_definition)
          @_pending_return_type = type_definition
        end

        # Internal: Captures pending type declaration when method is defined
        def method_added(method_name)
          super
          if (pending_type = @_pending_return_type)
            return_type_registry[method_name] = pending_type
            @_pending_return_type = nil
          end
        end

        # Internal: Registry storing method return type declarations
        def return_type_registry
          @return_type_registry ||= {}
        end

        # Public: Retrieve declared return type for a method
        def type_for_method(method_name)
          return_type_registry[method_name.to_sym]
        end
      end
    end
  end
end
