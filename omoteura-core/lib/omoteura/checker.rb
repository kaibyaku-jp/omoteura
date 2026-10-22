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

    # Ruby files under these top-level directories are not project code.
    IGNORED_DIRS = %w[vendor tmp log node_modules coverage pkg].freeze

    attr_reader :config

    def initialize(config)
      @config = config
      @resolver = Resolver.new(config)
      @link_resolver = LinkResolver.new(config)
    end

    def run
      problems = []
      attachments = code_paths.filter_map do |code_path|
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

    # Code files that can have a diagram: the project's Ruby files and any
    # other existing file named in the attach setting. A convention diagram
    # whose code file is gone is reported by #unattached_diagrams.
    def code_paths
      paths = ruby_files.to_set
      paths.merge(config.attach.keys.select { |path| File.file?(File.join(config.root, path)) })
      paths.sort
    end

    def ruby_files
      Dir.glob("**/*.rb", base: config.root).reject do |path|
        IGNORED_DIRS.include?(path.split("/", 2).first) || path.start_with?("#{config.diagrams_dir}/")
      end
    end

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

        Problem.new(file: path, message: "is not attached to any code file", shape: nil)
      end
    end
  end
end
