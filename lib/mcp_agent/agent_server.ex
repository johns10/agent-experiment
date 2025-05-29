defmodule MCPAgent.AgentServer do
  @moduledoc """
  Clean API for agent server functionality.
  
  This module provides the public interface for creating and interacting with agent servers.
  It delegates all implementation to MCPAgent.AgentServer.Server (GenServer layer) and
  MCPAgent.AgentServer.Impl (business logic layer).
  
  ## Architecture
  
  - **API Layer** (this module): Clean public interface
  - **Server Layer**: Pure GenServer callbacks and message handling
  - **Implementation Layer**: Pure business logic without GenServer concerns
  
  ## Usage
  
      # Start an agent server with MCP client
      {:ok, pid} = MCPAgent.AgentServer.start_link([
        agent_impl: MyAgent.new("research-agent"),
        agent_config: %{domain: "AI research"},
        mcp_client: MCPAgent.KnowledgeClient
      ])
      
      # Send input to the agent
      MCPAgent.AgentServer.send_input(pid, "research quantum computing")
      
      # Get current state and discovered tools
      state = MCPAgent.AgentServer.get_state(pid)
      tools = MCPAgent.AgentServer.get_tools(pid)
      
      # Trigger action decision
      MCPAgent.AgentServer.trigger_action(pid)
  """

  @doc """
  Start an agent server with a specific agent implementation and MCP tools.
  
  ## Options
  
  - `:agent_impl` - Module or struct implementing the Agent protocol (required)
  - `:agent_config` - Configuration map passed to agent.init/2 (default: %{})
  - `:mcp_client` - Name/PID of the MCP client process (optional)
  - `:name` - Name to register this GenServer (optional)
  
  ## Examples
  
      # Start with a specific agent
      {:ok, pid} = MCPAgent.AgentServer.start_link([
        agent_impl: MyAgent.new("research-bot"),
        agent_config: %{domain: "AI research"},
        mcp_client: :mcp_client
      ])
      
      # Start with registration
      {:ok, pid} = MCPAgent.AgentServer.start_link([
        agent_impl: MyAgent.new("task-bot"),
        name: :task_agent
      ])
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {agent_impl, opts} = Keyword.pop!(opts, :agent_impl)
    {agent_config, opts} = Keyword.pop(opts, :agent_config, %{})
    {mcp_client, opts} = Keyword.pop(opts, :mcp_client)
    
    init_args = {agent_impl, agent_config, mcp_client}
    GenServer.start_link(MCPAgent.AgentServer.Server, init_args, opts)
  end

  @doc """
  Send input to the agent for processing.
  
  This is an asynchronous operation that will trigger the agent's
  process_input/4 function and potentially lead to autonomous actions.
  """
  @spec send_input(GenServer.server(), any()) :: :ok
  def send_input(server, input) do
    GenServer.cast(server, {:input, input})
  end

  @doc """
  Get the agent's current state and status information.
  
  Returns a map containing the agent's status, available tools count,
  and recent action history.
  """
  @spec get_state(GenServer.server()) :: map()
  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Get the list of available MCP tools.
  
  Returns the current list of tools available from the MCP client.
  """
  @spec get_tools(GenServer.server()) :: list()
  def get_tools(server) do
    GenServer.call(server, :get_tools)
  end

  @doc """
  Manually trigger the agent to decide and potentially execute an action.
  
  This bypasses the normal input-driven action flow and asks the agent
  to evaluate its current state and decide if any actions should be taken.
  """
  @spec trigger_action(GenServer.server()) :: :ok
  def trigger_action(server) do
    GenServer.cast(server, :trigger_action)
  end

  @doc """
  Get server statistics and performance metrics.
  
  Returns information about the server's operation including uptime,
  message counts, and performance data.
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(server) do
    GenServer.call(server, :get_stats)
  end
end 