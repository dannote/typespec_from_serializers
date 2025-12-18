require "spec_helper"

describe "Type DSL" do
  let(:generator) { TypeSpecFromSerializers }

  before do
    # Define a test serializer with type DSL
    stub_const("TypeDslTestSerializer", Class.new do
      include TypeSpecFromSerializers::DSL

      type String
      def full_name
        "John Doe"
      end

      type T.nilable(Integer) if defined?(T)
      def age
        30
      end

      type T::Array[String] if defined?(T)
      def tags
        ["tag1", "tag2"]
      end
    end)
  end

  describe ".type_for_method" do
    it "stores type declarations for methods" do
      expect(TypeDslTestSerializer.type_for_method(:full_name)).to eq(String)
    end

    it "handles T.nilable types" do
      skip "Sorbet not available" unless defined?(T)
      type_annotation = TypeDslTestSerializer.type_for_method(:age)
      expect(type_annotation).to be_a(T::Types::Union)
    end

    it "handles T::Array types" do
      skip "Sorbet not available" unless defined?(T)
      type_annotation = TypeDslTestSerializer.type_for_method(:tags)
      expect(type_annotation).to be_a(T::Types::TypedArray)
    end

    it "returns nil for methods without type declarations" do
      TypeDslTestSerializer.class_eval do
        def undeclared_method
          "value"
        end
      end

      expect(TypeDslTestSerializer.type_for_method(:undeclared_method)).to be_nil
    end
  end

  describe "Sorbet integration" do
    it "extracts types from type DSL" do
      result = TypeSpecFromSerializers::Sorbet.extract_type_for(TypeDslTestSerializer, :full_name)

      expect(result).to be_a(Hash)
      expect(result[:typespec_type]).to eq(:string)
      expect(result[:nilable]).to be false
      expect(result[:array]).to be false
    end

    it "handles nilable types" do
      skip "Sorbet not available" unless defined?(T)
      result = TypeSpecFromSerializers::Sorbet.extract_type_for(TypeDslTestSerializer, :age)

      expect(result).to be_a(Hash)
      expect(result[:typespec_type]).to eq(:int32)
      expect(result[:nilable]).to be true
      expect(result[:array]).to be false
    end

    it "handles array types" do
      skip "Sorbet not available" unless defined?(T)
      result = TypeSpecFromSerializers::Sorbet.extract_type_for(TypeDslTestSerializer, :tags)

      expect(result).to be_a(Hash)
      expect(result[:typespec_type]).to eq(:string)
      expect(result[:nilable]).to be false
      expect(result[:array]).to be true
    end
  end

  describe "backward compatibility" do
    it "differentiates between symbol types (attributes) and class types (methods)" do
      # Symbol types should trigger attribute behavior (not store in registry)
      # Class types should store in registry for methods
      expect(TypeDslTestSerializer.return_type_registry[:full_name]).to eq(String)
    end
  end
end
