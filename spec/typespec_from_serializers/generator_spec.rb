require "vanilla/config/boot"
require "vanilla/config/environment"

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
end
