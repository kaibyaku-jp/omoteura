# frozen_string_literal: true

require "omoteura/core/version"

module Omoteura
  class Error < StandardError; end
end

require "omoteura/config"
require "omoteura/diagram"
require "omoteura/magic_comment"
require "omoteura/resolver"
