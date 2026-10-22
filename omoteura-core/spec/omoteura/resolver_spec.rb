# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Resolver do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  attr_reader :root

  subject(:resolver) { described_class.new(Omoteura::Config.load(root)) }

  def write(path, content = "")
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def attachment(code_path, diagram_path, source, missing: false)
    described_class::Attachment.new(code_path: code_path, diagram_path: diagram_path, source: source, missing: missing)
  end

  describe "#resolve" do
    before { write("app/models/user.rb", "class User; end\n") }

    it "returns nil when nothing is attached" do
      expect(resolver.resolve("app/models/user.rb")).to be_nil
    end

    context "with the path convention" do
      it "finds <diagrams_dir>/<code path>.excalidraw.md" do
        write("ura/app/models/user.excalidraw.md")

        expect(resolver.resolve("app/models/user.rb"))
          .to eq(attachment("app/models/user.rb", "ura/app/models/user.excalidraw.md", :convention))
      end

      it "finds <diagrams_dir>/<code path>.excalidraw" do
        write("ura/app/models/user.excalidraw")

        expect(resolver.resolve("app/models/user.rb").diagram_path).to eq("ura/app/models/user.excalidraw")
      end

      it "prefers .excalidraw.md when both exist" do
        write("ura/app/models/user.excalidraw.md")
        write("ura/app/models/user.excalidraw")

        expect(resolver.resolve("app/models/user.rb").diagram_path).to eq("ura/app/models/user.excalidraw.md")
      end

      it "uses diagrams_dir from the config" do
        write(".omoteura.yml", "diagrams_dir: docs/ura\n")
        write("docs/ura/app/models/user.excalidraw")

        expect(resolver.resolve("app/models/user.rb").diagram_path).to eq("docs/ura/app/models/user.excalidraw")
      end

      it "accepts an absolute code path inside the root" do
        write("ura/app/models/user.excalidraw")

        expect(resolver.resolve(File.join(root, "app/models/user.rb")).code_path).to eq("app/models/user.rb")
      end
    end

    context "with the attach setting" do
      before { write(".omoteura.yml", "attach:\n  app/models/user.rb: ura/shared/user.excalidraw.md\n") }

      it "takes priority over the convention" do
        write("ura/app/models/user.excalidraw.md")
        write("ura/shared/user.excalidraw.md")

        expect(resolver.resolve("app/models/user.rb"))
          .to eq(attachment("app/models/user.rb", "ura/shared/user.excalidraw.md", :config))
      end

      it "reports a missing diagram instead of falling back to the convention" do
        write("ura/app/models/user.excalidraw.md")

        expect(resolver.resolve("app/models/user.rb"))
          .to eq(attachment("app/models/user.rb", "ura/shared/user.excalidraw.md", :config, missing: true))
      end
    end

    context "with a magic comment" do
      it "takes priority over the attach setting" do
        write(".omoteura.yml", "attach:\n  app/models/user.rb: ura/shared/from-config.excalidraw\n")
        write("ura/shared/from-config.excalidraw")
        write("ura/shared/from-comment.excalidraw")
        write("app/models/user.rb", "class User; end\n\n# omoteura: ura/shared/from-comment.excalidraw\n")

        expect(resolver.resolve("app/models/user.rb"))
          .to eq(attachment("app/models/user.rb", "ura/shared/from-comment.excalidraw", :magic_comment))
      end

      it "adds .md to a path copied from Obsidian" do
        write("ura/Drawing 2026-10-22 12.26.15.excalidraw.md")
        write("app/models/user.rb", "# omoteura: ura/Drawing 2026-10-22 12.26.15.excalidraw\nclass User; end\n")

        expect(resolver.resolve("app/models/user.rb").diagram_path).to eq("ura/Drawing 2026-10-22 12.26.15.excalidraw.md")
      end

      it "keeps the written path when it exists, even if <path>.md also exists" do
        write("ura/user.excalidraw")
        write("ura/user.excalidraw.md")
        write("app/models/user.rb", "# omoteura: ura/user.excalidraw\nclass User; end\n")

        expect(resolver.resolve("app/models/user.rb").diagram_path).to eq("ura/user.excalidraw")
      end

      it "reports a missing diagram" do
        write("app/models/user.rb", "# omoteura: ura/nowhere.excalidraw\nclass User; end\n")

        expect(resolver.resolve("app/models/user.rb")).to be_missing
      end

      it "refuses a diagram outside the project" do
        write("app/models/user.rb", "# omoteura: ../outside.excalidraw\nclass User; end\n")

        expect { resolver.resolve("app/models/user.rb") }
          .to raise_error(described_class::InvalidPath, "app/models/user.rb attaches ../outside.excalidraw, which is outside the project")
      end
    end

    it "returns nil for a code file outside the root" do
      expect(resolver.resolve("../elsewhere.rb")).to be_nil
    end
  end
end
