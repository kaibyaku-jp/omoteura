# frozen_string_literal: true

require_relative "../omoteura-core/lib/omoteura/core/version"

Gem::Specification.new do |spec|
  spec.name          = "omoteura-rspec"
  spec.version       = Omoteura::VERSION
  spec.authors       = ["KAIBYAKU K.K."]
  spec.summary       = "RSpec spec analysis and result formatter for Omoteura"
  spec.homepage      = "https://github.com/kaibyaku-jp/omoteura"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["changelog_uri"]         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"]

  spec.add_dependency "omoteura-core", Omoteura::VERSION
  spec.add_dependency "rspec-core", ">= 3.12", "< 4"
end
