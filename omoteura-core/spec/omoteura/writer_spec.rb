# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Writer do
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

  def read(path) = File.read(File.join(root, path))

  def fixture(name)
    File.read(File.expand_path("../fixtures/diagrams/#{name}", __dir__))
  end

  def writer = described_class.new(Omoteura::Config.load(root))

  def save(path, data, **options) = writer.save(File.join(root, path), data, **options)

  def drawing(*elements)
    {"type" => "excalidraw", "version" => 2, "source" => "https://github.com/kaibyaku-jp/omoteura",
     "elements" => elements, "appState" => {"viewBackgroundColor" => "#ffffff"}, "files" => {}}
  end

  let(:box) { {"id" => "Box00001", "type" => "rectangle", "isDeleted" => false, "link" => "omoteura:#name"} }

  it "saves a .excalidraw file as JSON and gives the digest of what it wrote" do
    write("ura/user.excalidraw", JSON.generate(drawing))

    result = save("ura/user.excalidraw", drawing(box))

    expect(JSON.parse(read("ura/user.excalidraw"))).to eq(drawing(box))
    expect(result).to eq(described_class::Result.new(diagram_path: "ura/user.excalidraw", digest: described_class.digest(read("ura/user.excalidraw"))))
  end

  it "saves an Obsidian note in place, keeping the rest of the note" do
    write("ura/user.excalidraw.md", fixture("user_compressed.excalidraw.md").sub("# Excalidraw Data", "メモ\n\n# Excalidraw Data"))

    save("ura/user.excalidraw.md", drawing(box))

    note = read("ura/user.excalidraw.md")
    expect(note).to include("メモ\n\n# Excalidraw Data", "## Element Links\nBox00001: omoteura:#name\n", "```compressed-json\n")
    expect(Omoteura::Diagram.load(File.join(root, "ura/user.excalidraw.md")).linked_elements.map(&:id)).to eq(["Box00001"])
  end

  it "keeps the plugin's rawText while the text is unchanged, and drops it once edited" do
    write("ura/user.excalidraw.md", Omoteura::Obsidian.render(drawing(
      {"id" => "Same0001", "type" => "text", "text" => "User", "originalText" => "User", "rawText" => "[[User]]"},
      {"id" => "Edit0001", "type" => "text", "text" => "Post", "originalText" => "Post", "rawText" => "[[Post]]"}
    )))

    save("ura/user.excalidraw.md", drawing(
      {"id" => "Same0001", "type" => "text", "text" => "User", "originalText" => "User"},
      {"id" => "Edit0001", "type" => "text", "text" => "Comment", "originalText" => "Comment", "rawText" => "[[Post]]"}
    ))

    expect(read("ura/user.excalidraw.md")).to include("## Text Elements\n[[User]] ^Same0001\n\nComment ^Edit0001\n\n")
  end

  it "creates a new drawing in the format its name asks for" do
    save("ura/new.excalidraw.md", drawing(box))
    save("ura/new.excalidraw", drawing(box))

    expect(Omoteura::Diagram.load(File.join(root, "ura/new.excalidraw.md")).format).to eq(:obsidian)
    expect(Omoteura::Diagram.load(File.join(root, "ura/new.excalidraw")).format).to eq(:excalidraw)
  end

  it "refuses to overwrite a change made since the editor read the file" do
    write("ura/user.excalidraw", JSON.generate(drawing))
    read_digest = described_class.digest(read("ura/user.excalidraw"))
    write("ura/user.excalidraw", JSON.generate(drawing(box)))

    expect { save("ura/user.excalidraw", drawing, if_unchanged: read_digest) }
      .to raise_error(described_class::Conflict, "ura/user.excalidraw changed since it was read")
    expect(JSON.parse(read("ura/user.excalidraw"))).to eq(drawing(box))
  end

  it "saves when the file is as the editor read it" do
    write("ura/user.excalidraw", JSON.generate(drawing))

    expect { save("ura/user.excalidraw", drawing(box), if_unchanged: described_class.digest(read("ura/user.excalidraw"))) }.not_to raise_error
  end

  it "refuses to write outside the project, over markdown that is not a drawing, or to other kinds of file" do
    write("notes.md", "# Notes\n")

    expect { writer.save(File.join(root, "../elsewhere.excalidraw"), drawing) }.to raise_error(described_class::Invalid, /outside/)
    expect { save("notes.md", drawing) }.to raise_error(described_class::Invalid, "notes.md is not an Excalidraw drawing")
    expect { save("ura/user.json", drawing) }.to raise_error(described_class::Invalid, /must end in \.excalidraw or \.excalidraw\.md/)
    expect { save("ura/user.excalidraw", {"elements" => nil}) }.to raise_error(described_class::Invalid, /no elements list/)
    expect(read("notes.md")).to eq("# Notes\n")
  end

  it "leaves the file whole and no temporary file behind when writing fails" do
    write("ura/user.excalidraw", JSON.generate(drawing))
    allow(File).to receive(:rename).and_raise(Errno::EACCES)

    expect { save("ura/user.excalidraw", drawing(box)) }.to raise_error(Errno::EACCES)
    expect(JSON.parse(read("ura/user.excalidraw"))).to eq(drawing)
    expect(Dir.children(File.join(root, "ura"))).to eq(["user.excalidraw"])
  end
end
