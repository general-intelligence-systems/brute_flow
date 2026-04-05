# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "brute_flow"
  spec.version       = "0.1.1"
  spec.authors       = ["Brute Contributors"]
  spec.summary       = "BPMN-based multi-agent flow engine for Brute"
  spec.description   = "Extends the brute gem with a declarative BPMN workflow engine " \
                        "for multi-agent orchestration — parallel branches, conditional " \
                        "routing, loops with timeouts, and pluggable service tasks."
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files         = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "brute", "~> 0.1"
  spec.add_dependency "bpmn", "~> 0.4"
end
