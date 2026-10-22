# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Inspector do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  attr_reader :root

  def write(path, content)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def drawing(*shapes)
    JSON.generate(type: "excalidraw", elements: shapes.map { |id, link| {id: id, type: "text", text: id, link: link} })
  end

  def results(*examples)
    Omoteura::TestResults.new(examples.map do |line, status|
      Omoteura::TestResults::Example.new(file_path: "spec/models/user_spec.rb", line_number: line,
        full_description: "User line #{line}", status: status, message: nil)
    end)
  end

  def report(path, results: Omoteura::TestResults.new([]))
    described_class.new(Omoteura::Config.load(root), results: results).report(path)
  end

  before do
    write("spec/models/user_spec.rb", <<~RUBY)
      RSpec.describe User do
        describe "validations" do
          it "requires a name" do
          end

          it "keeps emails unique" do
          end
        end
      end
    RUBY
  end

  it "reports a file without a diagram" do
    expect(report("spec/models/user_spec.rb"))
      .to eq(version: 1, code_path: "spec/models/user_spec.rb", attachment: nil, shapes: [], error: nil)
  end

  it "reports linked shapes with their targets and test results" do
    write("ura/spec/models/user_spec.excalidraw", drawing(
      ["name", "omoteura:#requires a name"],
      ["all", "omoteura:#validations"],
      ["memo", nil]
    ))

    data = report("spec/models/user_spec.rb", results: results([3, "passed"], [6, "failed"]))

    expect(data[:attachment]).to eq(diagram_path: "ura/spec/models/user_spec.excalidraw", source: "convention", missing: false)
    expect(data[:shapes].map { |s| [s[:id], s[:target], s[:test]&.fetch(:status)] }).to eq([
      ["name", {path: "spec/models/user_spec.rb", start_line: 3, end_line: 4}, "passed"],
      ["all", {path: "spec/models/user_spec.rb", start_line: 2, end_line: 8}, "failed"]
    ])
    expect(data[:shapes].first[:test][:examples]).to eq([
      {line_number: 3, full_description: "User line 3", status: "passed", message: nil}
    ])
  end

  it "reports a broken link in the shape" do
    write("ura/spec/models/user_spec.excalidraw", drawing(["gone", "omoteura:#was renamed"]))

    shape = report("spec/models/user_spec.rb")[:shapes].first

    expect(shape).to include(target: nil, test: nil, error: "omoteura:#was renamed matches nothing in spec/models/user_spec.rb")
  end

  it "reports a missing explicit diagram" do
    write("app/models/user.rb", "# omoteura: ura/shared/user.excalidraw\nclass User; end\n")

    expect(report("app/models/user.rb")[:attachment]).to eq(diagram_path: "ura/shared/user.excalidraw", source: "magic_comment", missing: true)
  end

  it "reports an unreadable diagram as an error" do
    write("ura/spec/models/user_spec.excalidraw", "{")

    expect(report("spec/models/user_spec.rb")[:error]).to start_with("ura/spec/models/user_spec.excalidraw has invalid drawing JSON")
  end

  it "accepts an absolute path inside the root" do
    expect(report(File.join(root, "spec/models/user_spec.rb"))[:code_path]).to eq("spec/models/user_spec.rb")
  end

  it "refuses a file outside the project" do
    expect { report("../elsewhere.rb") }.to raise_error(ArgumentError, "../elsewhere.rb is outside the project")
  end
end
