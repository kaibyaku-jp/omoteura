# frozen_string_literal: true

require_relative "lib/omoteura/core/version"

Gem::Specification.new do |spec|
  spec.name = "omoteura-core"
  spec.version = Omoteura::VERSION
  spec.authors = ["KAIBYAKU K.K"]
  spec.summary = "Diagram file I/O, omoteura: link resolution and CLI for Omoteura"
  spec.homepage = "https://github.com/kaibyaku-jp/omoteura"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"]
end
