#!/usr/bin/env ruby
# frozen_string_literal: true

# Test the BPMN flow builder DSL — no API key needed.

require_relative "../lib/brute_flow"

puts "=== Flow Builder Tests ==="
puts

# 1. Sequential
Brute::Flow::Builder.build("seq") do
  service :s1, type: "Brute::Flow::Services::MemoryRecallService"
  service :s2, type: "Brute::Flow::Services::MemoryRecallService"
  service :s3, type: "Brute::Flow::Services::MemoryRecallService"
end.processes.first.then do |p|
  puts "1. Sequential: #{p.service_tasks.size} tasks, #{p.sequence_flows.size} flows"
  puts "   Correct: #{p.service_tasks.size == 3 ? "yes" : "NO"}"
end

# 2. Parallel
Brute::Flow::Builder.build("par") do
  parallel do
    service :a, type: "Brute::Flow::Services::MemoryRecallService"
    service :b, type: "Brute::Flow::Services::MemoryRecallService"
  end
end.processes.first.then do |p|
  puts "2. Parallel: #{p.parallel_gateways.size} gateways, #{p.service_tasks.size} tasks"
  puts "   Correct: #{p.parallel_gateways.size == 2 && p.service_tasks.size == 2 ? "yes" : "NO"}"
end

# 3. Exclusive gateway
Brute::Flow::Builder.build("gw") do
  exclusive_gateway :mode, default: :path_b do
    branch :path_a, condition: '=mode = "a"' do
      service :ta, type: "Brute::Flow::Services::MemoryRecallService"
    end
    branch :path_b do
      service :tb, type: "Brute::Flow::Services::MemoryRecallService"
    end
  end
end.processes.first.then do |p|
  puts "3. Gateway: #{p.exclusive_gateways.size} gateways, #{p.service_tasks.size} tasks"
  puts "   Correct: #{p.exclusive_gateways.size == 2 && p.service_tasks.size == 2 ? "yes" : "NO"}"
end

# 4. Combined
Brute::Flow::Builder.build("combo") do
  service :pre, type: "Brute::Flow::Services::MemoryRecallService"
  parallel do
    service :pa, type: "Brute::Flow::Services::MemoryRecallService"
    service :pb, type: "Brute::Flow::Services::MemoryRecallService"
  end
  exclusive_gateway :d, default: :fb do
    branch :sp, condition: '=flag = true' do
      service :special, type: "Brute::Flow::Services::MemoryRecallService"
    end
    branch :fb do
      service :fallback, type: "Brute::Flow::Services::MemoryRecallService"
    end
  end
  service :post, type: "Brute::Flow::Services::MemoryRecallService"
end.processes.first.then do |p|
  puts "4. Combined: #{p.service_tasks.size} tasks, #{p.parallel_gateways.size} par, #{p.exclusive_gateways.size} ex"
  puts "   Start: #{p.start_events.size == 1 ? "yes" : "NO"}"
  puts "   End: #{p.end_events.size == 1 ? "yes" : "NO"}"
end

puts
puts "=== All Flow Builder tests passed ==="
