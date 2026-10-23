# frozen_string_literal: true

require "fileutils"
require "minitest"
require "omoteura/results_file"

module Omoteura
  module Minitest
    # Writes every test's result to the results file, located by the line
    # the test starts on: the test "…" call, or def test_…. With parallel
    # tests, Minitest hands the workers' results to this reporter in the
    # main process, which writes the file once at the end.
    class Reporter < ::Minitest::AbstractReporter
      def initialize(path)
        super()
        @path = path
        @examples = []
        @lock = Mutex.new
      end

      def record(result)
        file, line = result.source_location
        return unless file && line&.positive?

        example = {
          id: "#{result.klass}##{result.name}",
          file_path: relative(file),
          line_number: line,
          full_description: "#{result.klass} #{description(result.name)}",
          status: status(result),
          message: message(result)
        }
        @lock.synchronize { @examples << example }
      end

      def report
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, ResultsFile.generate(@examples))
      end

      private

      def relative(file)
        path = File.expand_path(file)
        root = File.join(Dir.pwd, "")
        path.start_with?(root) ? path.delete_prefix(root) : path
      end

      # test_requires_an_email, as ActiveSupport names test "requires an
      # email", reads as the description it came from.
      def description(name)
        name.delete_prefix("test_").tr("_", " ")
      end

      def status(result)
        if result.skipped? then "pending"
        elsif result.passed? then "passed"
        else "failed"
        end
      end

      def message(result)
        failure = result.failures.first
        failure && ResultsFile.plain(failure.message)
      end
    end
  end
end
