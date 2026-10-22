# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "omoteura/core"

RSpec.describe Omoteura::Draft do
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

  def config = Omoteura::Config.load(root)

  def draft(path, **options)
    dry_run = options.delete(:dry_run) || false
    described_class.new(config, **options).draft(path, dry_run: dry_run)
  end

  def elements(diagram_path)
    JSON.parse(File.read(File.join(root, diagram_path)))["elements"]
  end

  # Labels with the line breaks wrapping added taken out again.
  def labels(diagram_path)
    elements(diagram_path).select { |e| e["type"] == "text" }.map { |e| e["text"].tr("\n", " ") }
  end

  # Every link the draft wrote resolves, and to the line of the code its box names.
  def resolved_links(diagram_path, code_path)
    resolver = Omoteura::LinkResolver.new(config)
    Omoteura::Diagram.load(File.join(root, diagram_path)).linked_elements.map do |element|
      result = resolver.resolve(element.link, context_path: code_path)
      [element.label.tr("\n", " "), result.error || result.target.start_line]
    end
  end

  describe "a spec" do
    before do
      write("spec/models/user_spec.rb", <<~RUBY)
        RSpec.describe User do
          it "is valid with defaults" do
          end

          describe "validations" do
            it "requires an email" do
            end

            context "with a long name" do
              it "rejects names longer than fifty characters, as the column only holds that many" do
              end
            end
          end

          describe "#display_name" do
            it "uses the name" do
            end
          end
        end
      RUBY
    end

    it "writes a column per group with a linked box per example at the conventional path" do
      result = draft("spec/models/user_spec.rb")

      expect(result).to have_attributes(diagram_path: "ura/spec/models/user_spec.excalidraw", shape_count: 4, status: :written)
      expect(resolved_links(result.diagram_path, "spec/models/user_spec.rb")).to eq([
        ["is valid with defaults", 2],
        ["validations", 5],
        ["requires an email", 6],
        ["with a long name", 9],
        ["rejects names longer than fifty characters, as the column only holds that many", 10],
        ["#display_name", 15],
        ["uses the name", 16]
      ])
    end

    it "wraps long labels to the box" do
      result = draft("spec/models/user_spec.rb")

      long = elements(result.diagram_path).find { |e| e["text"]&.start_with?("rejects names") }["text"]
      expect(long.lines.size).to be > 1
      expect(long.tr("\n", " ")).to eq("rejects names longer than fifty characters, as the column only holds that many")
    end

    it "leaves the link off when two examples share a description" do
      write("spec/models/post_spec.rb", <<~RUBY)
        RSpec.describe Post do
          it "works" do
          end
          it "works" do
          end
        end
      RUBY

      result = draft("spec/models/post_spec.rb")

      expect(result.shape_count).to eq(2)
      expect(Omoteura::Diagram.load(File.join(root, result.diagram_path)).linked_elements).to eq([])
    end
  end

  describe "application code" do
    before do
      write("app/models/user.rb", <<~RUBY)
        class User < ApplicationRecord
          has_many :posts, dependent: :destroy
          belongs_to :team

          validates :name, presence: true
          validates :email, presence: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
          validates :email_confirmation, presence: true

          before_save :downcase_email
          scope :active, -> { where(active: true) }
          enum :role, { member: 0, admin: 1 }

          def display_name
            name.presence || email
          end

          def self.find_by_email(email)
          end

          private def secret
          end

          private

          def downcase_email
            self.email = email.downcase
          end
        end
      RUBY
    end

    it "groups declarations by kind, then public methods, all linked to their lines" do
      result = draft("app/models/user.rb")

      expect(labels(result.diagram_path)).to eq([
        "app/models/user.rb",
        "Validations", "validates :name, presence: true", "validates :email, presence: true",
        "validates :email_confirmation, presence: true",
        "Associations", "has_many :posts, dependent: :destroy", "belongs_to :team",
        "Callbacks", "before_save :downcase_email",
        "Scopes", "scope :active, -> { where(active: true) }",
        "Enums", "enum :role, { member: 0, admin: 1 }",
        "Methods", "display_name", "self.find_by_email"
      ])
      expect(resolved_links(result.diagram_path, "app/models/user.rb").map(&:last)).to eq([5, 6, 8, 2, 3, 10, 11, 12, 14, 18])
    end

    it "draws only the kinds asked for" do
      result = draft("app/models/user.rb", only: %w[associations methods])

      expect(labels(result.diagram_path)).to eq([
        "app/models/user.rb", "Associations", "has_many :posts, dependent: :destroy", "belongs_to :team",
        "Methods", "display_name", "self.find_by_email"
      ])
    end

    it "draws nothing for code without declarations or public methods" do
      write("lib/constants.rb", "LIMIT = 10\n")

      expect(draft("lib/constants.rb")).to have_attributes(status: :empty, shape_count: 0, diagram_path: nil)
    end
  end

  describe "where it writes" do
    before { write("app/models/team.rb", "class Team\n  def name\n  end\nend\n") }

    it "writes beside an existing diagram instead of replacing it" do
      write("ura/app/models/team.excalidraw.md", "kept")

      result = draft("app/models/team.rb")

      expect(result).to have_attributes(diagram_path: "ura/app/models/team.draft.excalidraw", status: :draft)
      expect(File.read(File.join(root, "ura/app/models/team.excalidraw.md"))).to eq("kept")
    end

    it "writes beside a diagram attached by magic comment" do
      write("app/models/team.rb", "# omoteura: ura/shared/team.excalidraw\nclass Team\n  def name\n  end\nend\n")

      expect(draft("app/models/team.rb").status).to eq(:draft)
    end

    it "does not replace an earlier draft" do
      write("ura/app/models/team.excalidraw", "{}")
      write("ura/app/models/team.draft.excalidraw", "edited")

      expect(draft("app/models/team.rb").status).to eq(:exists)
      expect(File.read(File.join(root, "ura/app/models/team.draft.excalidraw"))).to eq("edited")
    end

    it "writes to --out, as a directory or a file, but never over a file" do
      expect(draft("app/models/team.rb", out: "sketches").diagram_path).to eq("sketches/team.excalidraw")
      expect(File).to exist(File.join(root, "sketches/team.excalidraw"))
      expect(draft("app/models/team.rb", out: "sketches/team.excalidraw").status).to eq(:exists)
    end

    it "writes nothing on a dry run" do
      result = draft("app/models/team.rb", dry_run: true)

      expect(result.status).to eq(:written)
      expect(File).not_to exist(File.join(root, result.diagram_path))
    end
  end

  describe "for Obsidian" do
    before { write("app/models/team.rb", "class Team\n  def name\n  end\nend\n") }

    it "writes a note the Obsidian Excalidraw plugin reads, with the same drawing" do
      note = draft("app/models/team.rb", format: :obsidian)
      json = draft("app/models/team.rb", out: "team.excalidraw")
      diagram = Omoteura::Diagram.load(File.join(root, note.diagram_path))

      expect(note).to have_attributes(diagram_path: "ura/app/models/team.excalidraw.md", status: :written)
      expect(diagram.format).to eq(:obsidian)
      expect(diagram.scene["elements"].map { |e| e.except("updated") }).to eq(elements(json.diagram_path).map { |e| e.except("updated") })
      expect(File.read(File.join(root, note.diagram_path))).to include("## Element Links\n#{diagram.linked_elements.first.id}: omoteura:#name\n")
    end

    it "writes beside an existing diagram as a draft note" do
      write("ura/app/models/team.excalidraw", "{}")

      expect(draft("app/models/team.rb", format: :obsidian).diagram_path).to eq("ura/app/models/team.draft.excalidraw.md")
    end

    it "takes --out as a note or a directory" do
      expect(draft("app/models/team.rb", format: :obsidian, out: "notes").diagram_path).to eq("notes/team.excalidraw.md")
      expect(draft("app/models/team.rb", format: :obsidian, out: "notes/x.excalidraw.md").diagram_path).to eq("notes/x.excalidraw.md")
    end
  end

  describe "merging into the diagram" do
    let(:spec) do
      <<~RUBY
        RSpec.describe User do
          describe "validations" do
            it "requires an email" do
            end

            it "requires a name" do
            end
          end

          it "has a display name" do
          end
        end
      RUBY
    end

    before do
      write("spec/models/user_spec.rb", spec)
      draft("spec/models/user_spec.rb")
    end

    def merge(path, **options)
      dry_run = options.delete(:dry_run) || false
      described_class.new(config, **options).merge(path, dry_run: dry_run)
    end

    def without_updated(path) = elements(path).map { |e| e.except("updated") }

    it "adds only what has no shape yet, to the right, leaving every drawn element as it was" do
      diagram = "ura/spec/models/user_spec.excalidraw"
      before = without_updated(diagram)
      write("spec/models/user_spec.rb", spec.sub("  it \"has a display name\" do", "  it \"downcases emails\" do\n  end\n\n  it \"has a display name\" do"))

      result = merge("spec/models/user_spec.rb")

      after = without_updated(diagram)
      added = after.drop(before.size)
      expect(result).to have_attributes(diagram_path: diagram, shape_count: 1, status: :merged)
      expect(after.take(before.size)).to eq(before)
      expect(added.select { |e| e["type"] == "text" }.map { |e| e["text"].tr("\n", " ") }).to eq(["Not drawn yet", "downcases emails"])
      expect(added.map { |e| e["x"] }.min).to be > before.map { |e| e["x"] + e["width"] }.max
      expect((added + before).map { |e| e["id"] }.uniq.size).to eq(after.size)
      expect(resolved_links(diagram, "spec/models/user_spec.rb").assoc("downcases emails")).to eq(["downcases emails", 10])
    end

    it "counts a shape as drawn by its link or its label, wherever it is" do
      expect(merge("spec/models/user_spec.rb")).to have_attributes(status: :up_to_date, shape_count: 0)
    end

    it "keeps an Obsidian note's format and the rest of the note" do
      write("app/models/team.rb", "class Team\n  def name\n  end\nend\n")
      draft("app/models/team.rb", format: :obsidian)
      note = File.join(root, "ura/app/models/team.excalidraw.md")
      File.write(note, File.read(note).sub("# Excalidraw Data", "メモ\n\n# Excalidraw Data"))
      write("app/models/team.rb", "class Team\n  def name\n  end\n\n  def members\n  end\nend\n")

      expect(merge("app/models/team.rb").status).to eq(:merged)
      expect(File.read(note)).to include("メモ\n\n# Excalidraw Data", "```compressed-json\n")
      expect(Omoteura::Diagram.load(note).elements.map(&:label)).to include("name", "members")
    end

    it "writes nothing on a dry run, and nothing without a diagram" do
      write("spec/models/post_spec.rb", "RSpec.describe Post do\n  it \"works\" do\n  end\nend\n")
      write("spec/models/user_spec.rb", spec + "\nRSpec.describe Admin do\n  it \"is new\" do\n  end\nend\n")
      before = File.read(File.join(root, "ura/spec/models/user_spec.excalidraw"))

      expect(merge("spec/models/user_spec.rb", dry_run: true)).to have_attributes(status: :merged, shape_count: 1)
      expect(File.read(File.join(root, "ura/spec/models/user_spec.excalidraw"))).to eq(before)
      expect(merge("spec/models/post_spec.rb")).to have_attributes(status: :no_diagram, diagram_path: nil)
    end
  end

  describe "the drawing" do
    before { write("app/models/team.rb", "class Team\n  def name\n  end\nend\n") }

    it "is an Excalidraw file with every field Excalidraw expects on each element" do
      result = draft("app/models/team.rb")
      data = JSON.parse(File.read(File.join(root, result.diagram_path)))
      base = %w[id type x y width height angle strokeColor backgroundColor fillStyle strokeWidth strokeStyle
        roughness opacity groupIds frameId index roundness seed version versionNonce isDeleted boundElements
        updated link locked]
      text = %w[text originalText fontSize fontFamily textAlign verticalAlign containerId autoResize lineHeight]

      expect(data.slice("type", "version", "source")).to eq("type" => "excalidraw", "version" => 2, "source" => "https://github.com/kaibyaku-jp/omoteura")
      data["elements"].each do |element|
        expect(element.keys).to include(*base)
        expect(element.keys).to include(*text) if element["type"] == "text"
      end
      box = data["elements"].find { |e| e["type"] == "rectangle" }
      label = data["elements"].find { |e| e["containerId"] == box["id"] }
      expect(box["boundElements"]).to eq([{"type" => "text", "id" => label["id"]}])
      expect(data["elements"].map { |e| e["id"].size }.uniq).to eq([8])
    end

    it "is the same drawing every time, apart from timestamps" do
      first = draft("app/models/team.rb", out: "a.excalidraw")
      second = draft("app/models/team.rb", out: "b.excalidraw")
      strip = ->(path) { elements(path).map { |e| e.except("updated") } }

      expect(strip.call(first.diagram_path)).to eq(strip.call(second.diagram_path))
    end
  end
end
