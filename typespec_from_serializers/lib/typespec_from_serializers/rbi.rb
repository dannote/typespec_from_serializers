# frozen_string_literal: true

require "rbi"

module TypeSpecFromSerializers
  # Public: Generates Sorbet RBI files for serializers.
  #
  # This generator creates type signatures for serializer class methods
  # (.one, .many, .one_as_hash, .many_as_hash) that can be used by
  # Sorbet for static type checking.
  module RBI
    # Internal: Reusable type builders for common Sorbet types.
    module Types
    module_function

      # T::Hash[Symbol, T.untyped]
      def hash
        @hash ||= ::RBI::Type.generic("T::Hash", [
          ::RBI::Type.simple("Symbol"),
          ::RBI::Type.untyped,
        ])
      end

      # T.nilable(T::Hash[Symbol, T.untyped])
      def optional_hash
        @optional_hash ||= ::RBI::Type.nilable(hash)
      end

      # T::Array[T::Hash[Symbol, T.untyped]]
      def array_of_hashes
        @array_of_hashes ||= ::RBI::Type.generic("T::Array", [hash])
      end

      # T.any(T::Array[ModelType], ActiveRecord::Relation)
      def items_type(model_type)
        ::RBI::Type.any(
          ::RBI::Type.generic("T::Array", [::RBI::Type.simple(model_type)]),
          ::RBI::Type.simple("ActiveRecord::Relation"),
        )
      end
    end

    class << self
      # Public: Generate RBI content for a single serializer.
      #
      # serializer_class - The serializer class to generate RBI for
      #
      # Returns String with RBI content or nil
      def generate_for_serializer(serializer_class)
        model_class = infer_model_class(serializer_class)
        return nil unless model_class

        build_rbi_file(serializer_class, model_class).string
      end

      # Public: Generate RBI files for all serializers.
      #
      # output_dir - Optional output directory (defaults to sorbet/rbi/dsl)
      #
      # Returns Array of file paths that were written
      def generate_for_all_serializers(output_dir: nil)
        output_dir ||= default_output_dir
        output_dir.mkpath unless output_dir.exist?

        formatter = ::RBI::Formatter.new(sort_nodes: true, group_nodes: true)

        TypeSpecFromSerializers.serializers.filter_map do |serializer_class|
          model_class = infer_model_class(serializer_class)
          next unless model_class

          file_name = serializer_class.name.underscore.tr("/", "_")
          file_path = output_dir.join("#{file_name}.rbi")

          file = build_rbi_file(serializer_class, model_class)
          File.write(file_path, formatter.print_file(file))
          file_path
        end
      end

    private

      # Internal: Build RBI file for a serializer.
      #
      # serializer_class - The serializer class
      # model_class - The inferred model class
      #
      # Returns RBI::File
      def build_rbi_file(serializer_class, model_class)
        ::RBI::File.new(strictness: "strong") do |file|
          file << ::RBI::Class.new(serializer_class.name) do |klass|
            build_serializer_methods(klass, model_class.name)
          end
        end
      end

      # Internal: Add all serializer methods to a class.
      #
      # klass - RBI::Class to add methods to
      # model_type - Name of the model class (String)
      #
      # Returns nothing
      def build_serializer_methods(klass, model_type)
        [
          ["one", false],
          ["one_as_hash", false],
          ["many", true],
          ["many_as_hash", true],
        ].each do |method_name, is_array|
          klass << build_method(method_name, model_type, is_array: is_array)
        end
      end

      # Internal: Build a serializer method with signature.
      #
      # method_name - Name of the method (String)
      # model_type - Name of the model class (String)
      # is_array - Boolean indicating if method returns array
      #
      # Returns RBI::Method
      def build_method(method_name, model_type, is_array:)
        # Build signature and method parameters
        sig_params, method_params = if is_array
          [
            [
              ::RBI::SigParam.new("items", Types.items_type(model_type).to_s),
              ::RBI::SigParam.new("options", Types.optional_hash.to_s),
            ],
            [
              ::RBI::ReqParam.new("items"),
              ::RBI::OptParam.new("options", "nil"),
            ],
          ]
        else
          [
            [
              ::RBI::SigParam.new("item", model_type),
              ::RBI::SigParam.new("options", Types.optional_hash.to_s),
            ],
            [
              ::RBI::ReqParam.new("item"),
              ::RBI::OptParam.new("options", "nil"),
            ],
          ]
        end

        # Determine return type
        return_type = is_array ? Types.array_of_hashes.to_s : Types.hash.to_s

        # Create method and add signature
        ::RBI::Method.new(method_name, is_singleton: true, params: method_params).tap do |method|
          method.add_sig(params: sig_params, return_type: return_type)
        end
      end

      # Internal: Get the default output directory for RBI files.
      #
      # Returns Pathname
      def default_output_dir
        TypeSpecFromSerializers.rbi_dir.join("dsl")
      end

      # Internal: Infer the model class for a serializer.
      #
      # serializer_class - The serializer class
      #
      # Returns Class or nil
      def infer_model_class(serializer_class)
        # Try to get from object_as declaration
        if serializer_class.respond_to?(:object_name) && serializer_class.object_name
          model_name = serializer_class.object_name.to_s.camelize
          model_class = model_name.safe_constantize
          return model_class if model_class
        end

        # Try to get from explicit model declaration
        if serializer_class.respond_to?(:model_name) && serializer_class.model_name
          return serializer_class.model_name.safe_constantize
        end

        # Fall back to naming convention using configured name transformer
        inferred_name = TypeSpecFromSerializers.config.name_from_serializer.call(serializer_class.name)
        inferred_name.safe_constantize
      end
    end
  end
end
