# frozen_string_literal: true

require "securerandom"

module Brute
  module Flow
    # Builds BPMN::Definitions directly from a Ruby DSL — no XML involved.
    #
    # Usage:
    #   defs = Builder.build("my_flow") do
    #     service :router, type: "Brute::Flow::Services::RouterService"
    #     exclusive_gateway :mode, default: :simple_path do
    #       branch :fibre_path, condition: '=agent_mode = "fibre"' do
    #         parallel do
    #           service :tools,  type: "Brute::Flow::Services::ToolSuggestService"
    #           service :memory, type: "Brute::Flow::Services::MemoryRecallService"
    #         end
    #         service :agent, type: "Brute::Flow::Services::AgentService"
    #       end
    #       branch :simple_path do
    #         service :agent, type: "Brute::Flow::Services::AgentService"
    #       end
    #     end
    #     loop_while '=self_check_passed = false', max: 3, timeout: "PT5M" do
    #       service :check, type: "Brute::Flow::Services::SelfCheckService"
    #     end
    #   end
    #
    class Builder
      def self.build(process_id = "brute_flow", &block)
        new(process_id).tap { |b| b.instance_eval(&block) }.finalize
      end

      def initialize(process_id)
        @process_id = process_id
        @counter = 0
        # Collect raw hashes by BPMN type
        @start_events = []
        @end_events = []
        @service_tasks = []
        @exclusive_gateways = []
        @parallel_gateways = []
        @boundary_events = []
        @sub_processes = []
        @sequence_flows = []
        # Ordered list of element ids representing the top-level sequence
        @sequence = []
      end

      # -- DSL methods --

      def service(id, type:, headers: {})
        task_id = uid(id)
        header_arr = headers.map { |k, v| { key: k.to_s, value: v.to_s } }
        ext = {}
        ext[:task_definition] = { type: type }
        ext[:task_headers] = { header: header_arr } unless header_arr.empty?

        @service_tasks << {
          id: task_id,
          name: id.to_s,
          extension_elements: ext,
        }
        @sequence << task_id
        task_id
      end

      def exclusive_gateway(id, default: nil, &block)
        split_id = uid(:"#{id}_split")
        join_id = uid(:"#{id}_join")
        default_branch_id = default

        ctx = GatewayContext.new(self)
        ctx.instance_eval(&block)
        branches = ctx.branches

        # Add split gateway
        default_flow_id = nil
        @exclusive_gateways << { id: split_id, name: "#{id}_split" }
        @sequence << split_id

        # Each branch: split → [branch elements] → join
        branches.each do |br|
          flow_id = uid(:"flow_#{br[:id]}")
          flow = { id: flow_id, source_ref: split_id, target_ref: br[:elements].first }
          flow[:condition_expression] = br[:condition] if br[:condition]
          @sequence_flows << flow

          if br[:id].to_s == default_branch_id.to_s
            default_flow_id = flow_id
          end

          # Chain branch elements internally
          br[:elements].each_cons(2) do |from, to|
            @sequence_flows << { id: uid(:flow), source_ref: from, target_ref: to }
          end

          # Last branch element → join
          @sequence_flows << { id: uid(:flow), source_ref: br[:elements].last, target_ref: join_id }
        end

        # Set default on split gateway
        @exclusive_gateways.last[:default] = default_flow_id if default_flow_id

        # Add join gateway
        @exclusive_gateways << { id: join_id, name: "#{id}_join" }
        @sequence << join_id
      end

      def parallel(&block)
        fork_id = uid(:parallel_fork)
        join_id = uid(:parallel_join)

        ctx = ParallelContext.new(self)
        ctx.instance_eval(&block)
        branches = ctx.branches

        @parallel_gateways << { id: fork_id, name: "parallel_fork" }
        @sequence << fork_id

        branches.each do |br|
          # fork → branch elements → join
          @sequence_flows << { id: uid(:flow), source_ref: fork_id, target_ref: br.first }
          br.each_cons(2) do |from, to|
            @sequence_flows << { id: uid(:flow), source_ref: from, target_ref: to }
          end
          @sequence_flows << { id: uid(:flow), source_ref: br.last, target_ref: join_id }
        end

        @parallel_gateways << { id: join_id, name: "parallel_join" }
        @sequence << join_id
      end

      def loop_while(condition, max: 3, timeout: nil, &block)
        # Build the loop body into a subprocess
        sub_id = uid(:loop_sub)
        inner = Builder.new(sub_id)
        inner.instance_eval(&block)

        # The loop gate: after the subprocess, check condition to loop back
        gate_id = uid(:loop_gate)
        back_flow_id = uid(:loop_back)
        exit_flow_id = uid(:loop_exit)

        # Counter variable for max iterations
        counter_var = "_loop_#{@counter}_count"
        # FEEL condition: original condition AND counter < max
        guarded = "=#{strip_feel(condition)} and #{counter_var} < #{max}"

        # Add subprocess hash (it's a Process-like thing)
        sub_process_hash = inner.to_sub_process_hash(sub_id)
        @sub_processes << sub_process_hash
        @sequence << sub_id

        # Add gate after subprocess
        @exclusive_gateways << { id: gate_id, name: "loop_gate", default: exit_flow_id }
        @sequence << gate_id

        # Back-edge: gate → subprocess (with condition)
        @sequence_flows << { id: back_flow_id, source_ref: gate_id, target_ref: sub_id, condition_expression: guarded }
        # Exit edge: gate → (whatever comes next, wired in finalize)
        # We store exit_flow_id so the next element connects from here
        @loop_exit_flow = exit_flow_id

        # Timeout boundary event on the subprocess
        if timeout
          boundary_id = uid(:loop_timeout)
          @boundary_events << {
            id: boundary_id,
            name: "loop_timeout",
            attached_to_ref: sub_id,
            cancel_activity: "true",
            timer_event_definition: { time_duration: timeout },
          }
        end
      end

      # -- Internal: used by GatewayContext / ParallelContext --

      def _build_branch(&block)
        saved_sequence = @sequence
        @sequence = []
        instance_eval(&block)
        branch_elements = @sequence
        @sequence = saved_sequence
        branch_elements
      end

      def uid(prefix = :el)
        @counter += 1
        "#{prefix}_#{@counter}"
      end

      # -- Finalize: assemble into BPMN::Definitions --

      def finalize
        start_id = uid(:start)
        end_id = uid(:end)

        @start_events << { id: start_id, name: "Start" }
        @end_events << { id: end_id, name: "End" }

        # Build the main sequence: start → elements → end
        all = [start_id] + @sequence + [end_id]
        all.each_cons(2) do |from, to|
          # Skip if there's already a flow from `from` (gateways wire their own)
          next if @sequence_flows.any? { |f| f[:source_ref] == from }
          # For loop exit flows
          if @loop_exit_flow && @sequence_flows.none? { |f| f[:id] == @loop_exit_flow }
            @sequence_flows << { id: @loop_exit_flow, source_ref: from, target_ref: to }
            @loop_exit_flow = nil
            next
          end
          @sequence_flows << { id: uid(:flow), source_ref: from, target_ref: to }
        end

        # Build incoming/outgoing arrays for each element
        incoming = Hash.new { |h, k| h[k] = [] }
        outgoing = Hash.new { |h, k| h[k] = [] }
        @sequence_flows.each do |f|
          outgoing[f[:source_ref]] << f[:id]
          incoming[f[:target_ref]] << f[:id]
        end

        # Attach incoming/outgoing to all elements
        all_elements = @start_events + @end_events + @service_tasks +
                       @exclusive_gateways + @parallel_gateways + @sub_processes
        all_elements.each do |el|
          el[:incoming] = incoming[el[:id]] unless incoming[el[:id]].empty?
          el[:outgoing] = outgoing[el[:id]] unless outgoing[el[:id]].empty?
        end

        process_hash = {
          id: @process_id,
          name: @process_id,
          is_executable: "true",
          start_event: @start_events,
          end_event: @end_events,
          service_task: @service_tasks,
          exclusive_gateway: @exclusive_gateways,
          parallel_gateway: @parallel_gateways,
          sub_process: @sub_processes,
          boundary_event: @boundary_events,
          sequence_flow: @sequence_flows,
        }

        defs = BPMN::Definitions.new(process: [process_hash])
        defs.processes.each { |p| p.wire_references(defs) }
        defs
      end

      # Build a sub-process hash from the current builder state (for loop bodies).
      def to_sub_process_hash(id)
        start_id = uid(:sub_start)
        end_id = uid(:sub_end)

        sub_start = [{ id: start_id, name: "SubStart" }]
        sub_end = [{ id: end_id, name: "SubEnd" }]

        all = [start_id] + @sequence + [end_id]
        all.each_cons(2) do |from, to|
          next if @sequence_flows.any? { |f| f[:source_ref] == from }
          @sequence_flows << { id: uid(:flow), source_ref: from, target_ref: to }
        end

        incoming = Hash.new { |h, k| h[k] = [] }
        outgoing = Hash.new { |h, k| h[k] = [] }
        @sequence_flows.each do |f|
          outgoing[f[:source_ref]] << f[:id]
          incoming[f[:target_ref]] << f[:id]
        end

        all_els = sub_start + sub_end + @service_tasks + @exclusive_gateways +
                  @parallel_gateways + @sub_processes
        all_els.each do |el|
          el[:incoming] = incoming[el[:id]] unless incoming[el[:id]].empty?
          el[:outgoing] = outgoing[el[:id]] unless outgoing[el[:id]].empty?
        end

        {
          id: id,
          name: id,
          start_event: sub_start,
          end_event: sub_end,
          service_task: @service_tasks,
          exclusive_gateway: @exclusive_gateways,
          parallel_gateway: @parallel_gateways,
          sequence_flow: @sequence_flows,
        }
      end

      private

      def strip_feel(expr)
        expr.to_s.delete_prefix("=")
      end

      # -- Context objects for gateway/parallel DSL blocks --

      class GatewayContext
        attr_reader :branches

        def initialize(builder)
          @builder = builder
          @branches = []
        end

        def branch(id, condition: nil, &block)
          elements = @builder._build_branch(&block)
          @branches << { id: id, condition: condition, elements: elements }
        end
      end

      class ParallelContext
        attr_reader :branches

        def initialize(builder)
          @builder = builder
          @branches = []
        end

        def service(id, type:, headers: {})
          # Single-element branch
          task_id = @builder.service(id, type: type, headers: headers)
          # Pop it from the main sequence (we manage our own)
          @builder.instance_variable_get(:@sequence).pop
          @branches << [task_id]
        end

        def branch(&block)
          elements = @builder._build_branch(&block)
          @branches << elements
        end
      end
    end
  end
end
