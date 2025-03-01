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
      desc "Generates TypeSpec descriptions for each serializer in the app."
      task generate: :environment do
        require_relative "generator"
        start_time = Time.zone.now
        print "Generating TypeSpec descriptions..."
        serializers = TypeSpecFromSerializers.generate(force: true)
        puts "completed in #{(Time.zone.now - start_time).round(2)} seconds.\n"
        puts "Found #{serializers.size} serializers:"
        puts serializers.map { |s| "\t#{s.name}" }.join("\n")
      end
    end
  end
end
