# frozen_string_literal: true

require "rdoc"

module TypeSpecFromSerializers
  # Public: RDoc integration for documentation extraction.
  #
  # This module uses RDoc's Prism-based parser to extract documentation
  # comments from Ruby source files. It provides documentation for:
  # 1. Classes (serializers, controllers)
  # 2. Methods (controller actions, serializer attributes)
  #
  # The module caches parsed files to avoid re-parsing the same file
  # multiple times during a single generation run.
  #
  # Requires RDoc 7.0+ for Prism parser support. Gracefully degrades
  # to returning nil for all documentation when unavailable.
  module RDoc
    class << self
      # Public: Check if RDoc Prism parser is available.
      #
      # Returns true if RDoc 7.0+ with Prism parser is available.
      def available?
        return @available if defined?(@available)

        @available = begin
          require "rdoc/parser/prism_ruby"
          true
        rescue LoadError
          false
        end
      end

      # Public: Get documentation for a class.
      #
      # klass - The Class to get documentation for
      #
      # Returns String or nil
      def class_doc(klass)
        find_rdoc_class(klass)&.then { extract_comment_text(_1.comment) }
      end

      # Public: Get documentation for a method.
      #
      # klass       - The Class containing the method
      # method_name - Symbol or String name of the method
      #
      # Returns String or nil
      def method_doc(klass, method_name)
        find_rdoc_class(klass)
          &.method_list
          &.find { _1.name == method_name.to_s }
          &.then { extract_comment_text(_1.comment) }
      end

      # Public: Clear the parse cache.
      #
      # This should be called between generation runs if files may have changed.
      def clear_cache!
        @cache = {}
      end

      private

      # Internal: Find the RDoc class object for a Ruby class.
      #
      # klass - The Class to find documentation for
      #
      # Returns RDoc::NormalClass, RDoc::NormalModule, or nil
      def find_rdoc_class(klass)
        return unless available?

        file_path = Object.const_source_location(klass.name)&.first
        top_level = file_path && parse_file(file_path)
        return unless top_level

        class_name = klass.name.split("::").last
        top_level.classes.find { _1.name == class_name } ||
          top_level.modules.find { _1.name == class_name }
      rescue
        nil
      end

      # Internal: Parse a Ruby file and return the RDoc top-level object.
      #
      # file_path - String path to the Ruby file
      #
      # Returns RDoc::TopLevel or nil if parsing fails
      def parse_file(file_path)
        @cache ||= {}
        @cache[file_path] ||= begin
          return unless File.exist?(file_path)

          options = ::RDoc::Options.new
          store = ::RDoc::Store.new(options)
          top_level = store.add_file(file_path)
          stats = ::RDoc::Stats.new(store, 0, 0)

          parser = ::RDoc::Parser::PrismRuby.new(top_level, File.read(file_path), options, stats)
          parser.scan
          top_level
        rescue => e
          warn "TypeSpec: Failed to parse #{file_path} for docs: #{e.message}" if ENV["DEBUG"]
          nil
        end
      end

      # Internal: Extract text from an RDoc::Comment or String.
      #
      # comment - RDoc::Comment object or String
      #
      # Returns String or nil
      def extract_comment_text(comment)
        case comment
        when String then comment.strip.presence
        when nil then nil
        else
          comment.normalize
          comment.text&.strip.presence
        end
      end
    end
  end
end
