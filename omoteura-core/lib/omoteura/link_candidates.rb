# frozen_string_literal: true

module Omoteura
  # The places in a code file a shape can link to, each with a link that
  # resolves to exactly that place: in a spec, every example group and
  # example; in other code, every declaration and method. For an editor to
  # offer when linking a shape, and for drafts.
  class LinkCandidates
    Candidate = Data.define(:link, :label, :kind, :line)

    def initialize(config, link_resolver: LinkResolver.new(config))
      @config = config
      @link_resolver = link_resolver
    end

    # code_path is relative to the project root. Links leave the path out,
    # so they are for a diagram attached to this file. Places no link can
    # single out, such as two examples with one description, are left out.
    def for(code_path)
      index = SourceIndex.parse_file(File.join(@config.root, code_path))
      candidates = index.spec_entries.empty? ? code(index, code_path) : specs(index, code_path)
      candidates.sort_by(&:line)
    end

    private

    def specs(index, code_path)
      index.spec_entries.filter_map do |entry|
        candidate(["omoteura:##{entry.name}"], entry, code_path, label: entry.name, kind: entry.group ? "group" : "example")
      end
    end

    # Declarations link by the macro and its first argument, such as
    # "validates :email", and failing that by their whole first line.
    def code(index, code_path)
      declarations = Outline.new(index).items(only: Outline::KINDS - ["methods"]).filter_map do |item|
        entry = item.entry
        prefix = entry.name[/\A\S+\s+[^,(\s]+/]
        candidate(["omoteura:##{prefix}", "omoteura:##{entry.name}"].compact.uniq, entry, code_path,
          label: entry.name.delete_suffix(","), kind: item.kind)
      end
      methods = index.method_entries.filter_map do |entry|
        candidate(["omoteura:##{entry.name}"], entry, code_path, label: entry.name, kind: "methods")
      end
      declarations + methods
    end

    def candidate(links, entry, code_path, label:, kind:)
      link = @link_resolver.exact_link(links, path: code_path, line: entry.start_line)
      link && Candidate.new(link: link, label: label, kind: kind, line: entry.start_line)
    end
  end
end
