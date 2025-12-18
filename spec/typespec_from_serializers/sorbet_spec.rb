require "spec_helper"

describe TypeSpecFromSerializers::Sorbet do
  let(:extractor) { TypeSpecFromSerializers::Sorbet }

  describe ".available?" do
    context "when sorbet-runtime is loaded" do
      it "returns true" do
        # sorbet-runtime is now a development dependency, so it's always available
        expect(extractor.available?).to be true
      end
    end
  end

  describe ".extract_type_for" do
    context "when sorbet-runtime is not available" do
      before do
        allow(extractor).to receive(:available?).and_return(false)
      end

      it "returns nil" do
        result = extractor.extract_type_for(String, :to_s)
        expect(result).to be_nil
      end
    end

    context "when method doesn't exist" do
      it "returns nil gracefully" do
        skip "sorbet-runtime not available" unless defined?(T::Utils)

        result = extractor.extract_type_for(String, :nonexistent_method_12345)
        expect(result).to be_nil
      end
    end

    context "when method has no signature" do
      it "returns nil" do
        skip "sorbet-runtime not available" unless defined?(T::Utils)

        # String#to_s exists but has no Sorbet signature
        result = extractor.extract_type_for(String, :to_s)
        expect(result).to be_nil
      end
    end
  end

  describe ".rbi_available?" do
    context "when sorbet/rbi directory doesn't exist" do
      it "returns false" do
        # Check if the directory actually doesn't exist
        path = if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join("sorbet/rbi")
        else
          Pathname.new("sorbet/rbi")
        end

        if path.exist? && path.directory?
          skip "sorbet/rbi directory exists in test environment"
        else
          expect(extractor.rbi_available?).to be false
        end
      end
    end

    context "when sorbet/rbi directory exists" do
      it "returns true" do
        path = if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join("sorbet/rbi")
        else
          Pathname.new("sorbet/rbi")
        end

        skip "sorbet/rbi directory not present" unless path.exist? && path.directory?

        expect(extractor.rbi_available?).to be true
      end
    end
  end

  describe "RBI integration" do
    context "when RBI files are not available" do
      before do
        allow(extractor).to receive(:rbi_available?).and_return(false)
      end

      it "falls back gracefully" do
        # Should return nil since both runtime and RBI are unavailable
        result = extractor.extract_type_for(String, :to_s)
        expect(result).to be_nil
      end
    end

    context "when RBI files exist but no signature found" do
      it "returns nil gracefully" do
        skip "sorbet/rbi directory not present" unless File.directory?("sorbet/rbi")

        result = extractor.extract_type_for(String, :to_s)
        expect([nil, Hash]).to include(result.class)
      end
    end
  end
end
