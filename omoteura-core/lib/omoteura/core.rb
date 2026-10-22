# frozen_string_literal: true

require "omoteura/core/version"

module Omoteura
  class Error < StandardError; end
end

require "omoteura/checker"
require "omoteura/config"
require "omoteura/diagram"
require "omoteura/inspector"
require "omoteura/link_resolver"
require "omoteura/magic_comment"
require "omoteura/resolver"
require "omoteura/source_index"
require "omoteura/test_results"
