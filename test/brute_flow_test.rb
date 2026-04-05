# frozen_string_literal: true

require "test_helper"

class BruteFlowTest < Minitest::Test
  def test_version
    refute_nil BruteFlow::VERSION
  end
end
