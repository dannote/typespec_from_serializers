# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"

# Public: Automatically generates TypeSpec descriptions for Ruby serializers and Rails routes.
module TypeSpecFromSerializers
  DEFAULT_TRANSFORM_KEYS = ->(key) { key.camelize(:lower).chomp("?") }

  # TypeSpec language keywords that are always problematic
  TYPESPEC_LANGUAGE_KEYWORDS = %w[
    using extends is import model scalar enum union interface
    namespace op alias true false null
  ].to_set.freeze

  # TypeSpec Reflection types that conflict only at global scope
  # When using a namespace, these names are safe (e.g., MyAPI.Model is OK)
  TYPESPEC_REFLECTION_TYPES = %w[
    Model Scalar Enum Union Interface Operation Namespace
  ].to_set.freeze

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
        transformed = TypeSpecFromSerializers.config.name_from_serializer.call(name).tr_s(":", "")

        # Only check for reflection type conflicts if no namespace is configured
        # When using a namespace, Model becomes MyNamespace.Model which doesn't conflict
        if TypeSpecFromSerializers.config.namespace.nil? && TYPESPEC_REFLECTION_TYPES.include?(transformed)
          warn "Warning: TypeSpec model name '#{transformed}' conflicts with reserved keyword. Renaming to '#{transformed}_'. Use config.namespace to avoid this."
          "#{transformed}_"
        else
          transformed
        end
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
                  property.infer_typespec_from(model_columns, model_enums, typespec_from, self, model_class)
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
    :sorbet_to_typespec_type_mapping,
    :action_to_operation_mapping,
    :skip_serializer_if,
    :transform_keys,
    :namespace,
    :export_if,
    keyword_init: true,
  ) do
    def relative_custom_typespec_dir
      @relative_custom_typespec_dir ||= (custom_typespec_dir || output_dir.parent).relative_path_from(output_dir.join("models"))
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
        .flat_map { |type| type.to_s.split(".").first }
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
    def infer_typespec_from(columns_hash, defined_enums, tsp_model, serializer_class = nil, model_class = nil)
      # Priority 1: Explicit type (already set via DSL)
      if type
        return type
      end

      # Priority 2: Sorbet method signature on serializer (if available)
      if serializer_class && Sorbet.available?
        sorbet_info = Sorbet.extract_type_for(serializer_class, column_name)
        if sorbet_info
          self.type = sorbet_info[:typespec_type]
          self.optional = true if sorbet_info[:nilable]
          self.multi = true if sorbet_info[:array]
          return type
        end
      end

      # Priority 2b: Sorbet method signature on model (if available)
      if model_class && Sorbet.available?
        sorbet_info = Sorbet.extract_type_for(model_class, column_name)
        if sorbet_info
          self.type = sorbet_info[:typespec_type]
          self.optional = true if sorbet_info[:nilable]
          self.multi = true if sorbet_info[:array]
          return type
        end
      end

      # Priority 3: ActiveRecord enums
      if (enum = defined_enums[column_name.to_s])
        self.type = enum.keys.map(&:inspect).join(" | ")
        return type
      end

      # Priority 4: SQL schema columns
      if (column = columns_hash[column_name.to_s])
        self.multi = true if column.try(:array)
        self.optional = true if column.null && !column.default
        self.type = TypeSpecFromSerializers.config.sql_to_typespec_type_mapping[column.type]
        return type
      end

      # Priority 5: TypeSpec model fallback
      if tsp_model
        self.type = "#{tsp_model}.#{name}::type"
      end

      type
    end

    def as_typespec
      type_str = if type.respond_to?(:tsp_name)
        type.tsp_name
      else
        type || TypeSpecFromSerializers.config.unknown_type
      end

      escaped_name = escape_field_name(name)
      "#{escaped_name}#{"?" if optional}: #{type_str}#{"[]" if multi};"
    end

  private

    def escape_field_name(field_name)
      # Escape field names that conflict with TypeSpec keywords using backticks
      all_keywords = TYPESPEC_LANGUAGE_KEYWORDS +
        TYPESPEC_REFLECTION_TYPES.map(&:downcase)

      if all_keywords.include?(field_name)
        "`#{field_name}`"
      else
        field_name
      end
    end
  end

  # Internal: Represents a TypeSpec resource interface
  Resource = Struct.new(:name, :path, :operations, keyword_init: true) do
    def as_typespec
      <<~TSP
        #{"  " * 1}@route("#{path}")
        #{"  " * 1}interface #{name} {
        #{"  " * 1}#{operations.map(&:as_typespec).join("\n  ")}
        #{"  " * 1}}
      TSP
    end
  end

  # Internal: Represents a TypeSpec operation within a resource
  Operation = Struct.new(:method, :action, :path_params, :response_type, keyword_init: true) do
    def as_typespec
      method_map = {
        "GET" => "get",
        "POST" => "post",
        "PUT" => "put",
        "PATCH" => "patch",
        "DELETE" => "delete",
      }
      tsp_method = method_map[method] || method.downcase
      operation_name = TypeSpecFromSerializers.config.action_to_operation_mapping[action] || action
      params = params_typespec
      params_str = params.empty? ? "()" : "(#{params})"

      "#{"  " * 1}@#{tsp_method} #{operation_name}#{params_str}: #{response_type.gsub("::", "")};"
    end

    def params_typespec
      params = []
      params += path_params.map { |param| "@path #{param}: string" } if path_params.any?
      params << "@body body: #{response_type.gsub("::", "")}" if method.in?(%w[POST PUT PATCH])
      params.join(", ")
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

      generate_routes

      serializers = loaded_serializers
      serializers.each do |serializer|
        generate_model_for(serializer)
      end

      serializers
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

      write_if_changed(filename: "models/#{model.filename}", cache_key: model.inspect, extension: "tsp") {
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

    # Internal: Generates TypeSpec routes from Rails routes
    def generate_routes
      return unless defined?(Rails) && Rails.application

      routes = collect_rails_routes
      cache_key = routes.map { |r| r.operations.map { |op| "#{op.method}#{r.path}#{op.action}" }.join }.join
      write_if_changed(filename: "routes", cache_key: cache_key) {
        routes_content(routes)
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

    # Public: Returns all loaded serializers.
    #
    # Returns Array of serializer classes.
    def serializers
      loaded_serializers
    end

    # Public: Returns the application root path.
    #
    # Returns Pathname
    def root
      defined?(Rails) ? Rails.root : Pathname.new(Dir.pwd)
    end

    # Public: Returns the RBI base directory path.
    #
    # Returns Pathname
    def rbi_dir
      root.join("sorbet/rbi")
    end

  private

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
        .reject { |s| s.name.nil? } # Filter out anonymous classes
        .sort_by(&:name)
        .reject { |s| skip_serializer?(s) }
    rescue NameError
      raise ArgumentError, "Please ensure all your serializers extend BaseSerializer, or configure `config.base_serializers`."
    end

    # Internal: Collects routes from Rails and groups them into resources
    def collect_rails_routes
      return [] unless defined?(Rails) && Rails.application

      routes_by_controller = Rails.application.routes.routes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |route, hash|
        # Filter routes based on export_if configuration (similar to js_from_routes)
        next unless route.defaults[:controller] && route.verb.present?
        next unless config.export_if.call(route)

        controller = namespace_for_route(route)
        action = route.defaults[:action]
        # Take the last verb from pipe-separated list (matches js_from_routes behavior)
        method = route.verb.split("|").last
        # Use chomp instead of sub for better path extraction (matches js_from_routes)
        path = route.path.spec.to_s.chomp("(.:format)")
        response_type = infer_response_type(route.defaults[:controller], action) || "unknown"

        # Reject duplicate PUT routes when PATCH exists for update action (js_from_routes pattern)
        next if action == "update" && method == "PUT" && hash[controller].any? { |r| r[:action] == "update" && r[:method] == "PATCH" }

        unless hash[controller].any? { |r| r[:method] == method && r[:action] == action && r[:path] == path }
          hash[controller] << {
            method: method,
            action: action,
            path: path,
            response_type: response_type,
          }
        end
      end

      routes_by_controller.map do |controller, routes|
        path_segments = routes.map { |r| r[:path].split("/")[1..-1] || [] }.uniq.sort_by(&:length)
        base_path = path_segments.any? ? path_segments.first.join("/")&.split("/{")&.first || controller : controller

        operations = routes.map do |route|
          path_params = route[:path].scan(/{([^}]+)}/).flatten
          response_type = if route[:response_type] == route[:action]
            "unknown"
          else
            (route[:action] == "index") ? "#{route[:response_type]}[]" : route[:response_type]
          end
          Operation.new(
            method: route[:method],
            action: route[:action],
            path_params: (route[:action] == "show") ? ["id"] : path_params,
            response_type: response_type,
          )
        end
        Resource.new(
          name: controller.tr("/", "_").camelize,
          path: "/#{base_path}",
          operations: operations,
        )
      end
    end

    # Internal: Extracts namespace from route export config or falls back to controller
    # (based on js_from_routes pattern)
    def namespace_for_route(route)
      if (export = route.defaults[:export]).is_a?(Hash)
        export[:namespace]
      end || route.defaults[:controller]
    end

    # Internal: Infers the response type based on controller and action
    def infer_response_type(controller, action)
      controller_class = "#{controller.camelize}Controller".safe_constantize
      return nil unless controller_class

      # Try to infer from explicit serializer usage in controller method
      if (serializer_from_method = extract_serializer_from_controller_method(controller_class, action))
        return serializer_from_method.tsp_name
      end

      # Try to infer from Sorbet signature on controller method
      if Sorbet.available?
        if (sorbet_type = infer_type_from_controller_sorbet(controller_class, action))
          return sorbet_type
        end
      end

      # Fall back to convention-based inference (controller name → serializer using name_from_serializer)
      model_name = controller.singularize.camelize
      loaded_serializers.find { |s| config.name_from_serializer.call(s.name) == model_name }&.tsp_name
    end

    # Internal: Extracts serializer class from controller method source using Prism AST
    def extract_serializer_from_controller_method(controller_class, action)
      return nil unless controller_class.method_defined?(action)

      method = controller_class.instance_method(action)
      source_location = method.source_location
      return nil unless source_location

      file_path, line_number = source_location
      return nil unless File.exist?(file_path)

      # Parse the file with Prism
      result = Prism.parse_file(file_path)
      return nil unless result.success?

      # Find the specific method definition node
      method_finder = MethodFinder.new(action.to_s, line_number)
      method_finder.visit(result.value)
      return nil unless method_finder.method_node

      # Find serializer references only within this method
      visitor = SerializerVisitor.new
      visitor.visit(method_finder.method_node)

      # Try to constantize any found serializers and return the first valid one
      visitor.serializer_names.filter_map(&:safe_constantize).first
    rescue
      # File read or parsing error - return nil
      nil
    end

    # Internal: Prism visitor to find a specific method definition by name and line
    class MethodFinder < Prism::Visitor
      attr_reader :method_node

      def initialize(method_name, line_number)
        super()
        @method_name = method_name
        @line_number = line_number
        @method_node = nil
      end

      def visit_def_node(node)
        # Match by method name and line number proximity
        if node.name.to_s == @method_name &&
            node.location.start_line <= @line_number &&
            node.location.end_line >= @line_number
          @method_node = node
        end
        super
      end
    end

    # Internal: Prism visitor to extract serializer class names from AST
    class SerializerVisitor < Prism::Visitor
      attr_reader :serializer_names

      def initialize
        super
        @serializer_names = []
      end

      # Visit call nodes to find serializer usage patterns
      def visit_call_node(node)
        # Pattern 1: render(..., serializer: FooSerializer)
        if node.name.to_s.in?(%w[render render_page])
          extract_serializer_from_render(node)
        end

        # Pattern 2: FooSerializer.one(...) or FooSerializer.many(...)
        if node.name.to_s.in?(%w[one many]) && node.receiver
          extract_serializer_from_class_method(node)
        end

        super
      end

    private

      # Extract serializer from render call keyword arguments
      def extract_serializer_from_render(node)
        return unless node.arguments&.arguments

        node.arguments.arguments
          .select { |arg| arg.is_a?(Prism::KeywordHashNode) }
          .flat_map(&:elements)
          .select do |el|
            el.is_a?(Prism::AssocNode) &&
              el.key.is_a?(Prism::SymbolNode) &&
              el.key.unescaped == "serializer"
          end
          .each do |element|
            @serializer_names << extract_constant_name(element.value) if constant_node?(element.value)
          end
      end

      # Extract serializer from SomeSerializer.one/many calls
      def extract_serializer_from_class_method(node)
        return unless constant_node?(node.receiver)

        # Collect any constant called with .one/.many - let constantization filter valid serializers
        extract_constant_name(node.receiver).then { |name| @serializer_names << name if name.present? }
      end

      # Check if node is a constant reference
      def constant_node?(node)
        node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
      end

      # Extract constant name from ConstantReadNode or ConstantPathNode
      def extract_constant_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          node.full_name
        else
          ""
        end
      end
    end

    # Internal: Infers TypeSpec type from Sorbet signature on controller method
    def infer_type_from_controller_sorbet(controller_class, action)
      return nil unless controller_class.method_defined?(action)

      sorbet_info = Sorbet.extract_type_for(controller_class, action)
      type_class = sorbet_info&.dig(:type_class)
      return nil unless type_class

      # If it's already a serializer, use it directly
      return type_class.tsp_name if type_class.respond_to?(:tsp_name)

      # If it's an ActiveRecord model, search for corresponding serializer using name_from_serializer
      if type_class.is_a?(Class) && type_class.ancestors.map(&:name).include?("ActiveRecord::Base")
        loaded_serializers.find { |s| config.name_from_serializer.call(s.name) == type_class.name }&.tsp_name
      end
    rescue
      # Type introspection or constantization error - return nil
      nil
    end

    # Internal: Generates the routes.tsp content with resources
    def routes_content(routes)
      imports = routes.flat_map { |r| r.operations.map(&:response_type) }.compact.uniq.map do |type|
        base_type = (type || "unknown").split("[]").first.gsub("::", "")
        next if base_type == "unknown"
        relative_path = "./models/#{base_type}.tsp"
        %(import "#{relative_path}";\n)
      end.compact.uniq.join

      resources = routes.map(&:as_typespec).join("\n").strip

      routes_namespace = if config.namespace
        # Wrap Routes in the same namespace as models
        <<~TSP
          namespace #{config.namespace} {
            namespace Routes {
              #{resources}
            }
          }
        TSP
      else
        <<~TSP
          namespace Routes {
            #{resources}
          }
        TSP
      end

      <<~TSP
        //
        // DO NOT MODIFY: This file was automatically generated by TypeSpecFromSerializers.
        import "@typespec/http";

        #{imports}
        using TypeSpec.Http;

        #{routes_namespace.strip}
      TSP
    end

    def default_config(root)
      Config.new(
        # The base serializers that all other serializers extend.
        base_serializers: ["BaseSerializer"],

        # The dirs where the serializer files are located.
        serializers_dirs: [root.join("app/serializers").to_s],

        # The dir where model files are placed.
        output_dir: root.join(defined?(ViteRuby) ? ViteRuby.config.source_code_dir : "app/frontend").join("typespec/generated"),

        # Remove the serializer suffix from the class name.
        name_from_serializer: ->(name) {
          transformed = name.split("::").map { |n| n.delete_suffix("Serializer") }.join("::")
          # Check for TypeSpec language keyword conflicts (always problematic)
          final_name = transformed.split("::").map do |part|
            if TYPESPEC_LANGUAGE_KEYWORDS.include?(part)
              warn "Warning: TypeSpec model name '#{part}' conflicts with reserved keyword. Renaming to '#{part}_'"
              "#{part}_"
            else
              part
            end
          end.join("::")
          final_name
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

        # Map Rails actions to TypeSpec operations
        action_to_operation_mapping: {
          "index" => "list",
          "show" => "read",
          "create" => "create",
          "update" => "update",
          "destroy" => "delete",
        },

        # Maps Sorbet types to TypeSpec types (optional Sorbet integration)
        sorbet_to_typespec_type_mapping: {
          "String" => :string,
          "Integer" => :int32,
          "Float" => :float64,
          "TrueClass" => :boolean,
          "FalseClass" => :boolean,
          "T::Boolean" => :boolean,
          "Date" => :plainDate,
          "DateTime" => :utcDateTime,
          "Time" => :utcDateTime,
          "Symbol" => :string,
        },

        # Allows to transform keys, useful when converting objects client-side.
        transform_keys: nil,

        # Allows scoping typespec definitions to a namespace
        # Default to Rails app name, or "Schema" as fallback
        namespace: (defined?(Rails) && Rails.application) ? Rails.application.class.module_parent_name : "Schema",

        # Filter routes to export (similar to js_from_routes)
        export_if: ->(route) { route.defaults.fetch(:export, nil) },
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

        import "./routes.tsp";
        #{serializers.reject(&:inline_serializer?).map { |s|
          %(import "./models/#{s.tsp_filename}.tsp";)
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
        #{model.used_imports.join unless model.used_imports.empty?}
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
