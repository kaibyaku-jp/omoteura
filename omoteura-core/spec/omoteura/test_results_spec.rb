# frozen_string_literal: true

require "json"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::TestResults do
  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, "results.json")
      example.run
    end
  end

  attr_reader :path

  def write_results(examples, version: 1)
    File.write(path, JSON.generate(version: version, examples: examples))
  end

  def example_data(line, status, message = nil)
    {file_path: "spec/models/user_spec.rb", line_number: line, full_description: "User #{line}", status: status, message: message}
  end

  def target(start_line, end_line, path: "spec/models/user_spec.rb")
    Omoteura::LinkResolver::Target.new(path: path, start_line: start_line, end_line: end_line)
  end

  before do
    write_results([example_data(3, "passed"), example_data(7, "failed", "boom"), example_data(11, "pending"), example_data(15, "passed")])
  end

  describe "#summary_for" do
    subject(:results) { described_class.load(path) }

    it "passes when every example in the range passed" do
      summary = results.summary_for(target(14, 16))

      expect(summary.status).to eq("passed")
      expect(summary.examples.map(&:line_number)).to eq([15])
    end

    it "fails when any example in the range failed" do
      expect(results.summary_for(target(1, 20)).status).to eq("failed")
    end

    it "is pending when an example is pending and none failed" do
      expect(results.summary_for(target(10, 16)).status).to eq("pending")
    end

    it "returns nil when no example is in the range" do
      expect(results.summary_for(target(4, 6))).to be_nil
    end

    it "only counts examples in the target's file" do
      expect(results.summary_for(target(1, 20, path: "spec/models/post_spec.rb"))).to be_nil
    end
  end

  describe "#executed?" do
    it "tells whether any of the lines ran, from the executed lines in the file" do
      File.write(path, JSON.generate(version: 1, examples: [], executed_lines: {"app/models/user.rb" => [1, 3]}))
      results = described_class.load(path)

      expect(results.executed?("app/models/user.rb", 2..3)).to be(true)
      expect(results.executed?("app/models/user.rb", 4..5)).to be(false)
      expect(results.executed?("app/models/post.rb", 1..2)).to be_nil
    end

    it "cannot tell when the run did not measure coverage" do
      File.write(path, JSON.generate(version: 1, examples: []))

      expect(described_class.load(path).executed?("app/models/user.rb", 1..2)).to be_nil
    end
  end

  describe ".load" do
    it "returns empty results when the file does not exist" do
      expect(described_class.load(File.join(File.dirname(path), "missing.json")).examples).to eq([])
    end

    it "rejects another format version" do
      write_results([], version: 2)

      expect { described_class.load(path) }.to raise_error(described_class::Invalid, /not an Omoteura results file of version 1/)
    end

    it "rejects invalid JSON" do
      File.write(path, "{")

      expect { described_class.load(path) }.to raise_error(described_class::Invalid, /not valid JSON/)
    end
  end
end
