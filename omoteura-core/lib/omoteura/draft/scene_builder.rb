# frozen_string_literal: true

require "digest"

module Omoteura
  class Draft
    # Builds Excalidraw elements laid out in columns: a title, then for each
    # column a heading and a stack of boxes, each box labelled and linked.
    # Element ids and seeds derive from the file and the box, so drafting
    # the same code twice gives the same drawing.
    class SceneBuilder
      Box = Data.define(:label, :link)
      Heading = Data.define(:text, :link)
      Column = Data.define(:heading, :items)

      INK = "#1e1e1e"
      FONT_EXCALIFONT = 5
      BOX_FONT_SIZE = 16
      HEADING_FONT_SIZE = 20
      TITLE_FONT_SIZE = 28
      LINE_HEIGHT = 1.25
      COLUMN_WIDTH = 280
      COLUMN_GAP = 60
      BOX_GAP = 16
      BOX_PADDING = 14
      MAX_LABEL_WIDTH = COLUMN_WIDTH - 2 * BOX_PADDING
      # A word with its trailing space, or one Japanese or Chinese character.
      WRAP_TOKENS = /[\p{Han}\p{Hiragana}\p{Katakana}ー、。]|[^\p{Han}\p{Hiragana}\p{Katakana}ー、。\s]+\s*|\s+/

      def initialize(code_path, updated: (Time.now.to_f * 1000).to_i)
        @code_path = code_path
        @updated = updated
        @elements = []
      end

      # columns are Columns whose items are Boxes, or Headings for a nested
      # group, in reading order.
      def build(title, columns)
        add_text("title", title, x: 0, y: 0, size: TITLE_FONT_SIZE)
        top = TITLE_FONT_SIZE * LINE_HEIGHT + 32
        columns.each_with_index do |column, index|
          x = index * (COLUMN_WIDTH + COLUMN_GAP)
          y = top
          if column.heading
            add_text("column #{index}", column.heading.text, x: x, y: y, size: HEADING_FONT_SIZE, link: column.heading.link)
            y += HEADING_FONT_SIZE * LINE_HEIGHT + BOX_GAP
          end
          column.items.each_with_index do |item, row|
            y += item.is_a?(Heading) ? place_heading(item, index, row, x, y) : place_box(item, index, row, x, y)
          end
        end
        @elements
      end

      private

      def place_heading(heading, column, row, x, y)
        add_text("heading #{column}/#{row}", heading.text, x: x, y: y + 8, size: BOX_FONT_SIZE, link: heading.link)
        8 + BOX_FONT_SIZE * LINE_HEIGHT + BOX_GAP / 2
      end

      def place_box(box, column, row, x, y)
        key = "box #{column}/#{row}"
        lines = wrap(box.label, MAX_LABEL_WIDTH, BOX_FONT_SIZE)
        text_height = lines.size * BOX_FONT_SIZE * LINE_HEIGHT
        height = (text_height + 2 * BOX_PADDING).round
        box_id = id_for(key)
        label_id = id_for("#{key} label")

        @elements << base(key, type: "rectangle", x: x, y: y, width: COLUMN_WIDTH, height: height).merge(
          "roundness" => {"type" => 3},
          "boundElements" => [{"type" => "text", "id" => label_id}],
          "link" => box.link
        )
        text = lines.join("\n")
        width = lines.map { |line| text_width(line, BOX_FONT_SIZE) }.max
        @elements << base("#{key} label", type: "text", x: x + (COLUMN_WIDTH - width) / 2.0, y: y + BOX_PADDING,
          width: width, height: text_height).merge(text_fields(text, BOX_FONT_SIZE, container: box_id))
        height + BOX_GAP
      end

      def add_text(key, text, x:, y:, size:, link: nil)
        width = text.lines.map { |line| text_width(line.chomp, size) }.max
        @elements << base(key, type: "text", x: x, y: y, width: width, height: size * LINE_HEIGHT)
          .merge(text_fields(text, size, container: nil))
          .merge("link" => link)
      end

      def text_fields(text, size, container:)
        {
          "text" => text,
          "originalText" => text,
          "fontSize" => size,
          "fontFamily" => FONT_EXCALIFONT,
          "textAlign" => container ? "center" : "left",
          "verticalAlign" => container ? "middle" : "top",
          "containerId" => container,
          "autoResize" => true,
          "lineHeight" => LINE_HEIGHT
        }
      end

      def base(key, type:, x:, y:, width:, height:)
        {
          "id" => id_for(key),
          "type" => type,
          "x" => x,
          "y" => y,
          "width" => width,
          "height" => height,
          "angle" => 0,
          "strokeColor" => INK,
          "backgroundColor" => "transparent",
          "fillStyle" => "solid",
          "strokeWidth" => 2,
          "strokeStyle" => "solid",
          "roughness" => 1,
          "opacity" => 100,
          "groupIds" => [],
          "frameId" => nil,
          "index" => nil,
          "roundness" => nil,
          "seed" => seed_for(key),
          "version" => 1,
          "versionNonce" => seed_for("#{key} nonce"),
          "isDeleted" => false,
          "boundElements" => nil,
          "updated" => @updated,
          "link" => nil,
          "locked" => false
        }
      end

      def id_for(key)
        Digest::SHA256.hexdigest("#{@code_path}\0#{key}")[0, 20]
      end

      def seed_for(key)
        Digest::SHA256.hexdigest("#{@code_path}\0#{key}")[0, 8].to_i(16) % 2**31
      end

      # An estimate, since the real width depends on the font: Excalidraw
      # measures text again when the drawing opens.
      def text_width(text, size)
        text.each_char.sum { |char| char.ascii_only? ? size * 0.55 : size * 1.0 }.ceil
      end

      # Breaks between words, or between characters in Japanese and Chinese
      # text, which has no spaces; a word wider than a line is split.
      def wrap(text, max_width, size)
        lines = [+""]
        text.scan(WRAP_TOKENS).each do |token|
          if lines.last != "" && text_width(lines.last + token.rstrip, size) > max_width
            lines.last.rstrip!
            lines << +""
            token = token.lstrip
          end
          token.each_char do |char|
            lines << +"" if lines.last != "" && text_width(lines.last + char, size) > max_width
            lines.last << char
          end
        end
        lines.each(&:rstrip!)
      end
    end
  end
end
