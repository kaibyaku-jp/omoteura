# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# Walks through what a user does, in a copy of spec/fixtures/sample_project:
# run RSpec with the formatter, then ask omoteura to check the project and
# to describe a file for the editor. Every command runs in its own process
# from the project directory, as it would in a real project.
RSpec.describe "A sample project" do
  around do |example|
    Dir.mktmpdir do |dir|
      @project = File.join(dir, "sample_project")
      FileUtils.cp_r(File.expand_path("../fixtures/sample_project", __dir__), @project)
      example.run
    end
  end

  attr_reader :project

  def run(*command)
    Open3.capture3(RbConfig.ruby, *command, chdir: project)
  end

  def run_rspec
    run(Gem.bin_path("rspec-core", "rspec"))
  end

  def run_omoteura(*args)
    run(File.expand_path("../../omoteura-core/exe/omoteura", __dir__), *args)
  end

  it "records test results for the formatter configured in .rspec" do
    out, _err, status = run_rspec

    expect(out).to include("3 examples, 1 failure")
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(File.read(File.join(project, "tmp/omoteura/results.json")))["summary"])
      .to eq("examples" => 3, "failures" => 1, "pending" => 0)
  end

  it "passes omoteura check" do
    out, err, status = run_omoteura("check")

    expect([out, err, status.exitstatus]).to eq(["Checked 2 diagrams and 4 links: no problems.\n", "", 0])
  end

  it "describes a spec file with its diagram, links and test results" do
    run_rspec
    out, err, status = run_omoteura("inspect", "spec/models/user_spec.rb")
    data = JSON.parse(out)

    expect([err, status.exitstatus]).to eq(["", 0])
    expect(data["attachment"]).to eq("diagram_path" => "ura/spec/models/user_spec.excalidraw.md", "source" => "convention", "missing" => false)
    expect(data["shapes"].map { |s| [s["label"], s["target"], s.dig("test", "status")] }).to eq([
      ["email 必須", {"path" => "spec/models/user_spec.rb", "start_line" => 7, "end_line" => 9}, "passed"],
      ["表示名", {"path" => "spec/models/user_spec.rb", "start_line" => 12, "end_line" => 21}, "failed"]
    ])
  end

  it "links an application diagram to methods" do
    out, _err, _status = run_omoteura("inspect", "app/models/user.rb")

    expect(JSON.parse(out)["shapes"].map { |s| [s["label"], s["target"]] }).to eq([
      ["email が必須", {"path" => "app/models/user.rb", "start_line" => 11, "end_line" => 13}],
      ["表示名", {"path" => "app/models/user.rb", "start_line" => 15, "end_line" => 17}]
    ])
  end

  it "reports the link a renamed spec breaks" do
    spec = File.join(project, "spec/models/user_spec.rb")
    File.write(spec, File.read(spec).sub("requires an email", "needs an email"))

    out, _err, status = run_omoteura("check")

    expect(status.exitstatus).to eq(1)
    expect(out).to eq(<<~TEXT)
      ura/spec/models/user_spec.excalidraw.md: omoteura:#requires an email matches nothing in spec/models/user_spec.rb (shape "email 必須")
      Checked 2 diagrams and 4 links: 1 problem.
    TEXT
  end
end
