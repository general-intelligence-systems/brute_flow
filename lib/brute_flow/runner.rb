# frozen_string_literal: true

require "async"
require "async/barrier"

module Brute
  module Flow
    # Async-native BPMN execution runner.
    #
    # Takes a BPMN::Definitions (built by Builder), starts the process,
    # and drives automated ServiceTasks to completion — running parallel
    # branches concurrently via Async::Barrier.
    #
    # WorkflowKit's engine is synchronous by design: ServiceTask#run is
    # called inline and ParallelGateway branches execute sequentially.
    # We monkey-patch ServiceTask#run to be a no-op and handle execution
    # ourselves, giving us true async parallelism.
    #
    class Runner
      attr_reader :execution, :context

      def initialize(definitions, cwd: Dir.pwd, variables: {})
        @definitions = definitions
        @cwd = cwd
        @initial_variables = variables.merge(cwd: cwd)
        @context = nil
        @execution = nil
      end

      # Execute the flow to completion. Blocks until done.
      # Returns the final variables hash.
      def run
        @context = BPMN::Context.new([], processes: @definitions.processes)
        @execution = @context.start(variables: @initial_variables)

        Async do
          run_loop
        end

        @execution.variables
      end

      # Serialize execution state for session persistence.
      def serialize
        @execution&.serialize
      end

      # Restore from serialized state.
      def restore(state)
        @context = BPMN::Context.new([], processes: @definitions.processes)
        @execution = @context.restore(state)
      end

      # Final output variables.
      def variables
        @execution&.variables || {}
      end

      private

      def run_loop
        loop do
          # Check expired timers (for loop timeouts)
          @execution.check_expired_timers if @execution.respond_to?(:check_expired_timers)

          # Find all waiting automated (ServiceTask) executions
          waiting = find_waiting_automated(@execution)
          break if waiting.empty?

          # Group by whether they share a parallel gateway parent
          # (i.e., sibling branches that should run concurrently)
          groups = group_by_parallel_parent(waiting)

          groups.each do |_parent_id, tasks|
            if tasks.size > 1
              run_parallel(tasks)
            else
              run_single(tasks.first)
            end
          end
        end
      end

      def run_parallel(tasks)
        barrier = Async::Barrier.new
        results = {}

        tasks.each do |exec|
          barrier.async do
            results[exec] = run_service(exec)
          end
        end

        barrier.wait
      ensure
        barrier&.stop

        # Signal each execution with its result
        results.each do |exec, result|
          signal_with_result(exec, result)
        end
      end

      def run_single(exec)
        result = run_service(exec)
        signal_with_result(exec, result)
      end

      def run_service(exec)
        step = exec.step
        return nil unless step.respond_to?(:task_type) && step.task_type

        klass = step.task_type.constantize
        vars = exec.parent&.variables || {}
        hdrs = step.respond_to?(:headers) ? (step.headers || {}) : {}

        klass.new.call(vars, hdrs)
      rescue => e
        { error: true, message: e.message, class: e.class.name }
      end

      def signal_with_result(exec, result)
        return unless exec.waiting?
        exec.signal(result)
      rescue => e
        warn "[brute/flow] Signal failed for #{exec.step&.id}: #{e.message}"
      end

      # Recursively find all waiting executions whose step is an automated task.
      def find_waiting_automated(execution)
        found = []
        return found unless execution.respond_to?(:children)

        execution.children.each do |child|
          if child.waiting? && child.step.respond_to?(:is_automated?) && child.step.is_automated?
            found << child
          end
          # Recurse into sub-process children
          found.concat(find_waiting_automated(child))
        end

        found
      end

      # Group waiting tasks by their parent execution id.
      # Tasks sharing the same parent after a ParallelGateway fork
      # are siblings that should run concurrently.
      def group_by_parallel_parent(tasks)
        tasks.group_by { |t| t.parent&.object_id || :root }
      end
    end

    # ----------------------------------------------------------------
    # Monkey-patch: make ServiceTask#run a no-op.
    #
    # WorkflowKit's ServiceTask#run calls task_type.constantize.new.call()
    # synchronously. We override it so the engine only puts the task into
    # `waiting` state. Our Runner then picks up waiting tasks and runs
    # them with async parallelism.
    # ----------------------------------------------------------------
    module ServiceTaskAsyncPatch
      def run(execution)
        # No-op: Runner handles execution externally.
        # The task is already in `waiting` state from execute().
        nil
      end
    end
  end
end

# Apply the monkey-patch
BPMN::ServiceTask.prepend(Brute::Flow::ServiceTaskAsyncPatch)
