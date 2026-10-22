# frozen_string_literal: true

require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Obsidian do
  def fixture(name)
    File.read(File.expand_path("../fixtures/diagrams/#{name}", __dir__))
  end

  def scene_of(source)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "drawing.excalidraw.md")
      File.write(path, source)
      Omoteura::Diagram.load(path)
    end
  end

  # The whole saved scene, type, version and source included.
  def saved_scene(source)
    json = source[/```json\n(.*)\n```/m, 1] || Omoteura::LZString.decompress_from_base64(source[/```compressed-json\n(.*)\n```/m, 1])
    JSON.parse(json)
  end

  let(:scene) do
    {
      "type" => "excalidraw",
      "version" => 2,
      "source" => "https://github.com/kaibyaku-jp/omoteura",
      "elements" => [
        {"id" => "Box00001", "type" => "rectangle", "isDeleted" => false, "link" => "omoteura:#requires an email"},
        {"id" => "Label001", "type" => "text", "isDeleted" => false, "link" => nil, "text" => "email\n必須",
         "originalText" => "email 必須", "containerId" => "Box00001"},
        {"id" => "Note0001", "type" => "text", "isDeleted" => false, "link" => "https://example.com", "text" => "メモ",
         "originalText" => "メモ", "containerId" => nil},
        {"id" => "Gone0001", "type" => "text", "isDeleted" => true, "link" => nil, "text" => "消した", "originalText" => "消した"},
        {"id" => "a-long-excalidraw-id", "type" => "text", "isDeleted" => false, "link" => "omoteura:#x", "text" => "x", "originalText" => "x"}
      ],
      "appState" => {"viewBackgroundColor" => "#ffffff"},
      "files" => {}
    }
  end

  describe ".render" do
    it "lists text and links above the drawing as the plugin does" do
      markdown = described_class.render(scene, compress: false)

      expect(markdown).to start_with(described_class::HEADER)
      expect(markdown.delete_prefix(described_class::HEADER)[/\A.*?(?=```json)/m]).to eq(<<~MARKDOWN)
        # Excalidraw Data

        ## Text Elements
        email 必須 ^Label001

        メモ ^Note0001

        ## Element Links
        Box00001: omoteura:#requires an email

        Note0001: https://example.com

        %%
        ## Drawing
      MARKDOWN
    end

    it "writes a drawing that reads back as the same scene, compressed or not" do
      [true, false].each do |compress|
        diagram = scene_of(described_class.render(scene, compress: compress))

        expect(diagram.format).to eq(:obsidian)
        expect(diagram.scene["elements"]).to eq(scene["elements"])
        expect(diagram.linked_elements.map(&:id)).to eq(%w[Box00001 a-long-excalidraw-id])
      end
    end

    it "splits compressed data into lines of 256 characters with blank lines between" do
      big = scene.merge("elements" => scene["elements"] * 40)
      lines = described_class.render(big)[/```compressed-json\n(.*)\n```/m, 1].split("\n\n")

      expect(lines.size).to be > 1
      expect(lines[0..-2].map(&:size).uniq).to eq([256])
    end
  end

  describe ".rewrite" do
    %w[user.excalidraw.md user_compressed.excalidraw.md].each do |name|
      it "gives back #{name} exactly as the plugin saved it when nothing changed" do
        source = fixture(name)

        expect(described_class.rewrite(source, saved_scene(source))).to eq(source)
      end
    end

    it "keeps what the user wrote above the drawing, the compression and embedded files" do
      source = fixture("user_compressed.excalidraw.md").sub("# Excalidraw Data", "# 背景\n\nなぜこの順で検証するか。\n\n# Excalidraw Data")
        .sub("%%\n## Drawing", "## Embedded Files\n0123456789abcdef0123456789abcdef01234567: [[diagram.png]]\n\n%%\n## Drawing")

      rewritten = described_class.rewrite(source, scene)

      expect(rewritten).to start_with(source[/\A.*なぜこの順で検証するか。\n\n/m])
      expect(rewritten).to include("```compressed-json\n")
      expect(rewritten).to include("## Embedded Files\n0123456789abcdef0123456789abcdef01234567: [[diagram.png]]\n\n%%\n## Drawing")
      expect(scene_of(rewritten).scene["elements"]).to eq(scene["elements"])
    end

    it "keeps the data commented out when the plugin's setting put it so" do
      source = fixture("user.excalidraw.md").sub("# Excalidraw Data", "%%\n# Excalidraw Data").sub("%%\n## Drawing", "## Drawing")

      rewritten = described_class.rewrite(source, scene)

      expect(rewritten.scan("%%").size).to eq(2)
      expect(rewritten).to match(/^%%\n# Excalidraw Data\n.*\n## Drawing\n```json\n.*\n```\n%%\z/m)
    end

    it "refuses markdown without a drawing" do
      expect { described_class.rewrite("# Just a note\n", scene) }.to raise_error(Omoteura::Diagram::ParseError)
    end
  end
end
