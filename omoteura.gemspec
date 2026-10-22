# frozen_string_literal: true

require_relative "omoteura-core/lib/omoteura/core/version"

Gem::Specification.new do |spec|
  spec.name = "omoteura"
  spec.version = Omoteura::VERSION
  spec.authors = ["KAIBYAKU K.K"]
  spec.summary = "Overlay hand-drawn Excalidraw diagrams on Rails and RSpec code"
  spec.description = "Meta gem that installs omoteura-core, omoteura-rails and omoteura-rspec."
  spec.homepage = "https://github.com/kaibyaku-jp/omoteura"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob(["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"], base: __dir__)

  spec.add_dependency "omoteura-core", Omoteura::VERSION
  spec.add_dependency "omoteura-rails", Omoteura::VERSION
  spec.add_dependency "omoteura-rspec", Omoteura::VERSION
end
