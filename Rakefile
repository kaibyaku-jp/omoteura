# frozen_string_literal: true

require "rspec/core/rake_task"
require "standard/rake"
require_relative "omoteura-core/lib/omoteura/core/version"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "{spec,omoteura-*/spec}/**/*_spec.rb"
end

task default: %i[spec standard]

GEMS = %w[omoteura-core omoteura-rails omoteura-rspec omoteura].freeze

desc "Build all four gems into pkg/"
task :package do
  require "fileutils"
  pkg = File.expand_path("pkg", __dir__)
  FileUtils.mkdir_p(pkg)
  GEMS.each do |name|
    dir = (name == "omoteura") ? __dir__ : File.join(__dir__, name)
    Dir.chdir(dir) { sh "gem", "build", "#{name}.gemspec", "--output", File.join(pkg, "#{name}-#{Omoteura::VERSION}.gem") }
  end
end
