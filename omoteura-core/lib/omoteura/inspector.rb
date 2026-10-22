# frozen_string_literal: true

module Omoteura
  # Everything an editor needs about one code file or one diagram, as plain
  # data: the attached diagram or the code it is attached to, where each
  # linked shape points and how the tests behind it did. Broken links and
  # unreadable diagrams are reported in the data rather than raised, so the
  # editor can show them.
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

    # diagram_path must be an existing file inside the project root. A shared
    # diagram can be attached to several files; links without a path are
    # resolved against the first of them.
    def diagram_report(diagram_path)
      file = @config.expand(diagram_path) or raise ArgumentError, "#{diagram_path} is outside the project"
      relative = @config.relative(file)
      attached_to = code_attached_to(relative)
      data = {version: FORMAT_VERSION, diagram_path: relative, attached_to: attached_to, scene: nil, shapes: [], error: nil}

      diagram = Diagram.load(file)
      data[:scene] = diagram.scene
      data[:shapes] = diagram.linked_elements.map { |element| shape(element, attached_to.first) }
      data
    rescue Diagram::NotADiagram, Diagram::ParseError => e
      data.merge(error: e.message.delete_prefix("#{@config.root}/"))
    end

    private

    def code_attached_to(diagram_path)
      Project.new(@config).code_paths.select do |code_path|
        attachment = @resolver.resolve(code_path)
        attachment && !attachment.missing? && attachment.diagram_path == diagram_path
      rescue MagicComment::Duplicate, Resolver::InvalidPath
        false
      end
    end

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
