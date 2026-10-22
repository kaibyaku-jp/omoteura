# frozen_string_literal: true

require "fileutils"
require "json"
require "omoteura/draft/scene_builder"
require "omoteura/outline"

module Omoteura
  # Drafts a diagram from a code file: for a spec, a column per example
  # group with a box per example; for other code, a column per kind of
  # declaration and one for public methods. Every box links to its code,
  # and a link is added only when it resolves to exactly that code.
  #
  # A draft is a starting point for a hand-drawn diagram. It never
  # replaces one: when the file already has a diagram, the draft goes
  # beside it as <name>.draft.excalidraw, or .draft.excalidraw.md when
  # drafting for Obsidian.
  class Draft
    CATEGORIES = Outline::KINDS
    FORMAT_SOURCE = "https://github.com/kaibyaku-jp/omoteura"
    EXTENSIONS = {excalidraw: ".excalidraw", obsidian: ".excalidraw.md"}.freeze

    # status is :written, :draft (written beside an existing diagram),
    # :exists (a previous draft is in the way) or :empty (nothing to draw).
    Result = Data.define(:code_path, :diagram_path, :shape_count, :status)

    # format is :excalidraw for a .excalidraw file or :obsidian for an
    # Obsidian Excalidraw plugin note.
    def initialize(config, only: CATEGORIES, out: nil, format: :excalidraw)
      @config = config
      @only = only
      @out = out
      @format = format
      @extension = EXTENSIONS.fetch(format)
      @resolver = Resolver.new(config)
      @link_resolver = LinkResolver.new(config)
    end

    # code_path is relative to the project root. Nothing is written when
    # dry_run is true.
    def draft(code_path, dry_run: false)
      index = SourceIndex.parse_file(File.join(@config.root, code_path))
      columns = index.spec_entries.empty? ? code_columns(index, code_path) : spec_columns(index, code_path)
      boxes = columns.sum { |column| column.items.count { |item| item.is_a?(SceneBuilder::Box) } }
      return Result.new(code_path: code_path, diagram_path: nil, shape_count: 0, status: :empty) if boxes.zero?

      diagram_path, status = destination(code_path)
      return Result.new(code_path: code_path, diagram_path: diagram_path, shape_count: boxes, status: :exists) if status == :exists

      write(diagram_path, SceneBuilder.new(code_path).build(code_path, columns)) unless dry_run
      Result.new(code_path: code_path, diagram_path: diagram_path, shape_count: boxes, status: status)
    end

    private

    def spec_columns(index, code_path)
      entries = index.spec_entries.sort_by(&:start_line)
      parents = parents_of(entries)
      roots = entries.reject { |entry| parents[entry] }
      # A single top-level group, the usual RSpec.describe, gives its
      # children a column each; otherwise each top-level group is a column.
      tops = (roots.size == 1 && roots.first.group) ? entries.select { |e| parents[e] == roots.first } : roots
      loose = tops.reject(&:group)
      columns = loose.empty? ? [] : [SceneBuilder::Column.new(heading: nil, items: loose.map { |e| spec_box(e, parents, code_path) })]
      columns + tops.select(&:group).map do |group|
        items = entries.select { |e| descendant?(e, group, parents) }.map do |entry|
          entry.group ? SceneBuilder::Heading.new(text: own_label(entry, parents), link: spec_link(entry, code_path)) : spec_box(entry, parents, code_path)
        end
        SceneBuilder::Column.new(heading: SceneBuilder::Heading.new(text: own_label(group, parents), link: spec_link(group, code_path)), items: items)
      end
    end

    def spec_box(entry, parents, code_path)
      SceneBuilder::Box.new(label: own_label(entry, parents), link: spec_link(entry, code_path))
    end

    def spec_link(entry, code_path)
      verified_link(["omoteura:##{entry.name}"], entry, code_path)
    end

    # Entries are sorted by start line and RSpec blocks nest, so each
    # entry's parent is the nearest open entry that still contains it.
    def parents_of(entries)
      open = []
      entries.to_h do |entry|
        open.pop while open.any? && open.last.end_line < entry.start_line
        parent = open.last
        open.push(entry)
        [entry, parent]
      end
    end

    def descendant?(entry, ancestor, parents)
      parent = parents[entry]
      parent = parents[parent] while parent && parent != ancestor
      !parent.nil?
    end

    # The description the entry adds to its parent's: "keeps emails
    # unique" for "User validations keeps emails unique".
    def own_label(entry, parents)
      parent = parents[entry]
      return entry.name unless parent && entry.name.start_with?(parent.name)

      entry.name.delete_prefix(parent.name).delete_prefix(" ")
    end

    def code_columns(index, code_path)
      Outline.new(index).items(only: @only).chunk_while { |a, b| a.kind == b.kind }.map do |items|
        kind = items.first.kind
        boxes = items.map do |item|
          entry = item.entry
          if kind == "methods"
            SceneBuilder::Box.new(label: entry.name, link: verified_link(["omoteura:##{entry.name}"], entry, code_path))
          else
            prefix = entry.name[/\A\S+\s+[^,(\s]+/]
            SceneBuilder::Box.new(label: entry.name.delete_suffix(","), link: verified_link(["omoteura:##{prefix}", "omoteura:##{entry.name}"].uniq, entry, code_path))
          end
        end
        SceneBuilder::Column.new(heading: SceneBuilder::Heading.new(text: kind.capitalize, link: nil), items: boxes)
      end
    end

    # The first candidate that resolves to exactly this entry, or nil.
    def verified_link(candidates, entry, code_path)
      candidates.find do |link|
        target = @link_resolver.resolve(link, context_path: code_path).target
        target && target.path == code_path && target.start_line == entry.start_line
      end
    end

    # The draft takes the conventional place, unless the file already has
    # a diagram, by any means, or a file is there. --out, relative to the
    # root, names a file or a directory instead. Nothing is ever replaced.
    def destination(code_path)
      if @out
        path = @out.end_with?(@extension) ? @out : File.join(@out, File.basename(base_name(code_path)) + @extension)
        return [path, File.exist?(File.expand_path(path, @config.root)) ? :exists : :written]
      end

      base = File.join(@config.diagrams_dir, base_name(code_path))
      attachment = @resolver.resolve(code_path)
      taken = attachment || EXTENSIONS.each_value.any? { |ext| File.exist?(File.join(@config.root, base + ext)) }
      return [base + @extension, :written] unless taken

      path = base + ".draft" + @extension
      [path, File.exist?(File.join(@config.root, path)) ? :exists : :draft]
    end

    def base_name(code_path)
      code_path.delete_suffix(File.extname(code_path))
    end

    def write(diagram_path, elements)
      full = File.expand_path(diagram_path, @config.root)
      FileUtils.mkdir_p(File.dirname(full))
      scene = {
        "type" => "excalidraw",
        "version" => 2,
        "source" => FORMAT_SOURCE,
        "elements" => elements,
        "appState" => {"viewBackgroundColor" => "#ffffff", "gridSize" => nil},
        "files" => {}
      }
      File.write(full, (@format == :obsidian) ? Obsidian.render(scene) : JSON.pretty_generate(scene) + "\n")
    end
  end
end
