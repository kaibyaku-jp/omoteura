# frozen_string_literal: true

module Omoteura
  # Which of a code file's declarations and public methods its specs cover,
  # for the editor's coverage panel. Separate from diagrams: it works on any
  # file and needs none.
  #
  # An item counts as covered by an example that names it, in the example's
  # description or its code: "validates :email" by an example mentioning
  # email, "def display_name" by one inside describe "#display_name". The
  # descriptions RSpec generated in the last run, such as those of
  # shoulda-matchers one-liners, count as well.
  class CoverageReport
    FORMAT_VERSION = 1

    def initialize(config, results: TestResults.new([]))
      @config = config
      @results = results
    end

    # code_path must be an existing file inside the project root.
    def report(code_path)
      file = @config.expand(code_path) or raise ArgumentError, "#{code_path} is outside the project"
      relative = @config.relative(file)
      data = {version: FORMAT_VERSION, code_path: relative, enabled: @config.coverage_panel, spec_paths: [], items: []}
      return data unless @config.coverage_panel

      specs = spec_paths(relative)
      examples = specs.flat_map { |spec| examples_in(spec) }
      items = Outline.new(SourceIndex.parse_file(file)).items
      data.merge(spec_paths: specs, items: items.map { |item| item_data(item, examples) })
    end

    private

    ONE_LINER = /\A(?:it|specify|example|its)\b(?!\s*["'(])/
    # label is what the panel shows; description is what names are looked for in.
    Example = Data.define(:path, :line, :label, :description, :source, :status)
    private_constant :ONE_LINER, :Example

    # The specs for a file by RSpec's conventions: app/models/user.rb is
    # tested in spec/models/user_spec.rb, lib/a/b.rb in spec/a/b_spec.rb or
    # spec/lib/a/b_spec.rb.
    def spec_paths(code_path)
      base = code_path.delete_suffix(File.extname(code_path))
      candidates =
        if base.start_with?("app/") then ["spec/#{base.delete_prefix("app/")}_spec.rb"]
        elsif base.start_with?("lib/") then ["spec/#{base.delete_prefix("lib/")}_spec.rb", "spec/#{base}_spec.rb"]
        else ["spec/#{base}_spec.rb"]
        end
      candidates.select { |path| (full = @config.expand(path)) && File.file?(full) }
    end

    def examples_in(spec_path)
      source = File.read(File.join(@config.root, spec_path), encoding: Encoding::UTF_8)
      lines = source.lines
      recorded = @results.examples.select { |e| e.file_path.delete_prefix("./") == spec_path }.to_h { |e| [e.line_number, e] }
      index = SourceIndex.new(source)
      described = index.spec_entries.reject(&:group)
      # Examples without a description, such as it { is_expected.to ... },
      # are statements only; their description comes from the last run.
      lines_taken = described.to_h { |entry| [entry.start_line, true] }
      undescribed = index.statement_entries.select { |e| e.name.match?(ONE_LINER) && !lines_taken[e.start_line] }
      (described + undescribed).sort_by(&:start_line).map do |entry|
        result = recorded[entry.start_line]
        static = (entry.kind == :spec) ? entry.name : nil
        description = [static, result&.full_description].compact.uniq.join("\n")
        Example.new(path: spec_path, line: entry.start_line, label: static || result&.full_description || entry.name, description: description,
          source: lines[(entry.start_line - 1)...entry.end_line].join, status: result&.status)
      end
    end

    def item_data(item, examples)
      entry = item.entry
      patterns = names_of(item).map { |name| patterns_for(name) }
      covering = examples.select { |example| patterns.any? { |words, code| example.description.match?(words) || example.source.match?(code) } }
      {
        kind: item.kind,
        name: entry.name,
        start_line: entry.start_line,
        end_line: entry.end_line,
        covered: !covering.empty?,
        examples: covering.map { |e| {path: e.path, line: e.line, description: e.label, status: e.status} }
      }
    end

    # What an example would call the item: the symbols a declaration names,
    # such as email and name in "validates :email, :name, presence: true",
    # or a method's name.
    def names_of(item)
      return [item.entry.name.delete_prefix("self.")] if item.kind == "methods"

      call = item.entry.name.sub(/\A\S+\s*/, "")
      symbols = call.scan(/(?<![\w:]):(\w+[?!]?)/).flatten
      # enum role: { ... }, the older syntax, names its attribute as a key.
      symbols = call.scan(/\A(\w+):/).flatten if symbols.empty?
      symbols.reject { |name| name.length < 2 }
    end

    # The name as a word in an example's description, and in its code.
    # Underscores may be spaces in a description: "display name" for
    # display_name. Built once per name, not per example.
    def patterns_for(name)
      code = Regexp.escape(name)
      [/(?<!\w)#{code.gsub("_", "[_ ]")}(?![\w?!])/i, /(?<!\w)#{code}(?![\w?!])/]
    end
  end
end
