# frozen_string_literal: true

require "coverage"
require "json"
require "time"

module Omoteura
  # Builds the test results file that the RSpec formatter and the Minitest
  # reporter write and TestResults reads. Loaded on its own by those, so it
  # requires nothing else of Omoteura.
  module ResultsFile
    FORMAT_VERSION = 1
    DEFAULT_PATH = "tmp/omoteura/results.json"
    ANSI_ESCAPE = /\e\[[0-9;]*m/
    # Code that is not the project's own, or is the tests themselves.
    NOT_PROJECT_CODE = %r{\A(?:spec|test|vendor|tmp|node_modules)/}

    module_function

    # examples are Hashes with :id, :file_path, :line_number,
    # :full_description, :status ("passed", "failed" or "pending") and
    # :message.
    def generate(examples)
      counts = examples.map { |e| e[:status] }.tally
      data = {
        version: FORMAT_VERSION,
        generated_at: Time.now.utc.iso8601,
        summary: {examples: examples.size, failures: counts.fetch("failed", 0), pending: counts.fetch("pending", 0)},
        examples: examples
      }
      executed = executed_lines
      data[:executed_lines] = executed if executed
      JSON.pretty_generate(data) + "\n"
    end

    # A message as a terminal would show it, without the colors.
    def plain(text)
      text&.gsub(ANSI_ESCAPE, "")
    end

    # Line numbers that ran, by file relative to the working directory, or
    # nil when coverage is not being measured. Something else, such as
    # SimpleCov, must have started it: a coverage tool starting after the
    # test framework's integration would fail.
    def executed_lines
      return nil unless ::Coverage.running?

      root = File.join(Dir.pwd, "")
      ::Coverage.peek_result.each_with_object({}) do |(path, counts), executed|
        next unless path.start_with?(root) && path.end_with?(".rb")

        relative = path.delete_prefix(root)
        next if relative.match?(NOT_PROJECT_CODE)

        # Hash for Coverage.start(lines: true), as SimpleCov uses; an
        # Array of line counts for the older Coverage.start.
        lines = counts.is_a?(Hash) ? counts[:lines] : counts
        next unless lines

        executed[relative] = lines.each_index.select { |i| lines[i]&.positive? }.map { |i| i + 1 }
      end
    end
  end
end
