# frozen_string_literal: true

module Omoteura
  # The files of a project that can have a diagram attached.
  class Project
    # Ruby files under these top-level directories are not project code.
    IGNORED_DIRS = %w[vendor tmp log node_modules coverage pkg].freeze

    attr_reader :config

    def initialize(config)
      @config = config
    end

    # The project's Ruby files, outside IGNORED_DIRS and the diagrams
    # directory, and any other existing file named in the attach setting,
    # relative to the root and sorted.
    def code_paths
      paths = ruby_files.to_set
      paths.merge(config.attach.keys.select { |path| File.file?(File.join(config.root, path)) })
      paths.sort
    end

    private

    def ruby_files
      Dir.glob("**/*.rb", base: config.root).reject do |path|
        IGNORED_DIRS.include?(path.split("/", 2).first) || path.start_with?("#{config.diagrams_dir}/")
      end
    end
  end
end
