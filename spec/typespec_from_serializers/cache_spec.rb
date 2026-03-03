# frozen_string_literal: true

require "vanilla/config/boot"
require "vanilla/config/environment"
require "digest"

describe "Cache keys" do
  describe "content-based cache keys" do
    let(:output_dir) { Pathname.new File.expand_path("../support/cache_test", __dir__) }

    before do
      @original_config = TypeSpecFromSerializers.config.clone
      TypeSpecFromSerializers.config do |config|
        config.output_dir = output_dir
      end
      output_dir.rmtree if output_dir.exist?
    end

    after do
      output_dir.rmtree if output_dir.exist?
    end

    it "derives cache key from generated content, not internal representation" do
      model = TypeSpecFromSerializers::Interface.new(
        name: "Stable",
        filename: "Stable",
        properties: [
          TypeSpecFromSerializers::Property.new(
            name: "id",
            type: :int32,
            optional: false,
            multi: false,
            column_name: "id",
            doc: nil,
          ),
        ],
        doc: nil,
      )

      content = TypeSpecFromSerializers.send(:serializer_model_content, model)
      cache_key_hash = Digest::MD5.hexdigest(content)

      TypeSpecFromSerializers.send(
        :write_if_changed,
        filename: "models/Stable",
        cache_key: content,
        extension: "tsp",
      ) { content }

      file_content = output_dir.join("models/Stable.tsp").read
      expect(file_content).to start_with("// TypeSpecFromSerializers CacheKey #{cache_key_hash}")
    end

    it "does not rewrite file when content is identical" do
      model = TypeSpecFromSerializers::Interface.new(
        name: "Stable",
        filename: "Stable",
        properties: [
          TypeSpecFromSerializers::Property.new(
            name: "id",
            type: :int32,
            optional: false,
            multi: false,
            column_name: "id",
            doc: nil,
          ),
        ],
        doc: nil,
      )

      content = TypeSpecFromSerializers.send(:serializer_model_content, model)

      TypeSpecFromSerializers.send(
        :write_if_changed,
        filename: "models/Stable",
        cache_key: content,
        extension: "tsp",
      ) { content }

      mtime = output_dir.join("models/Stable.tsp").mtime

      TypeSpecFromSerializers.send(
        :write_if_changed,
        filename: "models/Stable",
        cache_key: content,
        extension: "tsp",
      ) { content }

      expect(output_dir.join("models/Stable.tsp").mtime).to eq(mtime)
    end
  end

  describe "model cache keys" do
    it "includes all interface fields including doc" do
      interface = TypeSpecFromSerializers::Interface.new(
        name: "Test",
        filename: "Test",
        properties: [],
        doc: "Test documentation",
      )

      cache_key = interface.inspect

      expect(cache_key).to include("Test")
      expect(cache_key).to include("Test documentation")
    end

    it "changes when doc changes" do
      interface1 = TypeSpecFromSerializers::Interface.new(
        name: "Test",
        filename: "Test",
        properties: [],
        doc: "Original doc",
      )

      interface2 = TypeSpecFromSerializers::Interface.new(
        name: "Test",
        filename: "Test",
        properties: [],
        doc: "Updated doc",
      )

      expect(interface1.inspect).not_to eq(interface2.inspect)
    end

    it "changes when doc is added" do
      interface1 = TypeSpecFromSerializers::Interface.new(
        name: "Test",
        filename: "Test",
        properties: [],
        doc: nil,
      )

      interface2 = TypeSpecFromSerializers::Interface.new(
        name: "Test",
        filename: "Test",
        properties: [],
        doc: "New doc",
      )

      expect(interface1.inspect).not_to eq(interface2.inspect)
    end
  end

  describe "routes cache keys" do
    it "includes all resource and operation fields including doc" do
      resource = TypeSpecFromSerializers::Resource.new(
        path: "/test",
        name: "Test",
        parent_namespace: nil,
        operations: [
          TypeSpecFromSerializers::Operation.new(
            method: "GET",
            action: "index",
            path: "/test",
            path_params: [],
            body_params: [],
            response_type: "Test[]",
            doc: "List all tests",
          ),
        ],
      )

      cache_key = [resource].map(&:inspect).join

      expect(cache_key).to include("/test")
      expect(cache_key).to include("index")
      expect(cache_key).to include("List all tests")
    end

    it "changes when operation doc changes" do
      resource1 = TypeSpecFromSerializers::Resource.new(
        path: "/test",
        name: "Test",
        parent_namespace: nil,
        operations: [
          TypeSpecFromSerializers::Operation.new(
            method: "GET",
            action: "index",
            path: "/test",
            path_params: [],
            body_params: [],
            response_type: "Test[]",
            doc: "Original doc",
          ),
        ],
      )

      resource2 = TypeSpecFromSerializers::Resource.new(
        path: "/test",
        name: "Test",
        parent_namespace: nil,
        operations: [
          TypeSpecFromSerializers::Operation.new(
            method: "GET",
            action: "index",
            path: "/test",
            path_params: [],
            body_params: [],
            response_type: "Test[]",
            doc: "Updated doc",
          ),
        ],
      )

      cache_key1 = [resource1].map(&:inspect).join
      cache_key2 = [resource2].map(&:inspect).join

      expect(cache_key1).not_to eq(cache_key2)
    end

    it "changes when operation doc is added" do
      resource1 = TypeSpecFromSerializers::Resource.new(
        path: "/test",
        name: "Test",
        parent_namespace: nil,
        operations: [
          TypeSpecFromSerializers::Operation.new(
            method: "GET",
            action: "index",
            path: "/test",
            path_params: [],
            body_params: [],
            response_type: "Test[]",
            doc: nil,
          ),
        ],
      )

      resource2 = TypeSpecFromSerializers::Resource.new(
        path: "/test",
        name: "Test",
        parent_namespace: nil,
        operations: [
          TypeSpecFromSerializers::Operation.new(
            method: "GET",
            action: "index",
            path: "/test",
            path_params: [],
            body_params: [],
            response_type: "Test[]",
            doc: "New doc",
          ),
        ],
      )

      cache_key1 = [resource1].map(&:inspect).join
      cache_key2 = [resource2].map(&:inspect).join

      expect(cache_key1).not_to eq(cache_key2)
    end
  end
end
