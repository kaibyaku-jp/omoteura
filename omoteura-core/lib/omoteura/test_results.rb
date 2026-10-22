# frozen_string_literal: true

require "json"

module Omoteura
  # Test results written by Omoteura::RSpec::Formatter.
  class TestResults
    class Invalid < Error; end

    DEFAULT_PATH = "tmp/omoteura/results.json"
    SUPPORTED_VERSION = 1

    Example = Data.define(:file_path, :line_number, :full_description, :status, :message)

    # Combined status of the examples behind one shape: any failure fails
    # the shape, then any pending example makes it pending.
    Summary = Data.define(:status, :examples) do
      def self.of(examples)
        statuses = examples.map(&:status)
        status =
          if statuses.include?("failed") then "failed"
          elsif statuses.include?("pending") then "pending"
          else "passed"
          end
        new(status: status, examples: examples)
      end
    end

    attr_reader :examples

    # Returns empty results when the file does not exist yet, so diagrams
    # still work before the first test run.
    def self.load(path)
      return new([]) unless File.file?(path)

      data = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
      unless data.is_a?(Hash) && data["version"] == SUPPORTED_VERSION && data["examples"].is_a?(Array)
        raise Invalid, "#{path} is not an Omoteura results file of version #{SUPPORTED_VERSION}"
      end

      examples = data["examples"].map do |e|
        Example.new(file_path: e["file_path"], line_number: e["line_number"], full_description: e["full_description"],
          status: e["status"], message: e["message"])
      end
      executed = data["executed_lines"]
      new(examples, executed_lines: executed.is_a?(Hash) ? executed : nil)
    rescue JSON::ParserError => e
      raise Invalid, "#{path} is not valid JSON: #{e.message}"
    end

    # executed_lines maps files to the line numbers that ran during the
    # tests, when the run measured coverage; nil when it did not.
    def initialize(examples, executed_lines: nil)
      @examples = examples
      @executed_lines = executed_lines&.transform_values { |lines| lines.to_h { |line| [line, true] } }
    end

    # Whether code between the lines ran, or nil when nothing says: the run
    # did not measure coverage, or did not load the file.
    def executed?(path, lines)
      executed = @executed_lines&.[](path) or return nil
      lines.any? { |line| executed[line] }
    end

    # Summarizes the examples defined within the lines of a link target,
    # or returns nil when no recorded example is there.
    def summary_for(target)
      matching = examples.select do |e|
        e.file_path == target.path && (target.start_line..target.end_line).cover?(e.line_number)
      end
      matching.empty? ? nil : Summary.of(matching)
    end
  end
end
