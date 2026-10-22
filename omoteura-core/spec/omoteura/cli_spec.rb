# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"
require "omoteura/cli"

RSpec.describe Omoteura::CLI do
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

  def run_cli(*argv)
    out = StringIO.new
    err = StringIO.new
    status = described_class.new(out: out, err: err).run(argv)
    [status, out.string, err.string]
  end

  def drawing_with_link(link)
    JSON.generate(type: "excalidraw", elements: [
      {id: "box", type: "rectangle", link: link, boundElements: [{type: "text", id: "label"}]},
      {id: "label", type: "text", text: "名前, 表示", containerId: "box"}
    ])
  end

  before do
    write("app/models/user.rb", "class User\n  def display_name\n  end\nend\n")
  end

  describe "check" do
    it "exits 0 and says so when there are no problems" do
      write("ura/app/models/user.excalidraw", drawing_with_link("omoteura:#display_name"))

      expect(run_cli("check", "--root", root)).to eq([0, "Checked 1 diagram and 1 link: no problems.\n", ""])
    end

    it "exits 1 and lists problems as file: message" do
      write("ura/app/models/user.excalidraw", drawing_with_link("omoteura:#full_name"))

      status, out, _err = run_cli("check", "--root", root)

      expect(status).to eq(1)
      expect(out).to eq(<<~TEXT)
        ura/app/models/user.excalidraw: omoteura:#full_name matches nothing in app/models/user.rb (shape "名前, 表示")
        Checked 1 diagram and 1 link: 1 problem.
      TEXT
    end

    it "prints GitHub Actions annotations with escaped values" do
      write("ura/app/models/user.excalidraw", drawing_with_link("omoteura:#full_name"))

      _status, out, _err = run_cli("check", "--root", root, "--format", "github")

      expect(out.lines.first).to eq(
        "::error file=ura/app/models/user.excalidraw,title=omoteura check::" \
        "omoteura:#full_name matches nothing in app/models/user.rb (shape \"名前, 表示\")\n"
      )
    end

    it "exits 2 for invalid settings" do
      write(".omoteura.yml", "diagrams_dir: /abs\n")

      status, _out, err = run_cli("check", "--root", root)

      expect(status).to eq(2)
      expect(err).to eq("omoteura: diagrams_dir must be a relative path, got \"/abs\"\n")
    end

    it "exits 2 for an unknown option" do
      expect(run_cli("check", "--nope")).to eq([2, "", "omoteura: invalid option: --nope\n"])
    end

    it "prints its options with --help" do
      status, out, _err = run_cli("check", "--help")

      expect(status).to eq(0)
      expect(out).to include("Usage: omoteura check [options]", "--root DIR", "--format FORMAT")
    end
  end

  it "prints the version" do
    expect(run_cli("version")).to eq([0, "#{Omoteura::VERSION}\n", ""])
  end

  it "prints usage to stderr and exits 2 without a command" do
    status, _out, err = run_cli

    expect(status).to eq(2)
    expect(err).to start_with("Usage: omoteura <command>")
  end

  it "rejects an unknown command" do
    status, _out, err = run_cli("draw")

    expect(status).to eq(2)
    expect(err).to start_with("omoteura: unknown command 'draw'")
  end

  it "runs as the omoteura executable from the project root" do
    write("ura/app/models/user.excalidraw", drawing_with_link("omoteura:#full_name"))
    exe = File.expand_path("../../exe/omoteura", __dir__)

    out, _err, status = Open3.capture3(RbConfig.ruby, exe, "check", chdir: root)

    expect(status.exitstatus).to eq(1)
    expect(out).to end_with("Checked 1 diagram and 1 link: 1 problem.\n")
  end
end
