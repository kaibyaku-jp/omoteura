# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Omoteura
  # Saves a drawing an editor changed, in the format of the file it goes
  # to: a .excalidraw file as JSON, an Obsidian note through
  # Obsidian.rewrite so the rest of the note stays as it was.
  #
  # The file is replaced in one step, so a failed save leaves it whole.
  # Given the digest of the file as the editor read it, a save that would
  # overwrite someone else's change is refused instead.
  class Writer
    class Conflict < Error; end

    class Invalid < Error; end

    Result = Data.define(:diagram_path, :digest)

    NEW_FILE_EXTENSIONS = [".excalidraw", ".excalidraw.md"].freeze

    def self.digest(content)
      Digest::SHA256.hexdigest(content)
    end

    def initialize(config)
      @config = config
    end

    # data is the drawing as Excalidraw saves it: a Hash with "elements",
    # and usually "type", "version", "source", "appState" and "files".
    def save(diagram_path, data, if_unchanged: nil)
      file = @config.expand(diagram_path) or raise Invalid, "#{diagram_path} is outside #{@config.root}"
      raise Invalid, "the drawing has no elements list" unless data.is_a?(Hash) && data["elements"].is_a?(Array)

      file = File.realpath(file) if File.symlink?(file)
      existing = File.exist?(file) ? File.binread(file) : nil
      if if_unchanged && (existing.nil? || self.class.digest(existing) != if_unchanged)
        raise Conflict, "#{@config.relative(file)} changed since it was read"
      end

      content = render(file, data, existing)
      replace(file, content)
      Result.new(diagram_path: @config.relative(file), digest: self.class.digest(content))
    end

    private

    def render(file, data, existing)
      if existing
        raise Invalid, "#{@config.relative(file)} is not an Excalidraw drawing" unless Diagram.diagram_file?(file)
      elsif NEW_FILE_EXTENSIONS.none? { |ext| file.end_with?(ext) }
        raise Invalid, "a new drawing must end in #{NEW_FILE_EXTENSIONS.join(" or ")}"
      end

      return JSON.pretty_generate(data) + "\n" if file.end_with?(".excalidraw")

      existing ? Obsidian.rewrite(existing.force_encoding(Encoding::UTF_8), keep_raw_text(file, data)) : Obsidian.render(data)
    end

    # The plugin keeps the markdown behind a text element, such as a
    # [[wiki link]], in rawText, and lists it in the note. Excalidraw does
    # not know it, so it is carried over from the saved drawing while the
    # text is unchanged, and dropped once the text was edited.
    def keep_raw_text(file, data)
      before = Diagram.load(file).scene["elements"].to_h { |e| [e["id"], e] }
      elements = data["elements"].map do |element|
        next element unless element.is_a?(Hash) && element["type"] == "text"

        old = before[element["id"]]
        raw = old["rawText"] if old && old["originalText"] == element["originalText"]
        raw ? element.merge("rawText" => raw) : element.except("rawText")
      end
      data.merge("elements" => elements)
    end

    def replace(file, content)
      FileUtils.mkdir_p(File.dirname(file))
      temp = File.join(File.dirname(file), ".#{File.basename(file)}.#{Process.pid}.omoteura")
      File.binwrite(temp, content)
      File.chmod(File.stat(file).mode, temp) if File.exist?(file)
      File.rename(temp, file)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end
  end
end
