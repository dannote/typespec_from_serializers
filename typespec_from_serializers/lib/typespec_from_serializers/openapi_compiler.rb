# frozen_string_literal: true

require_relative "runner"

module TypeSpecFromSerializers
  module OpenAPICompiler
    class CompilationError < StandardError; end

    class << self
      # Public: Compiles TypeSpec to OpenAPI specification.
      #
      # Returns the Pathname to the generated OpenAPI file.
      def compile
        require "fileutils"

        typespec_dir = config.output_dir
        FileUtils.mkdir_p(config.openapi_path.dirname)

        compile_typespec(typespec_dir)

        config.openapi_path
      end

      private

      def config
        TypeSpecFromSerializers.config
      end

      def runner
        @runner ||= TypeSpecFromSerializers::Runner.new(config)
      end

      # Internal: Executes TypeSpec compilation with OpenAPI emitter.
      def compile_typespec(typespec_dir)
        args = [
          "compile", "routes.tsp",
          "--emit", "@typespec/openapi3",
          "--option", "@typespec/openapi3.emitter-output-dir=#{config.openapi_path.dirname}",
          "--option", "@typespec/openapi3.output-file=#{config.openapi_path.basename}",
        ]

        output, error, status = runner.run(args, chdir: typespec_dir, with_output: ->(line) { print line })

        unless status.success?
          raise CompilationError, "TypeSpec compilation failed:\n#{output}#{error}"
        end

        unless config.openapi_path.exist?
          raise CompilationError, "OpenAPI output not found at: #{config.openapi_path}"
        end
      rescue TypeSpecFromSerializers::Runner::MissingExecutableError => e
        raise CompilationError, <<~ERROR
          #{e.message}

          Please install Node.js and a package manager:
          https://nodejs.org/
        ERROR
      end
    end
  end
end
