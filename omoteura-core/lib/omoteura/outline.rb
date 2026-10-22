# frozen_string_literal: true

module Omoteura
  # What a code file declares, the way a reader of a Rails model groups it:
  # validations, associations, callbacks, scopes and enums, then the public
  # methods. Read from a SourceIndex, without loading Rails or the code.
  class Outline
    KINDS = %w[validations associations callbacks scopes enums methods].freeze
    DECLARATIONS = {
      "validations" => /\A(?:validates?|validates_\w+)\b/,
      "associations" => /\A(?:has_many|has_one|belongs_to|has_and_belongs_to_many)\b/,
      "callbacks" => /\A(?:before|after|around)_\w+\b/,
      "scopes" => /\Ascope\b/,
      "enums" => /\Aenum\b/
    }.freeze

    # entry is the SourceIndex entry the item was read from; its name is the
    # statement's first line, or the method's name.
    Item = Data.define(:kind, :entry)

    def initialize(index)
      @index = index
    end

    # Items of the given kinds, by kind in KINDS order, then by line.
    def items(only: KINDS)
      KINDS.flat_map do |kind|
        next [] unless only.include?(kind)

        entries = (kind == "methods") ? public_methods : @index.statement_entries.select { |e| e.name.match?(DECLARATIONS[kind]) }
        entries.map { |entry| Item.new(kind: kind, entry: entry) }
      end
    end

    private

    # Methods after a bare private or protected in the same class, or
    # defined with private def, are left out, and so is initialize, which
    # Ruby makes private and callers reach through new.
    def public_methods
      statements = @index.statement_entries
      classes = statements.select { |e| e.name.match?(/\A(?:class|module)\b/) }
      hidden_from = statements.select { |e| %w[private protected].include?(e.name) }
      hidden_names = statements.filter_map { |e| e.name[/\A(?:private|protected)\s+def\s+(?:self\.)?(\w+[?!=]?)/, 1] }
      @index.method_entries.reject do |method|
        owner = classes.select { |c| c.start_line < method.start_line && c.end_line >= method.end_line }.max_by(&:start_line)
        method.name == "initialize" || hidden_names.include?(method.name.delete_prefix("self.")) ||
          hidden_from.any? { |h| h.start_line < method.start_line && (!owner || (h.start_line > owner.start_line && h.end_line <= owner.end_line)) }
      end
    end
  end
end
