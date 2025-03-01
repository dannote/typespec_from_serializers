# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"

# Public: Automatically generates TypeSpec descriptions for Ruby serializers.
module TypeSpecFromSerializers
  DEFAULT_TRANSFORM_KEYS = ->(key) { key.camelize(:lower).chomp("?") }

  # Internal: Extensions that simplify the implementation of the generator.
  module SerializerRefinements
    refine String do
      # Internal: Converts a name such as :user to the User constant.
      def to_model
        classify.safe_constantize
      end
    end

    refine Symbol do
      def safe_constantize
        to_s.classify.safe_constantize
      end

      def to_model
        to_s.to_model
      end
    end

    refine Class do
      # Internal: Name of the TypeSpec model.
      def tsp_name
        TypeSpecFromSerializers.config.name_from_serializer.call(name).tr_s(":", "")
      end

      # Internal: The base name of the TypeSpec file to be written.
      def tsp_filename
        TypeSpecFromSerializers.config.name_from_serializer.call(name).gsub("::", "/")
      end

      # Internal: If the serializer was defined inside a file.
      def inline_serializer?
        name.include?("Serializer::")
      end

      # Internal: The TypeSpec properties of the serialzeir model.
      def tsp_properties
        @tsp_properties ||= begin
          model_class = _serializer_model_name&.to_model
          model_columns = model_class.try(:columns_hash) || {}
          model_enums = model_class.try(:defined_enums) || {}
          typespec_from = try(:_serializer_typespec_from)

          prepare_attributes(
            sort_by: TypeSpecFromSerializers.config.sort_properties_by,
            transform_keys: TypeSpecFromSerializers.config.transform_keys || try(:_transform_keys) || DEFAULT_TRANSFORM_KEYS,
          )
            .flat_map { |key, options|
              if options[:association] == :flat
                options.fetch(:serializer).tsp_properties
              else
                Property.new(
                  name: key,
                  type: options[:serializer] || options[:type],
                  optional: options[:optional] || options.key?(:if),
                  multi: options[:association] == :many,
                  column_name: options.fetch(:value_from),
                ).tap do |property|
                  property.infer_typespec_from(model_columns, model_enums, typespec_from)
                end
              end
            }
        end
      end

      # Internal: A first pass of gathering types for the serializer attributes.
      def tsp_model
        @tsp_model ||= Interface.new(
          name: tsp_name,
          filename: tsp_filename,
          properties: tsp_properties,
        )
      end
    end
  end

  # Internal: The configuration for TypeSpec generation.
  Config = Struct.new(
    :base_serializers,
    :serializers_dirs,
    :output_dir,
    :custom_typespec_dir,
    :name_from_serializer,
    :global_types,
    :sort_properties_by,
    :sql_to_typespec_type_mapping,
    :skip_serializer_if,
    :transform_keys,
    :namespace,
    keyword_init: true,
  ) do
    def relative_custom_typespec_dir
      @relative_custom_typespec_dir ||= (custom_typespec_dir || output_dir.parent).relative_path_from(output_dir)
    end

    def unknown_type
      :unknown
    end
  end

  # Internal: Information to generate a TypeSpec model for a serializer.
  Interface = Struct.new(
    :name,
    :filename,
    :properties,
    keyword_init: true,
  ) do
    using SerializerRefinements

    def inspect
      to_h.inspect
    end

    # Internal: Returns a list of imports for types used in this model.
    def used_imports
      association_serializers, attribute_types = properties.map(&:type).compact.uniq
        .partition { |type| type.respond_to?(:tsp_model) }

      serializer_type_imports = association_serializers.map(&:tsp_model)
        .map { |type| [type.name, relative_path(type.pathname, pathname)] }

      custom_type_imports = attribute_types
        .flat_map { |type| extract_typespec_types(type.to_s) }
        .uniq
        .reject { |type| global_type?(type) }
        .map { |type|
          type_path = TypeSpecFromSerializers.config.relative_custom_typespec_dir.join(type)
          [type, relative_path(type_path, pathname)]
        }

      (custom_type_imports + serializer_type_imports)
        .map { |model, filename| %(import "#{filename}.tsp";\n) }
    end

    def as_typespec
      indent = TypeSpecFromSerializers.config.namespace ? 2 : 1
      <<~TSP.gsub(/\n$/, "")
        model #{name} {
        #{"  " * indent}#{properties.index_by(&:name).values.map(&:as_typespec).join("\n#{"  " * indent}")}
        #{"  " * (indent - 1)}}
      TSP
    end

  protected

    def pathname
      @pathname ||= Pathname.new(filename)
    end

    # Internal: Calculates a relative path that can be used in an import.
    def relative_path(target_path, importer_path)
      path = target_path.relative_path_from(importer_path.parent).to_s
      path.start_with?(".") ? path : "./#{path}"
    end

    # Internal: Extracts any types inside generics or array types.
    def extract_typespec_types(type)
      type.split(".").first
    end

    # NOTE: Treat uppercase names as custom types.
    # Lowercase names would be native types, such as :string and :boolean.
    def global_type?(type)
      type[0] == type[0].downcase || TypeSpecFromSerializers.config.global_types.include?(type)
    end
  end

  # Internal: The type metadata for a serializer attribute.
  Property = Struct.new(
    :name,
    :type,
    :optional,
    :multi,
    :column_name,
    keyword_init: true,
  ) do
    using SerializerRefinements

    def inspect
      to_h.inspect
    end

    # Internal: Infers the property's type by checking a corresponding SQL
    # column, or falling back to a TypeSpec model if provided.
    def infer_typespec_from(columns_hash, defined_enums, tsp_model)
      if type
        type
      elsif (enum = defined_enums[column_name.to_s])
        self.type = enum.keys.map(&:inspect).join(" | ")
      elsif (column = columns_hash[column_name.to_s])
        self.multi = true if column.try(:array)
        self.optional = true if column.null && !column.default
        self.type = TypeSpecFromSerializers.config.sql_to_typespec_type_mapping[column.type]
      elsif tsp_model
        self.type = "#{tsp_model}.#{name}::type"
      end
    end

    def as_typespec
      type_str = if type.respond_to?(:tsp_name)
        type.tsp_name
      else
        type || TypeSpecFromSerializers.config.unknown_type
      end

      "#{name}#{"?" if optional}: #{type_str}#{"[]" if multi};"
    end
  end

  # Internal: Structure to keep track of changed files.
  class Changes
    def initialize(dirs)
      @added = Set.new
      @removed = Set.new
      @modified = Set.new
      track_changes(dirs)
    end

    def updated?
      @modified.any? || @added.any? || @removed.any?
    end

    def any_removed?
      @removed.any?
    end

    def modified_files
      @modified
    end

    def only_modified?
      @added.empty? && @removed.empty?
    end

    def clear
      @added.clear
      @removed.clear
      @modified.clear
    end

  private

    def track_changes(dirs)
      Listen.to(*dirs, only: %r{.rb$}) do |modified, added, removed|
        modified.each { |file| @modified.add(file) }
        added.each { |file| @added.add(file) }
        removed.each { |file| @removed.add(file) }
      end.start
    end
  end

  class << self
    using SerializerRefinements

    attr_reader :force_generation

    # Public: Configuration of the code generator.
    def config
      (@config ||= default_config(root)).tap do |config|
        yield(config) if block_given?
      end
    end

    # Public: Generates code for all serializers in the app.
    def generate(force: ENV["SERIALIZER_TYPESPEC_FORCE"])
      @force_generation = force
      config.output_dir.rmtree if force && config.output_dir.exist?

      if config.namespace
        load_serializers(all_serializer_files) if force
      else
        generate_index_file
      end

      loaded_serializers.each do |serializer|
        generate_model_for(serializer)
      end
    end

    def generate_changed
      if changes.updated?
        config.output_dir.rmtree if changes.any_removed?
        load_serializers(changes.modified_files)
        generate
        changes.clear
      end
    end

    # Internal: Defines a TypeSpec model for the serializer.
    def generate_model_for(serializer)
      model = serializer.tsp_model

      write_if_changed(filename: model.filename, cache_key: model.inspect, extension: "tsp") {
        serializer_model_content(model)
      }
    end

    # Internal: Allows to import all serializer types from a single file.
    def generate_index_file
      cache_key = all_serializer_files.map { |file| file.delete_prefix(root.to_s) }.join
      write_if_changed(filename: "index", cache_key: cache_key) {
        load_serializers(all_serializer_files)
        serializers_index_content(loaded_serializers)
      }
    end

    # Internal: Checks if it should avoid generating an model.
    def skip_serializer?(serializer)
      serializer.name.in?(config.base_serializers) ||
        config.skip_serializer_if.call(serializer)
    end

    # Internal: Returns an object compatible with FileUpdateChecker.
    def track_changes
      changes
    end

  private

    def root
      defined?(Rails) ? Rails.root : Pathname.new(Dir.pwd)
    end

    def changes
      @changes ||= Changes.new(config.serializers_dirs)
    end

    def all_serializer_files
      config.serializers_dirs.flat_map { |dir| Dir["#{dir}/**/*.rb"] }.sort
    end

    def load_serializers(files)
      files.each { |file| require file }
    end

    def loaded_serializers
      config.base_serializers.map(&:constantize)
        .flat_map(&:descendants)
        .uniq
        .sort_by(&:name)
        .reject { |s| skip_serializer?(s) }
    rescue NameError
      raise ArgumentError, "Please ensure all your serializers extend BaseSerializer, or configure `config.base_serializers`."
    end

    def default_config(root)
      Config.new(
        # The base serializers that all other serializers extend.
        base_serializers: ["BaseSerializer"],

        # The dirs where the serializer files are located.
        serializers_dirs: [root.join("app/serializers").to_s],

        # The dir where model files are placed.
        output_dir: root.join(defined?(ViteRuby) ? ViteRuby.config.source_code_dir : "app/frontend").join("typespec/serializers"),

        # Remove the serializer suffix from the class name.
        name_from_serializer: ->(name) {
          name.split("::").map { |n| n.delete_suffix("Serializer") }.join("::")
        },

        # Types that don't need to be imported in TypeSpec.
        global_types: [
          "Array",
          "Record",
          "Date",
        ].to_set,

        # Allows to choose a different sort order, alphabetical by default.
        sort_properties_by: :name,

        # Allows to avoid generating a serializer.
        skip_serializer_if: ->(serializer) { false },

        # Maps SQL column types to TypeSpec native and custom types.
        sql_to_typespec_type_mapping: {
          boolean: :boolean,
          date: :plainDate,
          datetime: :utcDateTime,
          timestamp: :utcDateTime,
          timestamptz: :offsetDateTime,
          time: :plainTime,
          decimal: :decimal128,
          numeric: :decimal128,
          integer: :int32,
          bigint: :int64,
          smallint: :int16,
          tinyint: :int8,
          float: :float32,
          double: :float64,
          real: :float32,
          string: :string,
          text: :string,
          citext: :string,
          binary: :bytes,
          blob: :bytes,
          json: "Record<string, unknown>",
          jsonb: "Record<string, unknown>",
          uuid: :string,
        },

        # Allows to transform keys, useful when converting objects client-side.
        transform_keys: nil,

        # Allows scoping typespec definitions to a namespace
        namespace: nil,
      )
    end

    # Internal: Writes if the file does not exist or the cache key has changed.
    # The cache strategy consists of a comment on the first line of the file.
    #
    # Yields to receive the rendered file content when it needs to.
    def write_if_changed(filename:, cache_key:, extension: "tsp")
      filename = config.output_dir.join("#{filename}.#{extension}")
      FileUtils.mkdir_p(filename.dirname)
      cache_key_comment = "// TypeSpecFromSerializers CacheKey #{Digest::MD5.hexdigest(cache_key)}\n"
      File.open(filename, "a+") { |file|
        if stale?(file, cache_key_comment)
          file.truncate(0)
          file.write(cache_key_comment)
          file.write(yield)
        end
      }
    end

    def serializers_index_content(serializers)
      <<~TSP
        //
        // DO NOT MODIFY: This file was automatically generated by TypeSpecFromSerializers.
        #{serializers.reject(&:inline_serializer?).map { |s|
          %(import "./#{s.tsp_filename}.tsp";)
        }.join("\n")}
      TSP
    end

    def serializer_model_content(model)
      config.namespace ? declaration_model_definition(model) : standard_model_definition(model)
    end

    def standard_model_definition(model)
      <<~TSP
        //
        // DO NOT MODIFY: This file was automatically generated by TypeSpecFromSerializers.
        #{model.used_imports.join}
        #{model.as_typespec}
      TSP
    end

    def declaration_model_definition(model)
      <<~TSP
        //
        // DO NOT MODIFY: This file was automatically generated by TypeSpecFromSerializers.
        #{model.used_imports.empty? ? "export {}\n" : model.used_imports.join}
        namespace #{config.namespace} {
          #{model.as_typespec}
        }
      TSP
    end

    # Internal: Returns true if the cache key has changed since the last codegen.
    def stale?(file, cache_key_comment)
      @force_generation || file.gets != cache_key_comment
    end
  end
end
