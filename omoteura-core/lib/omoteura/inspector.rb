# frozen_string_literal: true

module Omoteura
  # Everything an editor needs about one code file, as plain data: the
  # attached diagram, where each linked shape points and how the tests
  # behind it did. Broken links and unreadable diagrams are reported in
  # the data rather than raised, so the editor can show them.
  class Inspector
    FORMAT_VERSION = 1

    def initialize(config, results: TestResults.new([]))
      @config = config
      @results = results
      @resolver = Resolver.new(config)
      @link_resolver = LinkResolver.new(config)
    end

    # code_path must be an existing file inside the project root.
    def report(code_path)
      file = @config.expand(code_path) or raise ArgumentError, "#{code_path} is outside the project"
      relative = @config.relative(file)
      data = {version: FORMAT_VERSION, code_path: relative, new_diagram_path: new_diagram_path(relative),
              attachment: nil, shapes: [], error: nil}

      attachment = @resolver.resolve(relative) or return data
      data[:attachment] = {diagram_path: attachment.diagram_path, source: attachment.source.to_s, missing: attachment.missing?}
      return data if attachment.missing?

      diagram = Diagram.load(@config.expand(attachment.diagram_path))
      data[:shapes] = diagram.linked_elements.map { |element| shape(element, relative) }
      data
    rescue MagicComment::Duplicate, Resolver::InvalidPath, Diagram::NotADiagram, Diagram::ParseError => e
      data.merge(error: e.message.delete_prefix("#{@config.root}/"))
    end

    private

    # Where a new plain Excalidraw diagram for the file belongs by the path
    # convention, so an editor can offer to create one.
    def new_diagram_path(code_path)
      File.join(@config.diagrams_dir, code_path.delete_suffix(File.extname(code_path)) + ".excalidraw")
    end

    def shape(element, context_path)
      result = @link_resolver.resolve(element.link, context_path: context_path)
      target = result.target
      summary = target && @results.summary_for(target)
      {
        id: element.id,
        label: element.label,
        link: element.link,
        target: target&.to_h,
        error: result.error,
        test: summary && {
          status: summary.status,
          examples: summary.examples.map { |e| e.to_h.slice(:line_number, :full_description, :status, :message) }
        }
      }
    end
  end
end
