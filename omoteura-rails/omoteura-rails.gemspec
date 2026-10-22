# frozen_string_literal: true

require_relative "../omoteura-core/lib/omoteura/core/version"

Gem::Specification.new do |spec|
  spec.name          = "omoteura-rails"
  spec.version       = Omoteura::VERSION
  spec.authors       = ["KAIBYAKU K.K."]
  spec.summary       = "Rails model, controller and service analysis for Omoteura"
  spec.homepage      = "https://github.com/kaibyaku-jp/omoteura"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["changelog_uri"]         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"]

  spec.add_dependency "omoteura-core", Omoteura::VERSION
  spec.add_dependency "railties", ">= 7.0"
end
