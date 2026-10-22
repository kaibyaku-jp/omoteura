# frozen_string_literal: true

require "coverage"
require "json"
require "time"
require "rspec/core"

module Omoteura
  module RSpec
    # Writes every example's result as JSON for the editor to color linked
    # shapes with. Use it next to a normal formatter:
    #
    #   --format progress
    #   --format Omoteura::RSpec::Formatter --out tmp/omoteura/results.json
    #
    # RSpec loads this file from the class name by itself, so .rspec needs
    # no --require line.
    #
    # When something already measures coverage, as SimpleCov does, the lines
    # of the project's own code that ran are recorded too, so the editor can
    # tell which methods the tests called. The formatter never starts
    # coverage itself: a coverage tool starting after it would fail.
    class Formatter
      FORMAT_VERSION = 1
      ANSI_ESCAPE = /\e\[[0-9;]*m/
      # Code that is not the project's own, or is the tests themselves.
      NOT_PROJECT_CODE = %r{\A(?:spec|test|vendor|tmp|node_modules)/}

      ::RSpec::Core::Formatters.register self, :example_passed, :example_failed, :example_pending, :close

      def initialize(output)
        @output = output
        @examples = []
      end

      def example_passed(notification)
        @examples << example_data(notification.example, "passed")
      end

      def example_failed(notification)
        exception = notification.example.execution_result.exception
        @examples << example_data(notification.example, "failed", message: exception && plain(exception.message))
      end

      def example_pending(notification)
        @examples << example_data(notification.example, "pending", message: notification.example.execution_result.pending_message)
      end

      def close(_notification)
        data = {version: FORMAT_VERSION, generated_at: Time.now.utc.iso8601, summary: summary, examples: @examples}
        executed = executed_lines
        data[:executed_lines] = executed if executed
        @output.write(JSON.pretty_generate(data))
        @output.write("\n")
      end

      private

      def example_data(example, status, message: nil)
        {
          id: example.id,
          file_path: example.metadata[:file_path].delete_prefix("./"),
          line_number: example.metadata[:line_number],
          full_description: example.full_description,
          status: status,
          message: message
        }
      end

      # Line numbers that ran, by file relative to the working directory, or
      # nil when coverage is not being measured.
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

      def summary
        counts = @examples.map { |e| e[:status] }.tally
        {examples: @examples.size, failures: counts.fetch("failed", 0), pending: counts.fetch("pending", 0)}
      end

      def plain(text)
        text.gsub(ANSI_ESCAPE, "")
      end
    end
  end
end
