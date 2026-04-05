# frozen_string_literal: true

module Brute
  module Flow
    module Services
      # Runs a full Brute::Orchestrator for the user's message.
      # This is the core service — it invokes the coding agent with
      # all tools, middleware, retry, compaction, etc.
      class AgentService
        def call(variables, headers)
          cwd = variables[:cwd] || variables["cwd"] || Dir.pwd
          message = variables[:user_message] || variables["user_message"]
          tools_filter = variables[:suggested_tools] || variables["suggested_tools"]
          context_files = variables[:relevant_files] || variables["relevant_files"]

          # Build enriched prompt with context from upstream services
          prompt = message.dup
          if context_files.is_a?(Array) && !context_files.empty?
            prompt = "Relevant files:\n#{context_files.map { |f| "- #{f}" }.join("\n")}\n\n#{prompt}"
          end

          orch = Brute.agent(cwd: cwd)
          response = orch.run(prompt)

          { agent_result: response&.content }
        end
      end
    end
  end
end
