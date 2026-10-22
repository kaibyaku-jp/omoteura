# frozen_string_literal: true

require "omoteura/core/version"

module Omoteura
  class Error < StandardError; end
end

require "omoteura/checker"
require "omoteura/config"
require "omoteura/coverage_report"
require "omoteura/diagram"
require "omoteura/draft"
require "omoteura/inspector"
require "omoteura/link_resolver"
require "omoteura/magic_comment"
require "omoteura/minimum_ruby"
require "omoteura/obsidian"
require "omoteura/outline"
require "omoteura/project"
require "omoteura/resolver"
require "omoteura/source_index"
require "omoteura/test_results"
require "omoteura/writer"
