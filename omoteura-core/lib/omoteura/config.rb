# frozen_string_literal: true

require "pathname"
require "psych"

module Omoteura
  # Project settings from .omoteura.yml, overridden by .omoteura.local.yml.
  class Config
    class Invalid < Error; end

    FILE_NAMES = %w[.omoteura.yml .omoteura.local.yml].freeze
    DEFAULT_DIAGRAMS_DIR = "ura"

    attr_reader :root, :diagrams_dir, :attach

    def self.load(root)
      root = File.expand_path(root)
      settings = FILE_NAMES.each_with_object({}) do |name, merged|
        path = File.join(root, name)
        merge_settings(merged, read_settings(path)) if File.file?(path)
      end
      new(root: root, **settings)
    end

    def self.read_settings(path)
      settings = Psych.safe_load_file(path) || {}
      raise Invalid, "#{path} must be a mapping" unless settings.is_a?(Hash)

      settings
    rescue Psych::Exception => e
      raise Invalid, "#{path} is not valid YAML: #{e.message}"
    end

    # The local file adds to and overrides individual attach entries
    # rather than replacing the whole attach mapping.
    def self.merge_settings(merged, settings)
      merged[:diagrams_dir] = settings["diagrams_dir"] if settings.key?("diagrams_dir")
      return unless settings.key?("attach")

      attach = settings["attach"]
      # A non-mapping value is passed through so #initialize reports it.
      merged[:attach] = attach.is_a?(Hash) ? (merged[:attach] || {}).merge(attach) : attach
    end
    private_class_method :read_settings, :merge_settings

    def initialize(root:, diagrams_dir: DEFAULT_DIAGRAMS_DIR, attach: {})
      @root = File.expand_path(root)
      @diagrams_dir = validate_relative_path(diagrams_dir, "diagrams_dir")
      @attach = validate_attach(attach).freeze
    end

    # Expands a path written relative to the project root. Returns nil when
    # it points outside the root, so a repository cannot make Omoteura read
    # arbitrary files on the machine.
    def expand(relative_path)
      path = File.expand_path(relative_path, root)
      inside_root?(path) ? path : nil
    end

    # The path relative to the root, for paths that #expand accepted.
    def relative(path)
      Pathname(path).relative_path_from(Pathname(root)).to_s
    end

    private

    def inside_root?(path)
      return false unless path.start_with?(root + File::SEPARATOR)
      return true unless File.exist?(path)

      File.realpath(path).start_with?(File.realpath(root) + File::SEPARATOR)
    end

    def validate_relative_path(value, key)
      unless value.is_a?(String) && !value.empty? && !Pathname(value).absolute?
        raise Invalid, "#{key} must be a relative path, got #{value.inspect}"
      end

      value
    end

    def validate_attach(value)
      raise Invalid, "attach must be a mapping of code paths to diagram paths" unless value.is_a?(Hash)

      value.to_h do |code_path, diagram_path|
        [validate_relative_path(code_path, "attach key"), validate_relative_path(diagram_path, "attach[#{code_path}]")]
      end
    end
  end
end
