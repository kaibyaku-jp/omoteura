# frozen_string_literal: true

require "rspec/core"
require "omoteura/results_file"

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
      FORMAT_VERSION = ResultsFile::FORMAT_VERSION

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
        @examples << example_data(notification.example, "failed", message: exception && ResultsFile.plain(exception.message))
      end

      def example_pending(notification)
        @examples << example_data(notification.example, "pending", message: notification.example.execution_result.pending_message)
      end

      def close(_notification)
        @output.write(ResultsFile.generate(@examples))
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
    end
  end
end
