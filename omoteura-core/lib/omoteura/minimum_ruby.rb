# frozen_string_literal: true

# Loaded by the executable before anything else, so it must stay in syntax
# that old Rubies can parse and must not depend on the rest of the gem.
module Omoteura
  MINIMUM_RUBY = "3.4"

  # The message to stop with when version is older than MINIMUM_RUBY, or nil.
  def self.ruby_too_old_message(version = RUBY_VERSION, ruby = RbConfig.ruby)
    return nil unless Gem::Version.new(version) < Gem::Version.new(MINIMUM_RUBY)

    "omoteura needs Ruby #{MINIMUM_RUBY} or later, but this is Ruby #{version} (#{ruby})."
  end
end
