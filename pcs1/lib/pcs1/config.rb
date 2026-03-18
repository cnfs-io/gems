# frozen_string_literal: true

module Pcs1
  class Config
    attr_accessor :host_defaults

    def initialize
      @host_defaults = {}
    end
  end
end
