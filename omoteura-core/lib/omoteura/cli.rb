# frozen_string_literal: true

require "json"
require "optparse"
require "omoteura/core"

module Omoteura
  # The omoteura command. #run returns the exit status: 0 when everything
  # is fine, 1 when check finds problems or save refuses to write, 2 for
  # usage or settings errors.
  class CLI
    USAGE = <<~TEXT
      Usage: omoteura <command> [options]

      Commands:
        check     Report broken omoteura: links and diagrams not attached to code
        inspect   Print what an editor needs about one code file, as JSON
        diagram   Print what an editor needs to show one diagram, as JSON
        coverage  Print which declarations and methods of one file its specs cover, as JSON
        draft     Draft a diagram from code, as a starting point to draw on
        save      Save a drawing an editor changed, read as JSON from stdin
        version   Print the version

      Run "omoteura <command> --help" for a command's options.
    TEXT

    def initialize(out: $stdout, err: $stderr, input: $stdin)
      @out = out
      @err = err
      @input = input
    end

    def run(argv)
      command, *args = argv
      case command
      when "check" then check(args)
      when "inspect" then editor_report(args, "inspect FILE") { |config, results, file| Inspector.new(config, results: results).report(file) }
      when "diagram" then editor_report(args, "diagram FILE") { |config, results, file| Inspector.new(config, results: results).diagram_report(file) }
      when "coverage" then editor_report(args, "coverage FILE") { |config, results, file| CoverageReport.new(config, results: results).report(file) }
      when "draft" then draft(args)
      when "save" then save(args)
      when "version", "--version", "-v"
        @out.puts VERSION
        0
      when "help", "--help", "-h"
        @out.puts USAGE
        0
      when nil
        @err.puts USAGE
        2
      else
        @err.puts "omoteura: unknown command '#{command}'", "", USAGE
        2
      end
    end

    private

    def check(args)
      options = {root: Dir.pwd, format: "text"}
      parser = OptionParser.new do |o|
        o.banner = "Usage: omoteura check [options]"
        o.on("--root DIR", "Project root (default: the current directory)") { |dir| options[:root] = dir }
        o.on("--format FORMAT", %w[text github], "text, or github for GitHub Actions annotations (default: text)") { |f| options[:format] = f }
        o.on("-h", "--help", "Show this help") do
          @out.puts o
          return 0
        end
      end
      parser.parse!(args)

      report = Checker.new(Config.load(options[:root])).run
      report.problems.each { |problem| @out.puts format_problem(problem, options[:format]) }
      @out.puts summary(report)
      report.ok? ? 0 : 1
    rescue OptionParser::ParseError, Config::Invalid => e
      @err.puts "omoteura: #{e.message}"
      2
    end

    # The commands editors run: one file in, one line of JSON out.
    def editor_report(args, usage)
      options = {root: Dir.pwd, results: TestResults::DEFAULT_PATH}
      parser = OptionParser.new do |o|
        o.banner = "Usage: omoteura #{usage} [options]"
        o.on("--root DIR", "Project root (default: the current directory)") { |dir| options[:root] = dir }
        o.on("--results PATH", "Test results, relative to the root (default: #{TestResults::DEFAULT_PATH})") { |path| options[:results] = path }
        o.on("-h", "--help", "Show this help") do
          @out.puts o
          return 0
        end
      end
      parser.parse!(args)
      raise OptionParser::InvalidArgument, "expected exactly one FILE" unless args.size == 1

      config = Config.load(options[:root])
      file = File.expand_path(args.first)
      raise OptionParser::InvalidArgument, "#{args.first} is not a file" unless File.file?(file)
      raise OptionParser::InvalidArgument, "#{args.first} is outside #{config.root}" unless config.expand(file)

      results = TestResults.load(File.expand_path(options[:results], config.root))
      @out.puts JSON.generate(yield(config, results, file))
      0
    rescue OptionParser::ParseError, Config::Invalid, TestResults::Invalid => e
      @err.puts "omoteura: #{e.message}"
      2
    end

    def draft(args)
      options = {root: Dir.pwd, only: Draft::CATEGORIES, out: nil, format: "json", dry_run: false}
      parser = OptionParser.new do |o|
        o.banner = "Usage: omoteura draft FILE_OR_GLOB... [options]"
        o.on("--root DIR", "Project root (default: the current directory)") { |dir| options[:root] = dir }
        o.on("--out PATH", "Write here instead, relative to the root: a file or a directory") { |path| options[:out] = path }
        o.on("--format FORMAT", %w[json md], "json for .excalidraw (default), or md for an Obsidian .excalidraw.md") { |f| options[:format] = f }
        o.on("--only LIST", Array, "For code other than specs, draw only: #{Draft::CATEGORIES.join(", ")}") { |list| options[:only] = list }
        o.on("--dry-run", "Show what would be written without writing") { options[:dry_run] = true }
        o.on("-h", "--help", "Show this help") do
          @out.puts o
          return 0
        end
      end
      parser.parse!(args)
      raise OptionParser::InvalidArgument, "expected at least one FILE" if args.empty?
      unknown = options[:only] - Draft::CATEGORIES
      raise OptionParser::InvalidArgument, "--only does not know #{unknown.join(", ")}" unless unknown.empty?

      config = Config.load(options[:root])
      paths = draft_paths(args, config)
      format = (options[:format] == "md") ? :obsidian : :excalidraw
      out_file = options[:out]&.match?(/\.excalidraw(?:\.md)?\z/)
      if out_file && !options[:out].end_with?(Draft::EXTENSIONS.fetch(format))
        raise OptionParser::InvalidArgument, "--out #{options[:out]} does not end in #{Draft::EXTENSIONS.fetch(format)}, as --format #{options[:format]} writes"
      end
      if out_file && paths.size > 1
        raise OptionParser::InvalidArgument, "--out names one file, but #{paths.size} files match"
      end

      drafter = Draft.new(config, only: options[:only], out: options[:out], format: format)
      paths.each { |path| @out.puts draft_line(drafter.draft(path, dry_run: options[:dry_run]), options[:dry_run]) }
      0
    rescue OptionParser::ParseError, Config::Invalid => e
      @err.puts "omoteura: #{e.message}"
      2
    end

    # Prints one line of JSON: where the drawing went and the digest of
    # what was written, or why nothing was.
    def save(args)
      options = {root: Dir.pwd, if_unchanged: nil}
      parser = OptionParser.new do |o|
        o.banner = "Usage: omoteura save FILE [options] < drawing.json"
        o.on("--root DIR", "Project root (default: the current directory)") { |dir| options[:root] = dir }
        o.on("--if-unchanged DIGEST", "Refuse to save unless the file's SHA-256 is still DIGEST") { |digest| options[:if_unchanged] = digest }
        o.on("-h", "--help", "Show this help") do
          @out.puts o
          return 0
        end
      end
      parser.parse!(args)
      raise OptionParser::InvalidArgument, "expected exactly one FILE" unless args.size == 1

      config = Config.load(options[:root])
      begin
        result = Writer.new(config).save(File.expand_path(args.first), JSON.parse(@input.read), if_unchanged: options[:if_unchanged])
        @out.puts JSON.generate(version: Inspector::FORMAT_VERSION, diagram_path: result.diagram_path, digest: result.digest, error: nil, conflict: false)
        0
      rescue JSON::ParserError, Writer::Invalid, Writer::Conflict, Diagram::ParseError => e
        error = e.is_a?(JSON::ParserError) ? "the drawing is not valid JSON" : e.message
        @out.puts JSON.generate(version: Inspector::FORMAT_VERSION, diagram_path: nil, digest: nil, error: error, conflict: e.is_a?(Writer::Conflict))
        1
      end
    rescue OptionParser::ParseError, Config::Invalid => e
      @err.puts "omoteura: #{e.message}"
      2
    end

    # Arguments are files or globs, relative to the root.
    def draft_paths(args, config)
      paths = args.flat_map do |arg|
        matches = arg.match?(/[*?\[{]/) ? Dir.glob(arg, base: config.root).sort : [arg]
        raise OptionParser::InvalidArgument, "#{arg} matches no files" if matches.empty?

        matches.map do |path|
          file = config.expand(path) or raise OptionParser::InvalidArgument, "#{path} is outside #{config.root}"
          raise OptionParser::InvalidArgument, "#{path} is not a file" unless File.file?(file)

          config.relative(file)
        end
      end
      paths.uniq
    end

    def draft_line(result, dry_run)
      shapes = "#{result.shape_count} #{(result.shape_count == 1) ? "shape" : "shapes"}"
      verb = dry_run ? "would write" : "wrote"
      case result.status
      when :written then "#{verb} #{result.diagram_path} (#{shapes})"
      when :draft
        "#{verb} #{result.diagram_path} (#{shapes}) beside the diagram #{result.code_path} already has; copy what you need, then delete it"
      when :exists then "skipped #{result.code_path}: #{result.diagram_path} already exists; delete it to draft again"
      when :empty then "skipped #{result.code_path}: nothing to draw"
      end
    end

    def format_problem(problem, format)
      message = problem.shape ? "#{problem.message} (shape \"#{problem.shape}\")" : problem.message
      if format == "github"
        "::error file=#{escape_property(problem.file)},title=omoteura check::#{escape_data(message)}"
      else
        "#{problem.file}: #{message}"
      end
    end

    def summary(report)
      checked = "Checked #{count(report.diagram_count, "diagram")} and #{count(report.link_count, "link")}"
      report.ok? ? "#{checked}: no problems." : "#{checked}: #{count(report.problems.size, "problem")}."
    end

    def count(number, noun)
      "#{number} #{noun}#{"s" unless number == 1}"
    end

    # Escaping rules for GitHub Actions workflow commands.
    def escape_data(text)
      text.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
    end

    def escape_property(text)
      escape_data(text).gsub(":", "%3A").gsub(",", "%2C")
    end
  end
end
