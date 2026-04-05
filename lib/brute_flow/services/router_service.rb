# frozen_string_literal: true

module Brute
  module Flow
    module Services
      # Classifies the incoming task and decides the execution mode.
      # Single LLM call, no tools. Returns { agent_mode: "simple"|"fibre" }.
      class RouterService
        PROMPT = <<~PROMPT
          Classify this software engineering task into one of two modes:

          - "simple": Straightforward tasks that one agent can handle linearly.
            Examples: fix a bug, add a function, rename a variable, run tests.

          - "fibre": Complex tasks requiring parallel research, multi-file changes,
            or analysis from multiple angles before acting.
            Examples: large refactors, new feature across many files, architecture review.

          Return ONLY a JSON object: {"agent_mode": "simple"} or {"agent_mode": "fibre"}

          Task: %<task>s
        PROMPT

        def call(variables, _headers)
          task = variables[:user_message] || variables["user_message"]
          prompt = format(PROMPT, task: task)

          begin
            response = Brute.provider.complete(prompt)
            parsed = JSON.parse(response.content)
            { agent_mode: parsed["agent_mode"] || "simple" }
          rescue => e
            warn "[brute/flow/router] Classification failed (#{e.message}), defaulting to simple"
            { agent_mode: "simple" }
          end
        end
      end
    end
  end
end
