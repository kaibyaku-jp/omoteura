# frozen_string_literal: true

require "prism"

module Omoteura
  # Finds the "# omoteura: <path>" comment that attaches a diagram to a
  # Ruby file. Only comments on their own line before the first statement
  # or after the last one count; comments inside the code are ignored.
  module MagicComment
    class Duplicate < Error; end

    PATTERN = /\A#[ \t]*omoteura:[ \t]*(\S(?:.*\S)?)[ \t]*\z/

    module_function

    # Returns the diagram path written in the magic comment, or nil.
    def find(source, path: "source")
      result = Prism.parse(source)
      statements = result.value.statements.body
      first_code = statements.first&.location&.start_offset
      last_code = statements.last&.location&.end_offset

      paths = result.comments.filter_map do |comment|
        next if !comment.is_a?(Prism::InlineComment) || comment.trailing?

        location = comment.location
        outside_code = first_code.nil? || location.end_offset <= first_code || location.start_offset >= last_code
        PATTERN.match(location.slice)&.[](1) if outside_code
      end

      raise Duplicate, "#{path} has #{paths.size} omoteura magic comments; keep only one" if paths.size > 1

      paths.first
    end
  end
end
