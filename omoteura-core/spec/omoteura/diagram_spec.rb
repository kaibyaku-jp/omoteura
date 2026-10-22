# frozen_string_literal: true

require "tmpdir"

require "omoteura/core"

RSpec.describe Omoteura::Diagram do
  def fixture(name)
    File.expand_path("../fixtures/diagrams/#{name}", __dir__)
  end

  shared_examples "the user drawing" do |name, format|
    subject(:diagram) { described_class.load(fixture(name)) }

    it "reads it as #{format}" do
      expect(diagram.format).to eq(format)
    end

    it "skips deleted elements" do
      expect(diagram.elements.map(&:id)).not_to include("Removed1")
    end

    it "labels containers with their bound text" do
      expect(diagram.elements.find { |e| e.id == "EmailBox" }.label).to eq("email 一意 🔑")
    end

    it "keeps the whole scene, deleted elements included, for showing the drawing" do
      expect(diagram.scene.keys).to eq(%w[elements appState files])
      expect(diagram.scene["elements"].map { |e| e["id"] }).to include("Removed1")
      expect(diagram.scene["appState"]).to eq("viewBackgroundColor" => "#ffffff")
    end

    it "returns only elements with omoteura: links as linked elements" do
      expect(diagram.linked_elements.map { |e| [e.id, e.link] })
        .to eq([["EmailBox", "omoteura:#email 一意であること"]])
    end
  end

  it_behaves_like "the user drawing", "user.excalidraw", :excalidraw
  it_behaves_like "the user drawing", "user.excalidraw.md", :obsidian
  it_behaves_like "the user drawing", "user_compressed.excalidraw.md", :obsidian
  it_behaves_like "the user drawing", "obsidian_without_suffix.md", :obsidian

  describe ".diagram_file?" do
    it "accepts markdown with excalidraw-plugin frontmatter whatever its name" do
      expect(described_class.diagram_file?(fixture("obsidian_without_suffix.md"))).to be(true)
    end

    it "rejects markdown without excalidraw-plugin frontmatter" do
      expect(described_class.diagram_file?(fixture("note.md"))).to be(false)
    end

    it "rejects missing files" do
      expect(described_class.diagram_file?(fixture("missing.excalidraw"))).to be(false)
    end
  end

  describe ".load" do
    it "raises NotADiagram for plain markdown" do
      expect { described_class.load(fixture("note.md")) }.to raise_error(described_class::NotADiagram)
    end

    it "raises ParseError when the drawing block is missing" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "broken.excalidraw.md")
        File.write(path, "---\nexcalidraw-plugin: parsed\n---\n# Excalidraw Data\n")

        expect { described_class.load(path) }.to raise_error(described_class::ParseError, /no ## Drawing block/)
      end
    end

    it "raises ParseError for invalid JSON" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "broken.excalidraw")
        File.write(path, "{")

        expect { described_class.load(path) }.to raise_error(described_class::ParseError, /invalid drawing JSON/)
      end
    end
  end
end
