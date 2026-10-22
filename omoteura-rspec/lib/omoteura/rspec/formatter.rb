# frozen_string_literal: true

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
    class Formatter
      FORMAT_VERSION = 1
      ANSI_ESCAPE = /\e\[[0-9;]*m/

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
        @output.write(JSON.pretty_generate(
          version: FORMAT_VERSION,
          generated_at: Time.now.utc.iso8601,
          summary: summary,
          examples: @examples
        ))
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
