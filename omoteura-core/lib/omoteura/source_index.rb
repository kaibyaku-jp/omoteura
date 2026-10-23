# frozen_string_literal: true

require "prism"

module Omoteura
  # The places in a Ruby file that an omoteura: link can point at, found by
  # parsing the file with Prism without loading or running it.
  class SourceIndex
    # kind is :spec (an example group or example), :method or :statement.
    # For :spec, name is the full description as RSpec builds it, and group
    # tells example groups from examples; for :statement, name is the first
    # line of the statement.
    # Every entry is built with all five members: a default would need an
    # initialize override that allocates on each of thousands of entries.
    Entry = Data.define(:kind, :name, :start_line, :end_line, :group)

    attr_reader :entries, :line_count, :spec_entries, :method_entries, :statement_entries

    def self.parse_file(path)
      new(File.read(path, encoding: Encoding::UTF_8))
    end

    def initialize(source)
      visitor = Visitor.new(source)
      Prism.parse(source).value.accept(visitor)
      @entries = visitor.entries.freeze
      # Grouped once here; link resolution reads these for every link.
      by_kind = @entries.group_by(&:kind)
      @spec_entries = by_kind.fetch(:spec, []).freeze
      @method_entries = by_kind.fetch(:method, []).freeze
      @statement_entries = by_kind.fetch(:statement, []).freeze
      @line_count = source.count("\n") + ((source.empty? || source.end_with?("\n")) ? 0 : 1)
    end

    class Visitor < Prism::Visitor
      EXAMPLE_GROUPS = %i[describe context feature example_group xdescribe xcontext xfeature fdescribe fcontext ffeature].freeze
      EXAMPLES = %i[it specify example scenario xit xspecify xexample xscenario fit fspecify fexample fscenario].freeze

      # test_class is true for a Minitest test class, where test "…" blocks
      # are examples.
      Group = Data.define(:description, :module, :test_class)

      attr_reader :entries

      def initialize(source)
        super()
        @source = source
        @entries = []
        # Enclosing example groups. A nil description means a parent could
        # not be read statically, so nothing below it has a known one.
        @groups = []
      end

      def visit_statements_node(node)
        node.body.each { |statement| add(:statement, first_line(statement), statement) }
        super
      end

      def visit_def_node(node)
        name = node.receiver.is_a?(Prism::SelfNode) ? "self.#{node.name}" : node.name.name
        add(:method, name, node)
        # def test_… in a test class is a test as much as test "…" is. A link
        # by its name finds the example first, at the same line.
        if node.receiver.nil? && @groups.last&.test_class && name.start_with?("test_")
          description = full_description(name)
          add(:spec, description, node) if description
        end
        super
      end

      # A Minitest test class is an example group described by its name, as
      # "UserTest", so that its tests are examples like RSpec's.
      def visit_class_node(node)
        return super unless test_class?(node)

        description = full_description(node.constant_path.slice)
        add(:spec, description, node, group: true) if description
        @groups.push(Group.new(description: description, module: true, test_class: true))
        super
        @groups.pop
      end

      def visit_call_node(node)
        return visit_minitest_test(node) if minitest_test?(node)
        return super unless spec_call?(node)

        part, is_module = description_of(node)
        description = full_description(part)
        add(:spec, description, node, group: EXAMPLE_GROUPS.include?(node.name)) if description

        if EXAMPLE_GROUPS.include?(node.name)
          @groups.push(Group.new(description: description, module: is_module, test_class: false))
          super
          @groups.pop
        else
          super
        end
      end

      private

      # test "requires an email" do … end, as ActiveSupport::TestCase defines
      # tests, directly in a test class.
      def minitest_test?(node)
        node.name == :test && node.receiver.nil? && node.block && @groups.last&.test_class &&
          node.arguments&.arguments&.first.is_a?(Prism::StringNode) || false
      end

      def visit_minitest_test(node)
        description = full_description(node.arguments.arguments.first.unescaped)
        add(:spec, description, node) if description
        # Groups opened inside the test are not examples of the class.
        @groups.push(Group.new(description: nil, module: false, test_class: false))
        visit_child_nodes(node)
        @groups.pop
      end

      # A class named like UserTest, or one that inherits from a class named
      # like ActiveSupport::TestCase or Minitest::Test. Symbols are compared
      # so that ordinary classes cost no allocation.
      def test_class?(node)
        return true if node.name.end_with?("Test")

        superclass = node.superclass
        (superclass.is_a?(Prism::ConstantReadNode) || superclass.is_a?(Prism::ConstantPathNode)) &&
          superclass.name.end_with?("Test", "TestCase")
      end

      # Cuts the statement's first line out of the source by byte offsets.
      # Slicing the whole statement would copy most of the file for every
      # class or describe block, and again for each level of nesting.
      def first_line(node)
        start = node.location.start_offset
        stop = @source.byteindex("\n", start) || @source.bytesize
        line = @source.byteslice(start, stop - start)
        line.rstrip!
        line
      end

      def add(kind, name, node, group: false)
        location = node.location
        @entries << Entry.new(kind: kind, name: name, start_line: location.start_line, end_line: location.end_line, group: group)
      end

      def spec_call?(node)
        return false unless EXAMPLE_GROUPS.include?(node.name) || EXAMPLES.include?(node.name)

        receiver = node.receiver
        receiver.nil? || (receiver.is_a?(Prism::ConstantReadNode) && receiver.name == :RSpec)
      end

      # RSpec takes the first argument as the description, plus a second
      # one when it is a string; later symbols and hashes are metadata.
      def description_of(node)
        first, second = node.arguments&.arguments
        part, is_module = literal(first)
        part = "#{part} #{second.unescaped}" if part && second.is_a?(Prism::StringNode)
        [part, is_module]
      end

      def literal(node)
        case node
        when Prism::StringNode, Prism::SymbolNode then [node.unescaped, false]
        when Prism::ConstantReadNode, Prism::ConstantPathNode then [node.slice, true]
        else [nil, false]
        end
      end

      # Mirrors RSpec's description building: parts are joined with a space,
      # except that "#method", ".method" and "::Const" attach directly to a
      # parent described by a module, as in "User#display_name".
      def full_description(part)
        return nil if part.nil?

        parent = @groups.last
        return part if parent.nil?
        return nil if parent.description.nil?

        separator = (parent.module && part.match?(/\A(?:#|::|\.)/)) ? "" : " "
        "#{parent.description}#{separator}#{part}"
      end
    end
  end
end
