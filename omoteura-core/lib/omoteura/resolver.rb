# frozen_string_literal: true

require "pathname"

module Omoteura
  # Decides which diagram is attached to a code file. In order of priority:
  # the magic comment, the attach setting, then the path convention
  # (<diagrams_dir>/<code path>.excalidraw.md or .excalidraw).
  class Resolver
    class InvalidPath < Error; end

    # Paths are relative to the project root. An explicitly attached diagram
    # that does not exist is still returned, marked missing, so callers can
    # report it instead of silently falling back to the convention.
    Attachment = Data.define(:code_path, :diagram_path, :source, :missing) do
      def missing?
        missing
      end
    end

    CONVENTION_EXTENSIONS = %w[.excalidraw.md .excalidraw].freeze

    attr_reader :config

    def initialize(config)
      @config = config
    end

    # Returns an Attachment, or nil when the file has no diagram or lies
    # outside the project root. The code file must exist.
    def resolve(code_path)
      code = config.expand(code_path) or return nil
      relative = relative_to_root(code)

      if (written = MagicComment.find(File.read(code, encoding: Encoding::UTF_8), path: relative))
        explicit(relative, written, :magic_comment)
      elsif (written = config.attach[relative])
        explicit(relative, written, :config)
      else
        by_convention(relative)
      end
    end

    private

    # Obsidian URIs and wikilinks leave out the .md extension, so a path
    # copied from Obsidian is accepted when only "<path>.md" exists.
    def explicit(code_path, written, source)
      path = config.expand(written) or
        raise InvalidPath, "#{code_path} attaches #{written}, which is outside the project"

      unless File.file?(path)
        with_md = config.expand("#{written}.md")
        path = with_md if with_md && File.file?(with_md)
      end

      Attachment.new(code_path: code_path, diagram_path: relative_to_root(path), source: source, missing: !File.file?(path))
    end

    def by_convention(code_path)
      base = File.join(config.diagrams_dir, code_path.delete_suffix(File.extname(code_path)))
      CONVENTION_EXTENSIONS.each do |extension|
        path = config.expand(base + extension)
        next unless path && File.file?(path)

        return Attachment.new(code_path: code_path, diagram_path: relative_to_root(path), source: :convention, missing: false)
      end
      nil
    end

    def relative_to_root(path)
      Pathname(path).relative_path_from(Pathname(config.root)).to_s
    end
  end
end
