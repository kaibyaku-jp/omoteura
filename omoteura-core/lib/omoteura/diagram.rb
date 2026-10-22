# frozen_string_literal: true

require "json"
require "psych"
require "omoteura/lz_string"

module Omoteura
  # An Excalidraw drawing read from disk, either a plain .excalidraw file or
  # an Obsidian Excalidraw plugin markdown file.
  class Diagram
    class NotADiagram < Error; end

    class ParseError < Error; end

    LINK_PREFIX = "omoteura:"

    Element = Data.define(:id, :type, :link, :label) do
      def omoteura_link?
        link&.start_with?(LINK_PREFIX) || false
      end
    end

    FRONTMATTER = /\A---[ \t]*\r?\n(.*?)^---[ \t]*$/m
    DRAWING_BLOCK = /^\#\#[ \t]+Drawing[ \t]*\r?\n+```(json|compressed-json)[ \t]*\r?\n(.*?)^```/m
    ELEMENT_LINKS = /^\#\# Element Links\r?\n(.*?)(?=^\#\# Embedded Files|^\#\#? Drawing|\z)/m
    # The plugin's ids are eight characters.
    ELEMENT_LINK = /^(.{8}):[ \t]*(.*?)\r?$/

    class << self
      def load(path)
        path = path.to_s
        source = File.read(path, encoding: Encoding::UTF_8)
        format = detect_format(path, source)
        raise NotADiagram, "#{path} is not an Excalidraw drawing" unless format

        new(path: path, format: format, data: parse_data(format, source, path))
      end

      def diagram_file?(path)
        path = path.to_s
        return false unless File.file?(path)

        !detect_format(path, File.read(path, encoding: Encoding::UTF_8)).nil?
      end

      private

      # Mirrors the Obsidian plugin: a .md file is a drawing when its
      # frontmatter has the excalidraw-plugin key, whatever its name.
      def detect_format(path, source)
        case File.extname(path)
        when ".excalidraw" then :excalidraw
        when ".md" then :obsidian if obsidian_drawing?(source)
        end
      end

      def obsidian_drawing?(source)
        match = FRONTMATTER.match(source) or return false
        frontmatter = Psych.safe_load(match[1])
        frontmatter.is_a?(Hash) && frontmatter.key?("excalidraw-plugin")
      rescue Psych::Exception
        false
      end

      def parse_data(format, source, path)
        json =
          if format == :excalidraw
            source
          else
            drawing_json(source, path)
          end
        data = JSON.parse(json)
        raise ParseError, "#{path} has no elements list" unless data.is_a?(Hash) && data["elements"].is_a?(Array)

        apply_element_links(source, data["elements"]) if format == :obsidian
        data
      rescue JSON::ParserError => e
        raise ParseError, "#{path} has invalid drawing JSON: #{e.message}"
      end

      def drawing_json(source, path)
        match = DRAWING_BLOCK.match(source) or raise ParseError, "#{path} has no ## Drawing block"
        return match[2] if match[1] == "json"

        LZString.decompress_from_base64(match[2]) or
          raise ParseError, "#{path} has a corrupt compressed-json block"
      end

      # As in the plugin, a link listed under Element Links wins over the
      # one in the drawing, so a link edited in the markdown counts before
      # Obsidian has saved the drawing again.
      def apply_element_links(source, elements)
        section = ELEMENT_LINKS.match(source) or return
        links = section[1].scan(ELEMENT_LINK).to_h
        elements.each { |e| e["link"] = links[e["id"]] if e.is_a?(Hash) && links.key?(e["id"]) }
      end
    end

    attr_reader :path, :format, :elements

    def initialize(path:, format:, data:)
      @path = path
      @format = format
      @data = data
      @elements = build_elements(data["elements"])
    end

    # The drawing as Excalidraw itself reads it, for showing it in an editor.
    def scene
      {"elements" => @data["elements"], "appState" => @data["appState"] || {}, "files" => @data["files"] || {}}
    end

    def linked_elements
      elements.select(&:omoteura_link?)
    end

    private

    def build_elements(raw_elements)
      live = raw_elements.select { |e| e.is_a?(Hash) && !e["isDeleted"] }
      labels = live.each_with_object({}) do |e, acc|
        acc[e["containerId"]] = text_of(e) if e["type"] == "text" && e["containerId"]
      end

      live.map do |e|
        label = (e["type"] == "text") ? text_of(e) : labels[e["id"]]
        Element.new(id: e["id"], type: e["type"], link: e["link"], label: label)
      end
    end

    def text_of(element)
      element["originalText"] || element["text"]
    end
  end
end
