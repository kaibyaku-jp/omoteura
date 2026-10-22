# frozen_string_literal: true

require "optparse"
require "omoteura/core"

module Omoteura
  # The omoteura command. #run returns the exit status: 0 when everything
  # is fine, 1 when check finds problems, 2 for usage or settings errors.
  class CLI
    USAGE = <<~TEXT
      Usage: omoteura <command> [options]

      Commands:
        check     Report broken omoteura: links and diagrams not attached to code
        version   Print the version

      Run "omoteura <command> --help" for a command's options.
    TEXT

    def initialize(out: $stdout, err: $stderr)
      @out = out
      @err = err
    end

    def run(argv)
      command, *args = argv
      case command
      when "check" then check(args)
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
