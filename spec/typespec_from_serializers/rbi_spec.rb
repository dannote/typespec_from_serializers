require "vanilla/config/boot"
require "vanilla/config/environment"

describe TypeSpecFromSerializers::RBI do
  describe ".generate_for_serializer" do
    it "generates RBI content for a serializer" do
      rbi = TypeSpecFromSerializers::RBI.generate_for_serializer(ComposerSerializer)

      expect(rbi).to include("# typed: strong")
      expect(rbi).to include("class ComposerSerializer")
      expect(rbi).to include("def self.one(item, options = nil); end")
      expect(rbi).to include("def self.many(items, options = nil); end")
      expect(rbi).to include("def self.one_as_hash(item, options = nil); end")
      expect(rbi).to include("def self.many_as_hash(items, options = nil); end")
      expect(rbi).to include("item: Composer")
      expect(rbi).to include("items: ::T.any(T::Array[Composer], ActiveRecord::Relation)")
    end

    it "returns nil if model class cannot be inferred" do
      # Use a serializer that doesn't follow naming convention
      # BaseSerializer itself won't have a corresponding model
      rbi = TypeSpecFromSerializers::RBI.generate_for_serializer(BaseSerializer)
      expect(rbi).to be_nil
    end

    it "infers model from object_as declaration" do
      # SongSerializer uses `object_as :song`
      rbi = TypeSpecFromSerializers::RBI.generate_for_serializer(SongSerializer)

      expect(rbi).to include("item: Song")
    end
  end

  describe ".generate_all" do
    let(:output_dir) { Pathname.new(File.expand_path("../../support/generated_rbi", __dir__)) }

    before do
      output_dir.rmtree if output_dir.exist?
      # Ensure serializers are loaded by triggering generation
      TypeSpecFromSerializers.generate
    end

    after do
      output_dir.rmtree if output_dir.exist?
    end

    it "generates RBI files for all serializers" do
      files = TypeSpecFromSerializers::RBI.generate_for_all_serializers(output_dir: output_dir)

      expect(files.size).to be > 0
      expect(output_dir.exist?).to be true

      # Check that a specific file was created
      composer_file = output_dir.join("composer_serializer.rbi")
      expect(composer_file.exist?).to be true

      content = composer_file.read
      expect(content).to include("class ComposerSerializer")
      expect(content).to include("item: Composer")
    end

    it "creates output directory if it doesn't exist" do
      expect(output_dir.exist?).to be false

      TypeSpecFromSerializers::RBI.generate_for_all_serializers(output_dir: output_dir)

      expect(output_dir.exist?).to be true
    end

    it "skips serializers without inferable models" do
      files = TypeSpecFromSerializers::RBI.generate_for_all_serializers(output_dir: output_dir)

      # Should generate RBI files only for serializers with inferable models
      expect(files.size).to be > 0

      # Check that at least one file was created
      expect(files.any? { |f| f.basename.to_s.include?("serializer.rbi") }).to be true

      # Files should contain valid RBI content
      files.each do |file|
        content = file.read
        expect(content).to include("# typed: strong")
        expect(content).to include("def self.one(item, options = nil); end")
      end
    end
  end
end
