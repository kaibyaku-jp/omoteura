# frozen_string_literal: true

module Omoteura
  # Checks a whole project: every attached diagram must exist and parse,
  # every omoteura: link in it must resolve, every magic comment must be
  # valid, and every diagram under diagrams_dir must be attached to code.
  class Checker
    # file is relative to the project root. shape names the diagram element
    # a link problem comes from, as its label or id.
    Problem = Data.define(:file, :message, :shape)

    Report = Data.define(:problems, :diagram_count, :link_count) do
      def ok?
        problems.empty?
      end
    end

    attr_reader :config

    def initialize(config)
      @config = config
      @project = Project.new(config)
      @resolver = Resolver.new(config)
      @link_resolver = LinkResolver.new(config)
    end

    def run
      problems = []
      attachments = @project.code_paths.filter_map do |code_path|
        @resolver.resolve(code_path)
      rescue MagicComment::Duplicate, Resolver::InvalidPath => e
        problems << Problem.new(file: code_path, message: e.message.delete_prefix("#{code_path} "), shape: nil)
        nil
      end

      link_count = 0
      attachments.each do |attachment|
        if attachment.missing?
          problems << Problem.new(file: attachment.code_path, message: "attaches #{attachment.diagram_path}, which does not exist", shape: nil)
          next
        end

        diagram = load_diagram(attachment.diagram_path, problems) or next
        diagram.linked_elements.each do |element|
          link_count += 1
          result = @link_resolver.resolve(element.link, context_path: attachment.code_path)
          next unless result.broken?

          problems << Problem.new(file: attachment.diagram_path, message: result.error, shape: element.label || element.id)
        end
      end

      problems.concat(unattached_diagrams(attachments))
      diagram_paths = attachments.reject(&:missing?).map(&:diagram_path).uniq
      Report.new(problems: problems, diagram_count: diagram_paths.size, link_count: link_count)
    end

    private

    def load_diagram(diagram_path, problems)
      Diagram.load(File.join(config.root, diagram_path))
    rescue Diagram::NotADiagram, Diagram::ParseError => e
      problems << Problem.new(file: diagram_path, message: e.message.delete_prefix("#{File.join(config.root, diagram_path)} "), shape: nil)
      nil
    end

    def unattached_diagrams(attachments)
      attached = attachments.map(&:diagram_path).to_set
      diagram_dir = File.join(config.root, config.diagrams_dir)
      return [] unless Dir.exist?(diagram_dir)

      Dir.glob("**/*.{excalidraw,md}", base: diagram_dir).sort.filter_map do |relative|
        path = File.join(config.diagrams_dir, relative)
        next if attached.include?(path) || !Diagram.diagram_file?(File.join(config.root, path))

        message = path.match?(/\.draft\.excalidraw(?:\.md)?\z/) ? "is a draft; copy what you need into the diagram, then delete it" : "is not attached to any code file"
        Problem.new(file: path, message: message, shape: nil)
      end
    end
  end
end
