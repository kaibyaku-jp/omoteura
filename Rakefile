# frozen_string_literal: true

require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "omoteura-*/spec/**/*_spec.rb"
end

task default: %i[spec standard]
