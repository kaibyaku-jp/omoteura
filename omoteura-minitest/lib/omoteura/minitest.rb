# frozen_string_literal: true

require "minitest"
require "omoteura/minitest/reporter"

module Omoteura
  # Records Minitest results for the editor. Require it from
  # test/test_helper.rb:
  #
  #   require "omoteura/minitest"
  #
  # Each run then writes tmp/omoteura/results.json, or the path in the
  # OMOTEURA_RESULTS environment variable, as Omoteura::RSpec::Formatter
  # does for RSpec. Nothing is written unless this file is required.
  module Minitest
  end
end

module Minitest
  # Called by Minitest.init_plugins for each name in Minitest.extensions.
  def self.plugin_omoteura_init(_options)
    reporter << Omoteura::Minitest::Reporter.new(ENV.fetch("OMOTEURA_RESULTS", Omoteura::ResultsFile::DEFAULT_PATH))
  end
end

# Minitest.register_plugin does this from 5.22 on; this works from 5.21.
Minitest.extensions << "omoteura" unless Minitest.extensions.include?("omoteura")
