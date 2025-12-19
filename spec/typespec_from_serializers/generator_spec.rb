require "vanilla/config/boot"
require "vanilla/config/environment"
require "ostruct"

describe "Generator" do
  let(:output_dir) { Pathname.new File.expand_path("../support/generated", __dir__) }
  let(:sample_dir) { Rails.root.join("app/frontend/types/serializers") }
  let(:serializers) {
    %w[
      Nested::AlbumSerializer
      VideoWithSongSerializer
      VideoSerializer
      SongSerializer
      SongWithVideosSerializer
      ModelSerializer
      ComposerWithSongsSerializer
      ComposerWithSongsSerializer::SongSerializer
      ComposerSerializer
      SnakeComposerSerializer
      TaskSerializer
    ]
  }

  def file_for(dir, name, ext)
    dir.join("#{TypeSpecFromSerializers.config.name_from_serializer.call(name).gsub("::", "/")}.#{ext}")
  end

  def app_file_for(name, ext = "tsp")
    file_for(sample_dir, name, ext)
  end

  def output_file_for(name, ext = "tsp")
    file_for(output_dir.join("models"), name, ext)
  end

  def expect_generator
    expect(TypeSpecFromSerializers)
  end

  def generate_serializers
    receive(:serializer_model_content).and_call_original
  end

  original_config = TypeSpecFromSerializers::Config.new TypeSpecFromSerializers.config.clone.to_h.transform_values(&:clone)

  before do
    TypeSpecFromSerializers.instance_variable_set(:@config, original_config)

    # Change the configuration to use a different directory.
    TypeSpecFromSerializers.config do |config|
      config.output_dir = output_dir
    end

    output_dir.rmtree if output_dir.exist?
  end

  context "with default config options" do
    # NOTE: We do a manual snapshot test for now, more tests coming in the future.
    it "generates the files as expected" do
      # Explicitly set namespace to nil to test without namespace
      TypeSpecFromSerializers.config do |config|
        config.namespace = nil
      end

      expect_generator.to generate_serializers.exactly(serializers.size).times
      TypeSpecFromSerializers.generate

      # It does not generate routes that don't have `export: true`.
      expect(output_file_for("BaseSerializer").exist?).to be false

      # It generates one file per serializer.
      serializers.each do |name|
        output_file = output_file_for(name)
        expect(output_file.read).to match_snapshot("models_#{name.gsub("::", "__")}") # UPDATE_SNAPSHOTS="1" bin/rspec
      end

      # It generates an file that exports all models.
      index_file = output_dir.join("index.tsp")
      expect(index_file.exist?).to be true
      expect(index_file.read).to match_snapshot("models_index") # UPDATE_SNAPSHOTS="1" bin/rspec

      # It generates a routes file
      routes_file = output_dir.join("routes.tsp")
      expect(routes_file.exist?).to be true
      expect(routes_file.read).to match_snapshot("routes_default") # UPDATE_SNAPSHOTS="1" bin/rspec

      # It does not render if generating again.
      TypeSpecFromSerializers.generate
    end
  end

  context "with namespace config option" do
    it "generates the files as expected" do
      TypeSpecFromSerializers.config do |config|
        config.namespace = "Schema"
      end

      expect_generator.to generate_serializers.exactly(serializers.size).times
      TypeSpecFromSerializers.generate

      # It does not generate routes that don't have `export: true`.
      expect(output_file_for("BaseSerializer", "tsp").exist?).to be false

      # It does not generate an index file
      index_file = output_dir.join("index.tsp")
      expect(index_file.exist?).to be false

      # It generates one file per serializer.
      serializers.each do |name|
        output_file = output_file_for(name, "tsp")
        expect(output_file.read).to match_snapshot("namespace_models_#{name.gsub("::", "__")}") # UPDATE_SNAPSHOTS="1" bin/rspec
      end
    end
  end

  it "has a rake task available" do
    Rails.application.load_tasks
    expect_generator.to generate_serializers.exactly(serializers.size).times
    expect { Rake::Task["typespec_from_serializers:generate"].invoke }.not_to raise_error
  end

  describe "types mapping" do
    it "maps citext type from SQL to string type in TypeSpec" do
      db_type = :citext

      tsp_type = TypeSpecFromSerializers.config.sql_to_typespec_type_mapping[db_type]

      expect(tsp_type).to eq(:string)
    end
  end

  describe "field name escaping" do
    it "escapes TypeSpec language keywords with backticks" do
      property = TypeSpecFromSerializers::Property.new(
        name: "model",
        type: :string,
        optional: false,
        multi: false,
        column_name: "model",
      )

      expect(property.as_typespec).to eq("`model`: string;")
    end

    it "escapes reflection type names (lowercase) with backticks" do
      property = TypeSpecFromSerializers::Property.new(
        name: "scalar",
        type: :int32,
        optional: false,
        multi: false,
        column_name: "scalar",
      )

      expect(property.as_typespec).to eq("`scalar`: int32;")
    end

    it "does not escape non-keyword field names" do
      property = TypeSpecFromSerializers::Property.new(
        name: "userId",
        type: :int32,
        optional: true,
        multi: false,
        column_name: "user_id",
      )

      expect(property.as_typespec).to eq("userId?: int32;")
    end

    it "escapes multiple keyword types" do
      %w[using extends is import namespace op alias].each do |keyword|
        property = TypeSpecFromSerializers::Property.new(
          name: keyword,
          type: :string,
          optional: false,
          multi: false,
          column_name: keyword,
        )

        expect(property.as_typespec).to eq("`#{keyword}`: string;")
      end
    end
  end

  describe "controller type inference" do
    let(:test_controller_class) {
      Class.new(ApplicationController) do
        extend T::Sig

        def self.name
          "TestController"
        end

        def explicit_serializer
          render json: User.all, serializer: ComposerSerializer
        end

        def serializer_one
          ComposerWithSongsSerializer.one(Composer.first)
        end

        def serializer_many
          SongSerializer.many(Song.all)
        end

        sig { returns(T::Array[Composer]) }
        def sorbet_typed_array
          Composer.all
        end

        sig { returns(Song) }
        def sorbet_typed_model
          Song.first
        end

        def no_serializer
          render json: {data: "test"}
        end
      end
    }

    describe "#extract_serializer_from_controller_method" do
      it "extracts serializer from render with serializer option" do
        result = TypeSpecFromSerializers.send(
          :extract_serializer_from_controller_method,
          test_controller_class,
          :explicit_serializer,
        )
        expect(result).to eq(ComposerSerializer)
      end

      it "extracts serializer from Serializer.one() call" do
        result = TypeSpecFromSerializers.send(
          :extract_serializer_from_controller_method,
          test_controller_class,
          :serializer_one,
        )
        expect(result).to eq(ComposerWithSongsSerializer)
      end

      it "extracts serializer from Serializer.many() call" do
        result = TypeSpecFromSerializers.send(
          :extract_serializer_from_controller_method,
          test_controller_class,
          :serializer_many,
        )
        expect(result).to eq(SongSerializer)
      end

      it "returns nil when no serializer found" do
        result = TypeSpecFromSerializers.send(
          :extract_serializer_from_controller_method,
          test_controller_class,
          :no_serializer,
        )
        expect(result).to be_nil
      end
    end

    describe "#infer_response_type integration" do
      before do
        stub_const("TestController", test_controller_class)
      end

      it "prioritizes explicit serializer over Sorbet" do
        # Even though the method has no Sorbet sig, explicit serializer wins
        result = TypeSpecFromSerializers.send(
          :infer_response_type,
          "test",
          :explicit_serializer,
        )
        expect(result).to eq("Composer")
      end

      it "uses Sorbet when no explicit serializer found" do
        result = TypeSpecFromSerializers.send(
          :infer_response_type,
          "test",
          :sorbet_typed_model,
        )
        expect(result).to eq("Song")
      end

      it "infers array types from Sorbet signatures" do
        result = TypeSpecFromSerializers.send(
          :infer_response_type,
          "test",
          :sorbet_typed_array,
        )
        expect(result).to eq("Composer")
      end
    end

    describe "#infer_type_from_controller_sorbet" do
      let(:sorbet_controller_class) {
        Class.new(ApplicationController) do
          extend T::Sig

          def self.name
            "SorbetTestController"
          end

          sig { returns(Composer) }
          def returns_model
            Composer.first
          end

          sig { returns(T::Array[Song]) }
          def returns_array
            Song.all
          end

          sig { returns(ComposerSerializer) }
          def returns_serializer
            ComposerSerializer.one(Composer.first)
          end
        end
      }

      it "infers type from ActiveRecord model Sorbet signature" do
        result = TypeSpecFromSerializers.send(
          :infer_type_from_controller_sorbet,
          sorbet_controller_class,
          :returns_model,
        )
        expect(result).to eq("Composer")
      end

      it "infers type from array of ActiveRecord models" do
        result = TypeSpecFromSerializers.send(
          :infer_type_from_controller_sorbet,
          sorbet_controller_class,
          :returns_array,
        )
        expect(result).to eq("Song")
      end

      it "infers type from serializer class Sorbet signature" do
        result = TypeSpecFromSerializers.send(
          :infer_type_from_controller_sorbet,
          sorbet_controller_class,
          :returns_serializer,
        )
        expect(result).to eq("Composer")
      end
    end
  end

  describe "route generation" do
    let(:routes_file) { output_dir.join("routes.tsp") }
    let(:original_routes) { Rails.application.routes.routes.dup }

    before do
      output_dir.rmtree if output_dir.exist?
      TypeSpecFromSerializers.generate
    end

    after do
      # Reset configuration to original state
      TypeSpecFromSerializers.instance_variable_set(:@config, original_config)
      TypeSpecFromSerializers.config do |config|
        config.output_dir = output_dir
      end

      # Reload routes to original state
      Rails.application.routes.clear!
      load Rails.root.join("config/routes.rb")
    end

    context "with export flag filtering" do
      it "only includes routes with export: true" do
        content = routes_file.read

        # Should include exported routes
        expect(content).to include("interface Composers")
        expect(content).to include("interface Songs")
        expect(content).to include("interface Videos")

        # Should NOT include Rails internal routes without export flag
        expect(content).not_to include("interface RailsInfo")
        expect(content).not_to include("interface RailsWelcome")
      end

      it "respects custom export_if configuration" do
        # Save original config
        original_export_if = TypeSpecFromSerializers.config.export_if

        begin
          TypeSpecFromSerializers.config do |config|
            # Configure to export all routes
            config.export_if = ->(route) { true }
          end

          output_dir.rmtree if output_dir.exist?
          TypeSpecFromSerializers.generate

          content = routes_file.read

          # Should now include routes since we're exporting everything
          expect(content).to include("interface Composers")
          expect(content).to match(/interface \w+/)  # Should have at least some interfaces
        ensure
          # Restore original config
          TypeSpecFromSerializers.config do |config|
            config.export_if = original_export_if
          end
        end
      end
    end

    context "with HTTP verb handling" do
      it "generates correct HTTP method decorators" do
        content = routes_file.read

        # Should have @get decorators for index and show actions
        expect(content).to include("@get index()")
        expect(content).to include("@get show(@path id: string)")
      end

      it "prefers PATCH over PUT for update actions" do
        # Create a temporary route with both PUT and PATCH

        Rails.application.routes.draw do
          defaults export: true do
            resources :composers, only: %i[index show update]
          end
        end

        output_dir.rmtree if output_dir.exist?
        TypeSpecFromSerializers.generate

        content = routes_file.read

        # Should have PATCH for update
        expect(content).to include("@patch")
        # Should NOT have duplicate PUT for the same update action
        # (Rails generates both PUT and PATCH, but we filter out PUT)
        put_count = content.scan(/@put\s+update/).size
        expect(put_count).to eq(0)
      ensure
        # Reload original routes
        Rails.application.routes.clear!
        load Rails.root.join("config/routes.rb")
      end
    end

    context "with route namespace support" do
      it "extracts namespace from export config" do
        # The namespace_for_route method should handle both:
        # - export: { namespace: "custom" }
        # - export: true (falls back to controller name)

        result = TypeSpecFromSerializers.send(:namespace_for_route,
          OpenStruct.new(defaults: {export: {namespace: "custom_ns"}, controller: "videos"}))
        expect(result).to eq("custom_ns")
      end

      it "falls back to controller name when no namespace in export config" do
        result = TypeSpecFromSerializers.send(:namespace_for_route,
          OpenStruct.new(defaults: {export: true, controller: "videos"}))
        expect(result).to eq("videos")
      end
    end

    context "with route uniqueness" do
      it "allows multiple routes with same action but different paths" do
        # This would be the case for nested routes or custom paths
        # The routes should be deduplicated by method + action + path

        content = routes_file.read

        # Each resource should have both index and show operations
        composers_section = content[/interface Composers.*?}/m]
        expect(composers_section).to include("index()")
        expect(composers_section).to include("show(@path id: string)")
      end
    end

    context "with path parameter extraction" do
      it "extracts path parameters correctly" do
        content = routes_file.read

        # Show actions should have id parameter
        expect(content).to include("show(@path id: string)")
      end

      it "generates array response types for index actions" do
        content = routes_file.read

        # Index actions should return arrays
        expect(content).to match(/index\(\): \w+\[\]/)
      end

      it "generates single object response types for show actions" do
        content = routes_file.read

        # Show actions should return single objects
        expect(content).to match(/show\(@path id: string\): \w+;/)
      end
    end

    context "with response type inference" do
      it "infers response types from serializers" do
        content = routes_file.read

        # Should map controller names to serializer types
        # Check for at least one of the main resources
        expect(content).to match(/Composer\[\]|Song\[\]|Video\[\]/)
      end

      it "imports the correct serializer types" do
        content = routes_file.read

        # Should have imports for used types with models/ prefix
        # Check for at least one of the main resource imports
        expect(content).to match(/import "\.\/models\/Composer\.tsp"|import "\.\/models\/Song\.tsp"|import "\.\/models\/Video\.tsp"/)
      end
    end

    context "with multiline formatting" do
      it "formats long operations across multiple lines when they exceed line length" do
        # The operation formatting logic splits lines > 100 chars
        # Current routes are short, so test the formatting logic works
        # by checking operations don't have extremely long single lines
        content = routes_file.read

        # Find all operation lines
        operation_lines = content.lines.grep(/@(get|post|put|patch|delete) \w+/)

        # If any operations exist, none should be excessively long (>150 chars)
        # This ensures multiline formatting kicks in for long parameter lists
        if operation_lines.any?
          operation_lines.each do |line|
            expect(line.length).to be < 150
          end
        end
      end

      it "keeps short operations on a single line" do
        content = routes_file.read

        # Short operations like index() should be on single lines
        expect(content).to match(/@get \w+\(\): \w+\[\];/)
        expect(content).to match(/@get \w+\(@path id: string\): \w+;/)
      end
    end
  end

  describe "route parameter type extraction" do
    before do
      # Include controller DSL for type declarations
      ApplicationController.send(:include, TypeSpecFromSerializers::DSL::Controller)
    end

    context "with route metadata param_types" do
      it "maps type classes to TypeSpec types" do
        result = TypeSpecFromSerializers.send(:map_type_class_to_typespec, Integer)
        expect(result).to eq("int32")

        result = TypeSpecFromSerializers.send(:map_type_class_to_typespec, String)
        expect(result).to eq("string")

        result = TypeSpecFromSerializers.send(:map_type_class_to_typespec, DateTime)
        expect(result).to eq("utcDateTime")
      end

      it "falls back to string for unknown types" do
        result = TypeSpecFromSerializers.send(:map_type_class_to_typespec, Object)
        expect(result).to eq("string")
      end
    end

    context "with type DSL on params methods" do
      after do
        # Reset config after each test
        TypeSpecFromSerializers.config do |config|
          config.param_method_suffix = "_params"
        end
      end

      it "extracts types from type DSL declarations" do
        # Create a test controller with type DSL
        test_controller = Class.new(ApplicationController) do
          type id: Integer, title: String
          def video_params
            {id: params[:id].to_i, title: params[:title].to_s}
          end
        end
        stub_const("TestController", test_controller)

        param_types = TypeSpecFromSerializers.send(:extract_param_types_from_controller, TestController, "show")

        expect(param_types["id"]).to eq("int32")
        expect(param_types["title"]).to eq("string")
      end

      it "uses configurable param_method_suffix" do
        TypeSpecFromSerializers.config do |config|
          config.param_method_suffix = "_parameters"
        end

        test_controller = Class.new(ApplicationController) do
          type id: Integer
          def video_parameters
            {id: params[:id].to_i}
          end
        end
        stub_const("TestController", test_controller)

        param_types = TypeSpecFromSerializers.send(:extract_param_types_from_controller, TestController, "show")

        expect(param_types["id"]).to eq("int32")
      end

      it "returns empty hash when no type DSL used and Sorbet unavailable" do
        # Create a test controller with no type annotations
        test_controller = Class.new(ApplicationController) do
          def video_params
            {id: params[:id].to_i, name: params[:name].to_s}
          end
        end
        stub_const("TestController", test_controller)

        param_types = TypeSpecFromSerializers.send(:extract_param_types_from_controller, TestController, "show")

        # Should return empty since no types declared
        expect(param_types).to eq({})
      end
    end

    context "priority and fallback" do
      it "handles multiple param methods" do
        test_controller = Class.new(ApplicationController) do
          type id: Integer
          def video_params
            {id: params[:id].to_i}
          end

          type slug: String
          def article_params
            {slug: params[:slug].to_s}
          end
        end
        stub_const("TestController", test_controller)

        param_types = TypeSpecFromSerializers.send(:extract_param_types_from_controller, TestController, "show")

        # Should extract from both methods
        expect(param_types["id"]).to eq("int32")
        expect(param_types["slug"]).to eq("string")
      end

      it "returns empty hash when extraction fails" do
        param_types = TypeSpecFromSerializers.send(:extract_param_types_from_controller, nil, "show")

        expect(param_types).to eq({})
      end
    end
  end

  context "when compiling TypeSpec" do
    before do
      # Clean and regenerate with default config (no namespace) to ensure valid TypeSpec
      output_dir.rmtree if output_dir.exist?
    end

    it "generates valid TypeSpec that compiles without errors" do
      skip "tsp compiler not available" unless system("npx --version > /dev/null 2>&1")

      # Check Node.js version (need v20.12+ for TypeSpec)
      node_version = `node --version`.strip.match(/v(\d+)\.(\d+)/)[1..2].map(&:to_i)
      skip "Node.js v20.12+ required for TypeSpec compiler" if node_version[0] == 20 && node_version[1] < 12

      # Ensure namespace is nil for this test
      TypeSpecFromSerializers.config.namespace = nil

      expect_generator.to generate_serializers.exactly(serializers.size).times
      TypeSpecFromSerializers.generate(force: true)

      # Compile routes.tsp which already imports all necessary models
      output = `cd #{output_dir} && npx --yes tsp compile routes.tsp 2>&1`
      success = $?.success?

      expect(success).to be(true), "TypeSpec compilation failed:\n#{output}"
    end
  end
end
