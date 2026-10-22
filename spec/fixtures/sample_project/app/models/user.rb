# frozen_string_literal: true

class User
  attr_accessor :name, :email

  def initialize(name: nil, email: nil)
    @name = name
    @email = email
  end

  def valid?
    !email.to_s.empty?
  end

  def display_name
    name || email.split("@").first
  end
end
