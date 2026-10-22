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

  describe "inspect" do
    it "prints the editor data for a file as JSON" do
      write("ura/app/models/user.excalidraw", drawing_with_link("omoteura:#display_name"))
      write("tmp/omoteura/results.json", JSON.generate(version: 1, examples: []))

      status, out, err = run_cli("inspect", File.join(root, "app/models/user.rb"), "--root", root)
      data = JSON.parse(out)

      expect([status, err]).to eq([0, ""])
      expect(data["attachment"]["diagram_path"]).to eq("ura/app/models/user.excalidraw")
      expect(data["shapes"].first["target"]).to eq("path" => "app/models/user.rb", "start_line" => 2, "end_line" => 3)
    end

    it "exits 2 without exactly one file" do
      expect(run_cli("inspect", "--root", root)).to eq([2, "", "omoteura: invalid argument: expected exactly one FILE\n"])
    end

    it "exits 2 for a file that does not exist" do
      status, _out, err = run_cli("inspect", File.join(root, "app/models/post.rb"), "--root", root)

      expect(status).to eq(2)
      expect(err).to end_with("app/models/post.rb is not a file\n")
    end

    it "exits 2 for a file outside the root" do
      Dir.mktmpdir do |elsewhere|
        File.write(File.join(elsewhere, "x.rb"), "")

        status, _out, err = run_cli("inspect", File.join(elsewhere, "x.rb"), "--root", root)

        expect(status).to eq(2)
        expect(err).to include("is outside #{root}")
      end
    end

    it "exits 2 for a results file it cannot read" do
      write("tmp/omoteura/results.json", "{")

      status, _out, err = run_cli("inspect", File.join(root, "app/models/user.rb"), "--root", root)

      expect(status).to eq(2)
      expect(err).to include("is not valid JSON")
    end
  end

  describe "diagram" do
    it "prints the editor data for a diagram as JSON" do
      write("ura/app/models/user.excalidraw", drawing_with_link("omoteura:#display_name"))

      status, out, err = run_cli("diagram", File.join(root, "ura/app/models/user.excalidraw"), "--root", root)
      data = JSON.parse(out)

      expect([status, err]).to eq([0, ""])
      expect(data["attached_to"]).to eq(["app/models/user.rb"])
      expect(data["scene"]["elements"].size).to eq(2)
      expect(data["shapes"].first["target"]).to eq("path" => "app/models/user.rb", "start_line" => 2, "end_line" => 3)
    end
  end

  describe "draft" do
    it "writes a draft for each file and glob match and says where" do
      write("app/models/post.rb", "class Post\n  def title\n  end\nend\n")

      status, out, err = run_cli("draft", "app/models/*.rb", "--root", root)

      expect([status, err]).to eq([0, ""])
      expect(out).to eq(<<~TEXT)
        wrote ura/app/models/post.excalidraw (1 shape)
        wrote ura/app/models/user.excalidraw (1 shape)
      TEXT
      expect(File).to exist(File.join(root, "ura/app/models/post.excalidraw"))
    end

    it "says what it would write on a dry run" do
      expect(run_cli("draft", "app/models/user.rb", "--root", root, "--dry-run"))
        .to eq([0, "would write ura/app/models/user.excalidraw (1 shape)\n", ""])
    end

    it "explains why it skipped a file" do
      write("lib/constants.rb", "LIMIT = 10\n")

      expect(run_cli("draft", "lib/constants.rb", "--root", root)).to eq([0, "skipped lib/constants.rb: nothing to draw\n", ""])
    end

    it "exits 2 for a glob that matches nothing" do
      expect(run_cli("draft", "app/nothing/*.rb", "--root", root)).to eq([2, "", "omoteura: invalid argument: app/nothing/*.rb matches no files\n"])
    end

    it "writes an Obsidian note with --format md" do
      expect(run_cli("draft", "app/models/user.rb", "--root", root, "--format", "md"))
        .to eq([0, "wrote ura/app/models/user.excalidraw.md (1 shape)\n", ""])
      expect(Omoteura::Diagram.load(File.join(root, "ura/app/models/user.excalidraw.md")).format).to eq(:obsidian)
    end

    it "exits 2 when --out names a file of the other format" do
      status, _out, err = run_cli("draft", "app/models/user.rb", "--root", root, "--format", "md", "--out", "x.excalidraw")

      expect(status).to eq(2)
      expect(err).to include("--out x.excalidraw does not end in .excalidraw.md, as --format md writes")
    end

    it "exits 2 for an unknown kind in --only" do
      status, _out, err = run_cli("draft", "app/models/user.rb", "--root", root, "--only", "methods,routes")

      expect(status).to eq(2)
      expect(err).to include("--only does not know routes")
    end

    it "exits 2 when --out names one file for several" do
      write("app/models/post.rb", "class Post\n  def title\n  end\nend\n")

      status, _out, err = run_cli("draft", "app/models/*.rb", "--root", root, "--out", "x.excalidraw")

      expect(status).to eq(2)
      expect(err).to include("--out names one file, but 2 files match")
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
