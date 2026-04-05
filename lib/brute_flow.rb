# frozen_string_literal: true

require "brute"
require "bpmn"
require "active_support/core_ext/time/zones"

# Ensure a time zone is set for WorkflowKit.
Time.zone ||= "UTC"

module Brute
  module Flow
    module Services; end
  end
end

require_relative "brute_flow/builder"
require_relative "brute_flow/runner"
require_relative "brute_flow/services/agent_service"
require_relative "brute_flow/services/router_service"
require_relative "brute_flow/services/self_check_service"
require_relative "brute_flow/services/tool_suggest_service"
require_relative "brute_flow/services/memory_recall_service"

module Brute
  # Create a BPMN-driven multi-agent flow.
  #
  #   runner = Brute.flow(cwd: "/project", variables: { user_message: msg }) do
  #     service :router, type: "Brute::Flow::Services::RouterService"
  #     service :agent,  type: "Brute::Flow::Services::AgentService"
  #   end
  #   result = runner.run
  #
  def self.flow(cwd: Dir.pwd, variables: {}, &block)
    definitions = Flow::Builder.build("brute_flow", &block)
    Flow::Runner.new(definitions, cwd: cwd, variables: variables)
  end
end
