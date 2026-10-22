# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Config do
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

  describe ".load" do
    it "uses ura as the diagrams directory when there is no config file" do
      config = described_class.load(root)

      expect(config.diagrams_dir).to eq("ura")
      expect(config.attach).to eq({})
    end

    it "reads .omoteura.yml" do
      write(".omoteura.yml", <<~YAML)
        diagrams_dir: docs/ura
        attach:
          app/models/user.rb: ura/shared/user.excalidraw.md
      YAML

      config = described_class.load(root)

      expect(config.diagrams_dir).to eq("docs/ura")
      expect(config.attach).to eq("app/models/user.rb" => "ura/shared/user.excalidraw.md")
    end

    it "lets .omoteura.local.yml add and override individual attach entries" do
      write(".omoteura.yml", <<~YAML)
        attach:
          app/models/user.rb: ura/shared/user.excalidraw.md
          app/models/post.rb: ura/shared/post.excalidraw.md
      YAML
      write(".omoteura.local.yml", <<~YAML)
        attach:
          app/models/user.rb: notes/user.excalidraw.md
          app/models/team.rb: ura/mine/team.excalidraw
      YAML

      expect(described_class.load(root).attach).to eq(
        "app/models/user.rb" => "notes/user.excalidraw.md",
        "app/models/post.rb" => "ura/shared/post.excalidraw.md",
        "app/models/team.rb" => "ura/mine/team.excalidraw"
      )
    end

    it "rejects a file that is not a mapping" do
      write(".omoteura.yml", "- ura\n")

      expect { described_class.load(root) }.to raise_error(described_class::Invalid, /must be a mapping/)
    end

    it "rejects invalid YAML" do
      write(".omoteura.yml", "attach: [\n")

      expect { described_class.load(root) }.to raise_error(described_class::Invalid, /not valid YAML/)
    end

    it "rejects YAML that needs unsafe classes" do
      write(".omoteura.yml", "diagrams_dir: !ruby/object:Object {}\n")

      expect { described_class.load(root) }.to raise_error(described_class::Invalid, /not valid YAML/)
    end

    it "rejects an absolute diagrams_dir" do
      write(".omoteura.yml", "diagrams_dir: /tmp/ura\n")

      expect { described_class.load(root) }.to raise_error(described_class::Invalid, /diagrams_dir must be a relative path/)
    end

    it "rejects attach that is not a mapping" do
      write(".omoteura.yml", "attach: ura/user.excalidraw.md\n")

      expect { described_class.load(root) }.to raise_error(described_class::Invalid, /attach must be a mapping/)
    end
  end

  describe "#expand" do
    subject(:config) { described_class.new(root: root) }

    it "expands a path relative to the root" do
      expect(config.expand("ura/app/models/user.excalidraw.md"))
        .to eq(File.join(root, "ura/app/models/user.excalidraw.md"))
    end

    it "returns nil for a path that leaves the root" do
      expect(config.expand("../secrets.excalidraw")).to be_nil
      expect(config.expand("/etc/passwd")).to be_nil
    end

    it "returns nil for a symlink that points outside the root" do
      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "secret.excalidraw"), "{}")
        File.symlink(File.join(outside, "secret.excalidraw"), File.join(root, "link.excalidraw"))

        expect(config.expand("link.excalidraw")).to be_nil
      end
    end
  end
end
