# frozen_string_literal: true

require "open3"

module Brute
  module Flow
    module Services
      # Deterministic post-execution validation. No LLM call.
      # Checks that output files exist and have valid syntax.
      # Returns { self_check_passed: bool, self_check_errors: [...] }
      class SelfCheckService
        SYNTAX_CHECKERS = {
          ".rb"   => ->(path) { check_cmd("ruby -c #{path.shellescape}") },
          ".json" => ->(path) { check_json(path) },
          ".yml"  => ->(path) { check_yaml(path) },
          ".yaml" => ->(path) { check_yaml(path) },
        }.freeze

        def call(variables, _headers)
          cwd = variables[:cwd] || variables["cwd"] || Dir.pwd
          result = variables[:agent_result] || variables["agent_result"] || ""
          errors = []

          # Increment loop counter
          counter_key = variables.keys.find { |k| k.to_s.start_with?("_loop_") && k.to_s.end_with?("_count") }
          if counter_key
            variables[counter_key] = (variables[counter_key] || 0).to_i + 1
          end

          # Extract file paths mentioned in agent output
          paths = result.to_s.scan(%r{(?:^|\s)((?:/|\.{1,2}/)\S+\.\w+)}).flatten.uniq
          paths.each do |rel_path|
            full = File.expand_path(rel_path, cwd)
            unless File.exist?(full)
              errors << "File not found: #{rel_path}"
              next
            end

            ext = File.extname(full).downcase
            checker = SYNTAX_CHECKERS[ext]
            next unless checker

            err = checker.call(full)
            errors << "#{rel_path}: #{err}" if err
          end

          { self_check_passed: errors.empty?, self_check_errors: errors }
        end

        private

        def self.check_cmd(cmd)
          _out, err, status = Open3.capture3(cmd)
          status.success? ? nil : err.lines.first&.strip
        end

        def self.check_json(path)
          JSON.parse(File.read(path))
          nil
        rescue JSON::ParserError => e
          e.message.lines.first&.strip
        end

        def self.check_yaml(path)
          YAML.safe_load(File.read(path))
          nil
        rescue Psych::SyntaxError => e
          e.message.lines.first&.strip
        end
      end
    end
  end
end
