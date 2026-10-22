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
    WORD_END_BYTES = [" ", "#", ".", ":"].map(&:ord).freeze

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

    # Each kind is only searched when the ones before it found nothing.
    # filter_map rather than select: select sizes its result for the whole
    # input even when nothing matches, about 9 KB per scan of a large file,
    # while filter_map grows its result only for matches. (.standard.yml
    # turns off the cop that prefers select here.)
    def find(index, fragment, link, path)
      candidates = spec_candidates(index.spec_entries, fragment)
      candidates = index.method_entries.filter_map { |e| e if e.name == fragment } if candidates.empty?
      candidates = index.statement_entries.filter_map { |e| e if statement_match?(e.name, fragment) } if candidates.empty?

      case candidates.size
      when 0 then failure(link, "matches nothing in #{path}")
      when 1 then success(link, Target.new(path: path, start_line: candidates.first.start_line, end_line: candidates.first.end_line))
      else
        lines = candidates.map(&:start_line).join(", ")
        failure(link, "matches #{candidates.size} places in #{path} (lines #{lines})")
      end
    end

    # An exact description beats descriptions that only end with it.
    def spec_candidates(entries, fragment)
      exact = entries.filter_map { |e| e if e.name == fragment }
      exact.empty? ? entries.filter_map { |e| e if spec_suffix_match?(e.name, fragment) } : exact
    end

    # A trailing part must start at a word boundary: "email 一意であること"
    # matches "User validations email 一意であること" but "ail 一意であること"
    # does not. In "User#display_name", both "#display_name" and
    # "display_name" match, as "#", "." and "::" also end a word.
    # Compares bytes so that checking thousands of entries allocates nothing.
    def spec_suffix_match?(name, fragment)
      return false unless name.bytesize > fragment.bytesize && name.end_with?(fragment)

      fragment.start_with?("#", ".", "::") || WORD_END_BYTES.include?(name.getbyte(name.bytesize - fragment.bytesize - 1))
    end

    # "validates :email" matches "validates :email, presence: true" but not
    # "validates :email_confirmation".
    def statement_match?(first_line, fragment)
      return false unless first_line.start_with?(fragment)

      following = first_line.getbyte(fragment.bytesize)
      return true if following.nil?
      # Only a non-ASCII character needs the regexp; ASCII is checked by byte.
      return !first_line[fragment.length].match?(IDENTIFIER_CHAR) if following >= 0x80

      !(following == 95 || following == 33 || following == 63 || (48..57).cover?(following) ||
        (65..90).cover?(following) || (97..122).cover?(following))
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
