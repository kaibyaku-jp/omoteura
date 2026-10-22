# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"

# Runs RSpec in a separate process on a small project set up the way the
# manual describes, so the test covers how RSpec finds and loads the
# formatter from .rspec alone.
RSpec.describe "Omoteura::RSpec::Formatter" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  def run_rspec
    File.write(File.join(root, ".rspec"), <<~OPTIONS)
      --format progress
      --format Omoteura::RSpec::Formatter --out tmp/omoteura/results.json
    OPTIONS
    rspec = Gem.bin_path("rspec-core", "rspec")
    _out, err, status = Open3.capture3(RbConfig.ruby, rspec, chdir: root)
    expect(err).to eq("")
    [status, JSON.parse(File.read(File.join(root, "tmp/omoteura/results.json")))]
  end

  before do
    FileUtils.mkdir_p(File.join(root, "spec/models"))
    File.write(File.join(root, "spec/models/user_spec.rb"), <<~RUBY)
      RSpec.describe "User" do
        describe "validations" do
          it "requires a name" do
            expect(1).to eq(1)
          end

          it "keeps emails unique" do
            expect("dup").to eq("unique")
          end

          it "limits the name length" do
            pending "not written yet"
            raise "boom"
          end
        end
      end
    RUBY
  end

  it "writes every example's result to the --out path from .rspec" do
    status, results = run_rspec

    expect(status.exitstatus).to eq(1)
    expect(results["version"]).to eq(1)
    expect(results["summary"]).to eq("examples" => 3, "failures" => 1, "pending" => 1)
    expect(results["examples"].map { |e| e.slice("file_path", "line_number", "full_description", "status") }).to eq([
      {"file_path" => "spec/models/user_spec.rb", "line_number" => 3, "full_description" => "User validations requires a name", "status" => "passed"},
      {"file_path" => "spec/models/user_spec.rb", "line_number" => 7, "full_description" => "User validations keeps emails unique", "status" => "failed"},
      {"file_path" => "spec/models/user_spec.rb", "line_number" => 11, "full_description" => "User validations limits the name length", "status" => "pending"}
    ])
  end

  it "includes the failure message without terminal colors" do
    _status, results = run_rspec
    failed = results["examples"].find { |e| e["status"] == "failed" }

    expect(failed["message"]).to include('expected: "unique"')
    expect(failed["message"]).not_to match(/\e\[/)
  end

  it "includes the pending reason" do
    _status, results = run_rspec

    expect(results["examples"].find { |e| e["status"] == "pending" }["message"]).to eq("not written yet")
  end

  it "uses ids that RSpec accepts for reruns" do
    _status, results = run_rspec

    expect(results["examples"].map { |e| e["id"] }).to eq([
      "./spec/models/user_spec.rb[1:1:1]",
      "./spec/models/user_spec.rb[1:1:2]",
      "./spec/models/user_spec.rb[1:1:3]"
    ])
  end
end
