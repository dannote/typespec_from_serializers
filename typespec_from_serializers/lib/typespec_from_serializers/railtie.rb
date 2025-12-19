# frozen_string_literal: true

require "rails/railtie"

class TypeSpecFromSerializers::Railtie < Rails::Railtie
  railtie_name :typespec_from_serializers

  # Automatically generates code whenever a serializer is loaded.
  if defined?(Rails.env) && Rails.env.development?
    require_relative "generator"

    initializer "typespec_from_serializers.reloader" do |app|
      if Gem.loaded_specs["listen"]
        require "listen"

        app.config.after_initialize do
          app.reloaders << TypeSpecFromSerializers.track_changes
        end

        app.config.to_prepare do
          TypeSpecFromSerializers.generate_changed
        end
      else
        app.config.to_prepare do
          TypeSpecFromSerializers.generate
        end

        Rails.logger.warn "Add 'listen' to your Gemfile to automatically generate code on serializer changes."
      end
    end
  end

  # Suitable when triggering code generation manually.
  rake_tasks do |app|
    namespace :typespec_from_serializers do
      desc "Install TypeSpec dependencies"
      task setup: :environment do
        require_relative "generator"
        require_relative "runner"
        require "fileutils"

        config = TypeSpecFromSerializers.config
        root = config.root

        puts "Setting up TypeSpec dependencies..."

        # Create package.json in project root if it doesn't exist
        package_json_path = root.join("package.json")
        unless package_json_path.exist?
          puts "Creating package.json in #{root}..."
          File.write(package_json_path, <<~JSON)
            {
              "private": true,
              "type": "module"
            }
          JSON
        end

        # Install TypeSpec packages
        puts "Installing TypeSpec packages..."
        deps = %w[@typespec/compiler @typespec/http @typespec/openapi3]

        install_cmd = case config.package_manager
        when "npm"
          ["npm", "install", "--save-dev", *deps]
        when "pnpm"
          ["pnpm", "add", "-D", *deps]
        when "bun"
          ["bun", "add", "-d", *deps]
        when "yarn"
          ["yarn", "add", "-D", *deps]
        end

        output, error, status = TypeSpecFromSerializers::IO.capture(
          *install_cmd,
          chdir: root.to_s,
          with_output: ->(line) { print line }
        )

        if status.success?
          puts "\nTypeSpec dependencies installed successfully! 🎉"
        else
          puts "\nFailed to install dependencies:"
          puts error
          exit 1
        end
      end

      desc "Generates TypeSpec descriptions for each serializer in the app."
      task generate: :environment do
        require_relative "generator"
        start_time = Time.zone.now
        print "Generating TypeSpec descriptions..."
        result = TypeSpecFromSerializers.generate(force: true)
        puts "completed in #{(Time.zone.now - start_time).round(2)} seconds.\n"
        puts "Found #{result[:serializers].size} serializers:"
        puts result[:serializers].map { |s| "\t#{s.name}" }.join("\n")
        if result[:controllers].any?
          puts "\nFound #{result[:controllers].size} controllers:"
          puts result[:controllers].map { |c| "\t#{c}" }.join("\n")
        end
      end

      desc "Generates Sorbet RBI files for serializers"
      task generate_rbi: :environment do
        require_relative "generator"
        require_relative "rbi"
        start_time = Time.zone.now
        print "Generating Sorbet RBI files for serializers..."
        # Load serializers first
        TypeSpecFromSerializers.generate(force: true)
        files = TypeSpecFromSerializers::RBI.generate_for_all_serializers
        puts "completed in #{(Time.zone.now - start_time).round(2)} seconds.\n"
        puts "Generated #{files.size} RBI files:"
        puts files.map { |f| "\t#{f}" }.join("\n")
      end

      desc "Compiles TypeSpec to OpenAPI specification"
      task compile_openapi: :environment do
        require_relative "generator"
        require_relative "openapi_compiler"

        start_time = Time.zone.now
        print "Generating TypeSpec descriptions..."
        TypeSpecFromSerializers.generate(force: true)
        puts "done."

        print "Compiling TypeSpec to OpenAPI..."
        output_path = TypeSpecFromSerializers::OpenAPICompiler.compile
        duration = (Time.zone.now - start_time).round(2)
        puts "completed in #{duration} seconds.\n"
        puts "OpenAPI spec generated at: #{output_path}"
      end
    end
  end
end
