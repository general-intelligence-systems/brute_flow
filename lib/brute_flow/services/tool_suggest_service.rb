# frozen_string_literal: true

module Brute
  module Flow
    module Services
      # Pre-filters the available tool set to the most relevant subset
      # for the given task. Single LLM call, no tools.
      class ToolSuggestService
        TOOL_NAMES = %w[read write patch remove fs_search undo shell fetch todo_write todo_read delegate].freeze

        PROMPT = <<~PROMPT
          Given this software engineering task, which of these tools are most likely needed?

          Available tools: %<tools>s

          Task: %<task>s

          Return ONLY a JSON array of tool names, e.g. ["read", "shell", "patch"]
        PROMPT

        def call(variables, _headers)
          task = variables[:user_message] || variables["user_message"]
          prompt = format(PROMPT, tools: TOOL_NAMES.join(", "), task: task)

          begin
            response = Brute.provider.complete(prompt)
            parsed = JSON.parse(response.content)
            { suggested_tools: Array(parsed) & TOOL_NAMES }
          rescue => e
            warn "[brute/flow/tool_suggest] Failed (#{e.message}), returning all tools"
            { suggested_tools: TOOL_NAMES }
          end
        end
      end
    end
  end
end
