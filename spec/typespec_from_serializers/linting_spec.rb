# frozen_string_literal: true

require "vanilla/config/boot"
require "vanilla/config/environment"

describe "Linting" do
  let(:output_dir) { Pathname.new File.expand_path("../support/generated", __dir__) }

  # Deep clone the config to ensure proper test isolation
  original_config_hash = TypeSpecFromSerializers.config.to_h.transform_values { |v| v.is_a?(Hash) ? v.dup : v }
  original_config = TypeSpecFromSerializers::Config.new(original_config_hash)

  before do
    # Reset to a fresh clone for each test
    fresh_config = TypeSpecFromSerializers::Config.new(original_config_hash.transform_values { |v| v.is_a?(Hash) ? v.dup : v })
    TypeSpecFromSerializers.instance_variable_set(:@config, fresh_config)
    TypeSpecFromSerializers.config do |config|
      config.output_dir = output_dir
    end
    output_dir.rmtree if output_dir.exist?
  end

  describe "config.linting = false" do
    it "disables all linting" do
      TypeSpecFromSerializers.config do |config|
        config.linting = false
      end

      expect {
        TypeSpecFromSerializers.generate(force: true)
      }.not_to output(/TypeSpec Lint:/).to_stderr
    end
  end

  describe "default configuration" do
    it "has linting enabled by default" do
      expect(TypeSpecFromSerializers.config.linting).to be_a(Hash)
      expect(TypeSpecFromSerializers.config.linting[:missing_param_types]).to be true
      expect(TypeSpecFromSerializers.config.linting[:unknown_response_types]).to be true
      expect(TypeSpecFromSerializers.config.linting[:missing_documentation]).to be true
      expect(TypeSpecFromSerializers.config.linting[:ambiguous_operations]).to be true
      expect(TypeSpecFromSerializers.config.linting[:type_inference_failures]).to be true
    end
  end
end
