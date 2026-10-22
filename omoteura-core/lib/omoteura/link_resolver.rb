# frozen_string_literal: true

module Omoteura
  # Turns an omoteura: link into a file and line range.
  #
  #   omoteura:#<fragment>         a place in the code file the diagram is attached to
  #   omoteura:<path>#<fragment>   a place in another file
  #   omoteura:<path>              a whole file
  #
  # A fragment is tried, in order, as a spec description (in full, or a
  # trailing part of one), a method name, then the start of a statement.
  # The first kind that matches decides: one match resolves the link, more
  # than one makes it ambiguous, and none moves on to the next kind.
  class LinkResolver
    Target = Data.define(:path, :start_line, :end_line)

    Result = Data.define(:link, :target, :error) do
      def broken?
        !error.nil?
      end
    end

    IDENTIFIER_CHAR = /[[:alnum:]_?!]/

    attr_reader :config

    def initialize(config)
      @config = config
      @indexes = {}
    end

    # context_path is the code file the diagram is attached to, relative to
    # the project root. It is needed only for links without a path.
    def resolve(link, context_path: nil)
      body = link.to_s.delete_prefix(Diagram::LINK_PREFIX)
      path, fragment = body.split("#", 2)
      path = path.to_s
      fragment = fragment&.strip
      return failure(link, "has an empty #fragment") if fragment == ""

      path = context_path if path.empty?
      return failure(link, "has no file and the diagram is not attached to one") if path.nil?

      file = config.expand(path) or return failure(link, "points outside the project")
      return failure(link, "points to #{path}, which does not exist") unless File.file?(file)

      index = index_for(file)
      return success(link, Target.new(path: path, start_line: 1, end_line: index.line_count)) if fragment.nil?

      find(index, fragment, link, path)
    end

    private

    def find(index, fragment, link, path)
      [
        index.spec_entries.select { |e| spec_match?(e.name, fragment) },
        index.method_entries.select { |e| e.name == fragment },
        index.statement_entries.select { |e| statement_match?(e.name, fragment) }
      ].each do |candidates|
        candidates = narrow_spec_matches(candidates, fragment)
        case candidates.size
        when 0 then next
        when 1 then return success(link, Target.new(path: path, start_line: candidates.first.start_line, end_line: candidates.first.end_line))
        else
          lines = candidates.map(&:start_line).join(", ")
          return failure(link, "matches #{candidates.size} places in #{path} (lines #{lines})")
        end
      end
      failure(link, "matches nothing in #{path}")
    end

    # A trailing part must start at a word boundary: "email 一意であること"
    # matches "User validations email 一意であること" but "ail 一意であること"
    # does not. "#name" and ".name" may follow a module name directly.
    def spec_match?(name, fragment)
      return true if name == fragment
      return false unless name.end_with?(fragment)

      before = name[-fragment.length - 1]
      before == " " || fragment.start_with?("#", ".", "::")
    end

    # An exact description beats descriptions that only end with it.
    def narrow_spec_matches(candidates, fragment)
      exact = candidates.select { |e| e.name == fragment }
      exact.empty? ? candidates : exact
    end

    # "validates :email" matches "validates :email, presence: true" but not
    # "validates :email_confirmation".
    def statement_match?(first_line, fragment)
      first_line.start_with?(fragment) && !first_line[fragment.length]&.match?(IDENTIFIER_CHAR)
    end

    def index_for(file)
      @indexes[file] ||= SourceIndex.parse_file(file)
    end

    def success(link, target)
      Result.new(link: link, target: target, error: nil)
    end

    def failure(link, reason)
      Result.new(link: link, target: nil, error: "#{link} #{reason}")
    end
  end
end
