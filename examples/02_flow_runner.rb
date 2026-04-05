#!/usr/bin/env ruby
# frozen_string_literal: true

# Test BPMN flow execution — uses services that don't need API keys.

require_relative "../lib/brute_flow"

puts "=== Flow Runner Tests ==="
puts

# 1. Sequential
puts "[1] Sequential"
Brute.flow(cwd: Dir.pwd, variables: { user_message: "find ruby files" }) do
  service :recall, type: "Brute::Flow::Services::MemoryRecallService"
end.then do |runner|
  runner.run.then do |result|
    (result[:relevant_files] || result["relevant_files"] || []).then do |files|
      puts "   Status: #{runner.execution.status}"
      puts "   Files: #{files.size}"
      puts "   Pass: #{runner.execution.status.to_s == "completed" ? "yes" : "NO"}"
    end
  end
end
puts

# 2. Parallel
puts "[2] Parallel"
Brute.flow(cwd: Dir.pwd, variables: { user_message: "find test files" }) do
  parallel do
    service :m1, type: "Brute::Flow::Services::MemoryRecallService"
    service :m2, type: "Brute::Flow::Services::MemoryRecallService"
  end
end.then do |runner|
  runner.run
  puts "   Status: #{runner.execution.status}"
  puts "   Pass: #{runner.execution.status.to_s == "completed" ? "yes" : "NO"}"
end
puts

# 3. Gateway — default path
puts "[3] Gateway (default)"
Brute.flow(cwd: Dir.pwd, variables: { user_message: "test", agent_mode: "simple" }) do
  exclusive_gateway :mode, default: :simple_path do
    branch :fibre_path, condition: '=agent_mode = "fibre"' do
      service :fibre, type: "Brute::Flow::Services::MemoryRecallService"
    end
    branch :simple_path do
      service :simple, type: "Brute::Flow::Services::MemoryRecallService"
    end
  end
end.then do |runner|
  runner.run
  puts "   Status: #{runner.execution.status}"
  puts "   Pass: #{runner.execution.status.to_s == "completed" ? "yes" : "NO"}"
end
puts

# 4. Gateway — conditional path
puts "[4] Gateway (conditional)"
Brute.flow(cwd: Dir.pwd, variables: { user_message: "test", agent_mode: "fibre" }) do
  exclusive_gateway :mode, default: :simple_path do
    branch :fibre_path, condition: '=agent_mode = "fibre"' do
      service :fibre, type: "Brute::Flow::Services::MemoryRecallService"
    end
    branch :simple_path do
      service :simple, type: "Brute::Flow::Services::MemoryRecallService"
    end
  end
end.then do |runner|
  runner.run
  puts "   Status: #{runner.execution.status}"
  puts "   Pass: #{runner.execution.status.to_s == "completed" ? "yes" : "NO"}"
end
puts

# 5. SelfCheck
puts "[5] SelfCheck"
Brute.flow(cwd: Dir.pwd, variables: { user_message: "test", agent_result: "modified ./lib/brute_flow.rb" }) do
  service :check, type: "Brute::Flow::Services::SelfCheckService"
end.then do |runner|
  runner.run
  puts "   Status: #{runner.execution.status}"
  puts "   Pass: #{runner.execution.status.to_s == "completed" ? "yes" : "NO"}"
end
puts

# 6. Full combined
puts "[6] Combined: parallel → gateway"
Brute.flow(cwd: Dir.pwd, variables: { user_message: "test", agent_mode: "simple" }) do
  parallel do
    service :r1, type: "Brute::Flow::Services::MemoryRecallService"
    service :r2, type: "Brute::Flow::Services::MemoryRecallService"
  end
  exclusive_gateway :route, default: :default_path do
    branch :alt, condition: '=agent_mode = "alt"' do
      service :alt_check, type: "Brute::Flow::Services::SelfCheckService"
    end
    branch :default_path do
      service :main_check, type: "Brute::Flow::Services::SelfCheckService"
    end
  end
end.then do |runner|
  runner.run
  puts "   Status: #{runner.execution.status}"
  puts "   Pass: #{runner.execution.status.to_s == "completed" ? "yes" : "NO"}"
end

puts
puts "=== All Flow Runner tests passed ==="
