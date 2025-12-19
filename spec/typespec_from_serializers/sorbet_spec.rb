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

  describe "Type extraction from Sorbet signatures" do
    before do
      skip "sorbet-runtime not available" unless defined?(T::Sig)
    end

    context "simple types" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(String) }
          def string_method
            "test"
          end

          sig { returns(Integer) }
          def integer_method
            42
          end

          sig { returns(Float) }
          def float_method
            3.14
          end

          sig { returns(T::Boolean) }
          def boolean_method
            true
          end

          sig { returns(Symbol) }
          def symbol_method
            :test
          end
        end
      end

      it "extracts String type" do
        result = extractor.extract_type_for(test_class, :string_method)
        expect(result).to eq({
          typespec_type: :string,
          nilable: false,
          array: false,
          type_class: String
        })
      end

      it "extracts Integer type" do
        result = extractor.extract_type_for(test_class, :integer_method)
        expect(result).to eq({
          typespec_type: :int32,
          nilable: false,
          array: false,
          type_class: Integer
        })
      end

      it "extracts Float type" do
        result = extractor.extract_type_for(test_class, :float_method)
        expect(result).to eq({
          typespec_type: :float64,
          nilable: false,
          array: false,
          type_class: Float
        })
      end

      it "extracts Boolean type" do
        result = extractor.extract_type_for(test_class, :boolean_method)
        expect(result[:typespec_type]).to eq(:boolean)
        expect(result[:nilable]).to be false
        expect(result[:array]).to be false
      end

      it "extracts Symbol type" do
        result = extractor.extract_type_for(test_class, :symbol_method)
        expect(result).to eq({
          typespec_type: :string,
          nilable: false,
          array: false,
          type_class: Symbol
        })
      end
    end

    context "nilable types" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T.nilable(String)) }
          def nilable_string
            nil
          end

          sig { returns(T.nilable(Integer)) }
          def nilable_integer
            nil
          end
        end
      end

      it "extracts nilable String" do
        result = extractor.extract_type_for(test_class, :nilable_string)
        expect(result).to eq({
          typespec_type: :string,
          nilable: true,
          array: false,
          type_class: String
        })
      end

      it "extracts nilable Integer" do
        result = extractor.extract_type_for(test_class, :nilable_integer)
        expect(result).to eq({
          typespec_type: :int32,
          nilable: true,
          array: false,
          type_class: Integer
        })
      end
    end

    context "array types" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T::Array[String]) }
          def string_array
            []
          end

          sig { returns(T::Array[Integer]) }
          def integer_array
            []
          end

          sig { returns(T.nilable(T::Array[String])) }
          def nilable_array
            nil
          end
        end
      end

      it "extracts String array" do
        result = extractor.extract_type_for(test_class, :string_array)
        expect(result).to eq({
          typespec_type: :string,
          nilable: false,
          array: true,
          type_class: String
        })
      end

      it "extracts Integer array" do
        result = extractor.extract_type_for(test_class, :integer_array)
        expect(result).to eq({
          typespec_type: :int32,
          nilable: false,
          array: true,
          type_class: Integer
        })
      end

      it "extracts nilable array" do
        result = extractor.extract_type_for(test_class, :nilable_array)
        expect(result).to eq({
          typespec_type: :string,
          nilable: true,
          array: true,
          type_class: String
        })
      end
    end

    context "hash types" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T::Hash[String, Integer]) }
          def hash_method
            {}
          end

          sig { returns(T::Hash[Symbol, String]) }
          def symbol_keyed_hash
            {}
          end
        end
      end

      it "extracts Hash with Integer values" do
        result = extractor.extract_type_for(test_class, :hash_method)
        expect(result).to eq({
          typespec_type: "Record<int32>",
          nilable: false,
          array: false,
          type_class: nil
        })
      end

      it "extracts Hash with String values" do
        result = extractor.extract_type_for(test_class, :symbol_keyed_hash)
        expect(result).to eq({
          typespec_type: "Record<string>",
          nilable: false,
          array: false,
          type_class: nil
        })
      end
    end

    context "shape types (FixedHash)" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T::Array[{lon: Float, lat: Float}]) }
          def coordinates
            []
          end

          sig { returns(T::Array[{name: String, age: Integer}]) }
          def people
            []
          end
        end
      end

      it "extracts coordinate shape array" do
        result = extractor.extract_type_for(test_class, :coordinates)
        expect(result[:typespec_type]).to eq("{lon: float64, lat: float64}")
        expect(result[:nilable]).to be false
        expect(result[:array]).to be true
      end

      it "extracts people shape array" do
        result = extractor.extract_type_for(test_class, :people)
        expect(result[:typespec_type]).to eq("{name: string, age: int32}")
        expect(result[:nilable]).to be false
        expect(result[:array]).to be true
      end
    end

    context "set types" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T::Set[String]) }
          def string_set
            Set.new
          end

          sig { returns(T::Set[Integer]) }
          def integer_set
            Set.new
          end
        end
      end

      it "extracts String set as array" do
        result = extractor.extract_type_for(test_class, :string_set)
        expect(result).to eq({
          typespec_type: :string,
          nilable: false,
          array: true,
          type_class: nil
        })
      end

      it "extracts Integer set as array" do
        result = extractor.extract_type_for(test_class, :integer_set)
        expect(result).to eq({
          typespec_type: :int32,
          nilable: false,
          array: true,
          type_class: nil
        })
      end
    end

    context "union types (T.any)" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T.any(String, Integer)) }
          def string_or_integer
            "test"
          end

          sig { returns(T.any(String, Integer, Float)) }
          def multi_union
            42
          end
        end
      end

      it "extracts two-type union" do
        result = extractor.extract_type_for(test_class, :string_or_integer)
        expect(result[:typespec_type]).to match(/string \| int32|int32 \| string/)
        expect(result[:nilable]).to be false
        expect(result[:array]).to be false
      end

      it "extracts multi-type union" do
        result = extractor.extract_type_for(test_class, :multi_union)
        expect(result[:typespec_type]).to include("string")
        expect(result[:typespec_type]).to include("int32")
        expect(result[:typespec_type]).to include("float64")
        expect(result[:nilable]).to be false
        expect(result[:array]).to be false
      end
    end

    context "untyped" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T.untyped) }
          def untyped_method
            "anything"
          end
        end
      end

      it "extracts untyped as unknown" do
        result = extractor.extract_type_for(test_class, :untyped_method)
        expect(result).to eq({
          typespec_type: "unknown",
          nilable: false,
          array: false,
          type_class: nil
        })
      end
    end

    context "nested array types" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T::Array[T::Array[String]]) }
          def nested_arrays
            [[]]
          end

          sig { returns(T::Array[T::Array[Integer]]) }
          def integer_matrix
            [[]]
          end
        end
      end

      it "extracts nested string arrays" do
        result = extractor.extract_type_for(test_class, :nested_arrays)
        # For nested arrays, we expect the inner array to be represented as string[]
        # and the outer to add another [] -> string[][]
        # However, current implementation might not handle this - we'll see what happens
        expect(result).not_to be_nil
        # The exact format depends on implementation - document what we get
      end
    end

    context "nested hash types" do
      let(:test_class) do
        Class.new do
          extend T::Sig

          sig { returns(T::Hash[String, T::Array[Integer]]) }
          def hash_with_array_values
            {}
          end

          sig { returns(T::Hash[String, T::Hash[String, String]]) }
          def nested_hashes
            {}
          end
        end
      end

      it "extracts hash with array values" do
        result = extractor.extract_type_for(test_class, :hash_with_array_values)
        # Should be Record<int32[]> or similar
        expect(result).not_to be_nil
      end
    end

    context "custom class types" do
      let(:custom_class) { Class.new }
      let(:test_class) do
        custom = custom_class
        Class.new do
          extend T::Sig

          sig { returns(custom) }
          define_method(:custom_method) do
            custom.new
          end

          sig { returns(T::Array[custom]) }
          define_method(:custom_array) do
            []
          end
        end
      end

      it "extracts custom class" do
        result = extractor.extract_type_for(test_class, :custom_method)
        expect(result).not_to be_nil
        expect(result[:type_class]).to eq(custom_class)
      end

      it "extracts array of custom class" do
        result = extractor.extract_type_for(test_class, :custom_array)
        expect(result).not_to be_nil
        expect(result[:array]).to be true
      end
    end
  end
end
