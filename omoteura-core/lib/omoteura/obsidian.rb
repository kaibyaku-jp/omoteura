# frozen_string_literal: true

require "json"
require "omoteura/lz_string"

module Omoteura
  # Writes drawings as the Obsidian Excalidraw plugin saves them: a
  # markdown note whose "# Excalidraw Data" part lists the text of each
  # text element and the link of each linked element, followed by the
  # scene itself in a ## Drawing block.
  #
  # The plugin reads ids back from those lists as exactly eight
  # characters, so elements with other ids are left out of them. It still
  # reads them from the scene, and gives text elements new ids.
  module Obsidian
    # What the plugin writes at the top of a new drawing.
    HEADER = <<~MARKDOWN
      ---

      excalidraw-plugin: parsed
      tags: [excalidraw]

      ---
      ==⚠  Switch to EXCALIDRAW VIEW in the MORE OPTIONS menu of this document. ⚠== You can decompress Drawing data with the command palette: 'Decompress current Excalidraw file'. For more info check in plugin settings under 'Saving'


    MARKDOWN
    ID_LENGTH = 8
    CHUNK_SIZE = 256
    # Where the plugin's part of the note starts; everything above is the
    # user's. Older files have no "# Excalidraw Data" heading.
    DATA_START = /^(%%\n+)?(?:# Excalidraw Data|##? Text Elements|##? Drawing)(?:\n|$)/
    DRAWING_START = /^##? Drawing\n/
    EMBEDDED_FILES = /^## Embedded Files\n.*/m

    class << self
      # A new note holding scene, a Hash with "elements", "appState" and
      # "files" as Excalidraw saves them.
      def render(scene, compress: true)
        HEADER + data(scene, compress: compress, commented_out: false, embedded_files: "")
      end

      # source with its drawing replaced by scene. What the user wrote above
      # the drawing, the Embedded Files list and whether the drawing is
      # compressed stay as they were.
      def rewrite(source, scene)
        match = DATA_START.match(source) or raise Diagram::ParseError, "no Excalidraw data to replace"
        commented_out = !match[1].nil?
        rest = match.post_match
        before_drawing = (drawing = DRAWING_START.match(rest)) ? drawing.pre_match : rest
        before_drawing = before_drawing.delete_suffix("%%\n") unless commented_out

        match.pre_match + data(
          scene,
          compress: source.include?("```compressed-json\n"),
          commented_out: commented_out,
          embedded_files: before_drawing[EMBEDDED_FILES] || ""
        )
      end

      private

      def data(scene, compress:, commented_out:, embedded_files:)
        live = scene["elements"].select { |e| !e["isDeleted"] && e["id"].to_s.length == ID_LENGTH }
        texts, others = live.partition { |e| e["type"] == "text" }
        out = +(commented_out ? "%%\n" : "")
        out << "# Excalidraw Data\n\n## Text Elements\n"
        texts.each { |e| out << "#{e["rawText"] || e["originalText"] || e["text"]} ^#{e["id"]}\n\n" }
        linked = others.select { |e| e["link"] } + texts.select { |e| e["link"] }
        unless linked.empty?
          out << "## Element Links\n"
          linked.each { |e| out << "#{e["id"]}: #{e["link"]}\n\n" }
        end
        out << embedded_files
        out << "%%\n" unless commented_out
        out << drawing(scene, compress)
      end

      def drawing(scene, compress)
        json = JSON.pretty_generate(scene, indent: "\t")
        return "## Drawing\n```json\n#{json}\n```\n%%" unless compress

        chunks = LZString.compress_to_base64(json).scan(/.{1,#{CHUNK_SIZE}}/o)
        "## Drawing\n```compressed-json\n#{chunks.join("\n\n")}\n```\n%%"
      end
    end
  end
end
