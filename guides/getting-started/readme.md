# Getting Started

This guide walks you through setting up brute_flow for BPMN-based multi-agent orchestration.

## Install

```ruby
gem "brute_flow"
```

## Overview

brute_flow extends the [brute](https://github.com/general-intelligence-systems/brute) gem with a declarative BPMN workflow engine for multi-agent orchestration. It supports parallel branches, conditional routing, loops with timeouts, and pluggable service tasks.

## Dependencies

- [brute](https://github.com/general-intelligence-systems/brute) -- core agent library
- [bpmn](https://rubygems.org/gems/bpmn) -- BPMN process engine

## Services

brute_flow ships with several built-in service tasks:

- `AgentService` -- runs a Brute agent as a BPMN service task
- `MemoryRecallService` -- recalls context from previous agent interactions
- `RouterService` -- routes flow based on agent output
- `SelfCheckService` -- validates agent output against criteria
- `ToolSuggestService` -- suggests tools for the agent to use
