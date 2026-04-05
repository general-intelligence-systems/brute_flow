# frozen_string_literal: true

require "open3"

module Brute
  module Flow
    module Services
      # Searches the workspace for files relevant to the task.
      # Uses ripgrep to find matches. No LLM call.
      class MemoryRecallService
        MAX_FILES = 20
        MAX_SNIPPET = 200

        def call(variables, _headers)
          cwd = variables[:cwd] || variables["cwd"] || Dir.pwd
          task = variables[:user_message] || variables["user_message"] || ""

          # Extract keywords: words > 3 chars, skip common stop words
          keywords = extract_keywords(task)
          return { relevant_files: [] } if keywords.empty?

          files = {}
          keywords.first(5).each do |kw|
            search_keyword(kw, cwd).each do |path, snippet|
              files[path] ||= snippet
            end
            break if files.size >= MAX_FILES
          end

          { relevant_files: files.keys.first(MAX_FILES) }
        end

        private

        STOP_WORDS = %w[
          the and for that this with from are was were been have has
          had not but all can will just more some than them into also
          make like over such after first well back even give most
          file files code should would could please help want need use
        ].to_set.freeze

        def extract_keywords(text)
          text.scan(/\b[a-zA-Z_]\w{2,}\b/)
              .map(&:downcase)
              .reject { |w| STOP_WORDS.include?(w) }
              .tally
              .sort_by { |_, count| -count }
              .map(&:first)
        end

        def search_keyword(keyword, cwd)
          cmd = ["rg", "--line-number", "--max-count=3", "--max-columns=200",
                 "--ignore-case", "--no-heading", keyword, cwd]
          stdout, _, status = Open3.capture3(*cmd)
          return [] unless status.success?

          results = []
          stdout.lines.first(10).each do |line|
            if line =~ /\A(.+?):(\d+):(.*)/
              path = Regexp.last_match(1)
              snippet = Regexp.last_match(3).strip[0...MAX_SNIPPET]
              results << [path, snippet]
            end
          end
          results
        end
      end
    end
  end
end
