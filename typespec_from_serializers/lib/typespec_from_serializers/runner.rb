# frozen_string_literal: true

require_relative "io"

# Public: Executes TypeSpec commands, providing conveniences for debugging.
class TypeSpecFromSerializers::Runner
  class MissingExecutableError < StandardError; end

  def initialize(config)
    @config = config
  end

  # Public: Executes TypeSpec with the specified arguments.
  def run(argv, chdir: nil, with_output: nil)
    cmd = command_for(argv)
    opts = {}
    opts[:chdir] = chdir if chdir

    TypeSpecFromSerializers::IO.capture(*cmd, with_output: with_output, **opts)
  rescue Errno::ENOENT => error
    raise MissingExecutableError, "TypeSpec executable not found: #{error.message}"
  end

  private

  attr_reader :config

  # Internal: Returns an Array with the command to run.
  def command_for(args)
    [].tap do |cmd|
      cmd.push(*tsp_executable)
      cmd.push(*args)
    end
  end

  # Internal: Resolves to an executable for TypeSpec.
  def tsp_executable
    local_tsp = config.root.join("node_modules", ".bin", "tsp")
    return [local_tsp.to_s] if local_tsp.exist?

    case config.package_manager
    when "npm"
      %w[npx --yes --package=@typespec/compiler tsp]
    when "pnpm"
      %w[pnpm dlx --package=@typespec/compiler tsp]
    when "bun"
      %w[bunx --bun @typespec/compiler tsp]
    when "yarn"
      %w[yarn dlx --package=@typespec/compiler tsp]
    else
      raise ArgumentError, "Unknown package manager: #{config.package_manager.inspect}"
    end
  end
end
