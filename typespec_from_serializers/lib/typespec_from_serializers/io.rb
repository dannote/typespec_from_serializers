# frozen_string_literal: true

require "open3"

# Public: Builds on top of Ruby I/O open3 providing a friendlier experience.
module TypeSpecFromSerializers::IO
  class << self
    # Internal: A modified version of capture3 that can continuously print stdout.
    def capture(*cmd, with_output: nil, **opts)
      return Open3.capture3(*cmd, **opts) unless with_output

      Open3.popen3(*cmd, **opts) do |stdin, stdout, stderr, wait_threads|
        stdin.close
        out = Thread.new { read_lines(stdout, &with_output) }
        err = Thread.new { read_lines(stderr, &with_output) }
        [out.value, err.value, wait_threads.value]
      end
    end

    # Internal: Reads and yield every line in the stream. Returns the full content.
    def read_lines(io)
      buffer = +""
      while (line = io.gets)
        buffer << line
        yield line if block_given?
      end
      buffer
    end
  end
end
