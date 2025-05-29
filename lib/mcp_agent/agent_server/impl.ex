defmodule MCPAgent.AgentServer.Impl do
  @moduledoc """
  Pure implementation of agent server functionality.
  
  This module contains all the business logic for managing agents,
  MCP tool integration, and state management without any GenServer concerns.
  It can be tested directly and used with different execution strategies.
  """
  
  require Logger
  alias MCPAgent.Agent

  @type server_state :: %{
    agent_impl: any(),
    agent_state: any(),
    agent_config: map(),
    mcp_client: any(),
    tools: list(),
    action_history: list(),
    stats: map(),
    started_at: DateTime.t(),
    last_input_at: DateTime.t() | nil,
    last_action_at: DateTime.t() | nil
  }

  @doc """
  Initialize a new agent server state.
  """
  @spec init_state(any(), map(), any()) :: {:ok, server_state()} | {:error, any()}
  def init_state(agent_impl, agent_config, mcp_client) do
    try do
      # Initialize the agent using the protocol
      initial_agent_state = Agent.init(agent_impl, agent_config)
      
      # Fetch available tools from MCP client
      tools = fetch_mcp_tools(mcp_client)
      
      state = %{
        # Agent-specific state
        agent_impl: agent_impl,
        agent_state: initial_agent_state,
        agent_config: agent_config,
        
        # MCP integration
        mcp_client: mcp_client,
        tools: tools,
        
        # Server state
        action_history: [],
        stats: init_stats(),
        
        # Server metadata
        started_at: DateTime.utc_now(),
        last_input_at: nil,
        last_action_at: nil
      }
      
      Logger.info("AgentServer.Impl initialized successfully with #{length(tools)} tools")
      {:ok, state}
    rescue
      error ->
        Logger.error("Failed to initialize agent: #{inspect(error)}")
        {:error, {:initialization_failed, error}}
    end
  end

  @doc """
  Process input through the agent.
  """
  @spec process_input(server_state(), any()) :: {:ok, any(), server_state()} | {:error, any(), server_state()}
  def process_input(state, input) do
    Logger.debug("Processing input: #{inspect(input)}")
    
    updated_stats = update_stats(state.stats, :input_received)
    
    case process_agent_input(state.agent_impl, input, state.agent_state, state.tools) do
      {:ok, response, new_agent_state} ->
        Logger.debug("Agent response: #{inspect(response)}")
        
        new_state = %{
          state | 
          agent_state: new_agent_state,
          last_input_at: DateTime.utc_now(),
          stats: update_stats(updated_stats, :input_processed)
        }
        
        {:ok, response, new_state}
      
      {:error, reason} ->
        Logger.warning("Agent input processing failed: #{inspect(reason)}")
        
        new_state = %{
          state | 
          stats: update_stats(updated_stats, :input_error)
        }
        
        {:error, reason, new_state}
    end
  end

  @doc """
  Check if agent wants to take autonomous action and execute it.
  """
  @spec maybe_autonomous_action(server_state()) :: server_state()
  def maybe_autonomous_action(state) do
    case Agent.decide_action(state.agent_impl, state.agent_state, state.tools) do
      {:action, action} ->
        Logger.debug("Agent decided to take autonomous action: #{inspect(action)}")
        updated_stats = update_stats(state.stats, :autonomous_actions)
        new_state = %{state | stats: updated_stats}
        execute_action(new_state, action)
      
      :no_action ->
        Logger.debug("Agent decided no action needed")
        state
      
      other ->
        Logger.warning("Unexpected decision result: #{inspect(other)}")
        state
    end
  rescue
    error ->
      Logger.error("Error in autonomous action decision: #{inspect(error)}")
      state
  end

  @doc """
  Manually trigger action decision and execution.
  """
  @spec trigger_action(server_state()) :: server_state()
  def trigger_action(state) do
    updated_stats = update_stats(state.stats, :action_triggered)
    new_state = %{state | stats: updated_stats}
    
    case Agent.decide_action(new_state.agent_impl, new_state.agent_state, new_state.tools) do
      {:action, action} ->
        Logger.debug("Executing decided action: #{inspect(action)}")
        execute_action(new_state, action)
      
      :no_action ->
        Logger.debug("No action decided during manual trigger")
        new_state
      
      other ->
        Logger.warning("Unexpected action decision: #{inspect(other)}")
        new_state
    end
  rescue
    error ->
      Logger.error("Error in action cycle: #{inspect(error)}")
      state
  end

  @doc """
  Get formatted state response for external callers.
  """
  @spec get_state_response(server_state()) :: map()
  def get_state_response(state) do
    agent_status = Agent.status(state.agent_impl, state.agent_state)
    
    %{
      agent_status: agent_status,
      available_tools: length(state.tools),
      recent_actions: Enum.take(state.action_history, 5),
      server_info: %{
        started_at: state.started_at,
        last_input_at: state.last_input_at,
        last_action_at: state.last_action_at,
        mcp_client: state.mcp_client
      }
    }
  end

  @doc """
  Get tools list.
  """
  @spec get_tools(server_state()) :: list()
  def get_tools(state) do
    state.tools
  end

  @doc """
  Get statistics with uptime calculation.
  """
  @spec get_stats(server_state()) :: map()
  def get_stats(state) do
    Map.put(state.stats, :uptime_seconds, 
      DateTime.diff(DateTime.utc_now(), state.started_at))
  end

  @doc """
  Refresh tools from MCP client.
  """
  @spec refresh_tools(server_state()) :: server_state()
  def refresh_tools(state) do
    Logger.debug("Refreshing MCP tools")
    new_tools = fetch_mcp_tools(state.mcp_client)
    %{state | tools: new_tools}
  end

  @doc """
  Update tool call statistics.
  """
  @spec update_tool_stats(server_state(), :attempted | :success | :error) :: server_state()
  def update_tool_stats(state, stat_type) do
    case stat_type do
      :attempted -> %{state | stats: update_stats(state.stats, :tool_calls)}
      :success -> state  # Success already counted in attempts
      :error -> %{state | stats: update_stats(state.stats, :tool_errors)}
    end
  end

  # Private implementation functions

  @spec execute_action(server_state(), any()) :: server_state()
  defp execute_action(state, action) do
    Logger.info("Executing action: #{inspect(action)}")
    
    # Create a tool executor function for the agent
    tool_executor = create_tool_executor(state.mcp_client)
    
    # Execute the action using the agent's execute_action function
    case execute_agent_action(state.agent_impl, action, state.agent_state, tool_executor) do
      {:ok, result, new_agent_state} ->
        Logger.info("Action executed successfully: #{inspect(result)}")
        
        action_record = %{
          action: action,
          result: result,
          timestamp: DateTime.utc_now(),
          status: :completed,
          execution_time_ms: 0  # Could be measured if needed
        }
        
        %{
          state | 
          agent_state: new_agent_state,
          action_history: [action_record | Enum.take(state.action_history, 19)], # Keep last 20
          last_action_at: DateTime.utc_now(),
          stats: update_stats(state.stats, :action_executed)
        }
      
      {:error, reason} ->
        Logger.error("Action execution failed: #{inspect(reason)}")
        
        action_record = %{
          action: action,
          result: nil,
          error: reason,
          timestamp: DateTime.utc_now(),
          status: :failed
        }
        
        %{
          state | 
          action_history: [action_record | Enum.take(state.action_history, 19)],
          last_action_at: DateTime.utc_now(),
          stats: update_stats(state.stats, :action_error)
        }
    end
  end

  @spec create_tool_executor(any()) :: function()
  defp create_tool_executor(mcp_client) do
    fn tool_name, args ->
      execute_mcp_tool(mcp_client, tool_name, args)
    end
  end

  @spec fetch_mcp_tools(any()) :: list()
  defp fetch_mcp_tools(nil) do
    Logger.debug("No MCP client configured, using empty tool list")
    []
  end
  
  defp fetch_mcp_tools(mcp_client) when is_atom(mcp_client) or is_pid(mcp_client) do
    fetch_tools_via_hermes(mcp_client)
  end
  
  defp fetch_mcp_tools(mcp_client) do
    Logger.warning("Invalid MCP client type: #{inspect(mcp_client)}")
    []
  end
  
  @spec fetch_tools_via_hermes(atom() | pid()) :: list()
  defp fetch_tools_via_hermes(mcp_client) do
    case Hermes.Client.list_tools(mcp_client) do
      {:ok, %{tools: tools}} ->
        Logger.info("Discovered #{length(tools)} tools from MCP client #{inspect(mcp_client)}")
        tools
      
      {:ok, result} ->
        # Handle different response formats
        tools = Map.get(result, "tools", [])
        Logger.info("Discovered #{length(tools)} tools from MCP client #{inspect(mcp_client)}")
        tools
      
      {:error, reason} ->
        Logger.warning("Failed to list tools from MCP client #{inspect(mcp_client)}: #{inspect(reason)}")
        []
    end
  rescue
    error ->
      Logger.warning("Error calling Hermes.Client.list_tools for #{inspect(mcp_client)}: #{inspect(error)}")
      []
  end

  @spec execute_mcp_tool(any(), String.t(), map()) :: {:ok, any()} | {:error, any()}
  defp execute_mcp_tool(nil, tool_name, _args) do
    Logger.warning("Cannot execute tool '#{tool_name}': No MCP client configured")
    {:error, :no_mcp_client}
  end

  defp execute_mcp_tool(mcp_client, tool_name, args) when is_atom(mcp_client) or is_pid(mcp_client) do
    execute_tool_via_hermes(mcp_client, tool_name, args)
  end

  defp execute_mcp_tool(mcp_client, tool_name, _args) do
    Logger.error("Invalid MCP client type: #{inspect(mcp_client)} for tool: #{tool_name}")
    {:error, {:invalid_mcp_client, mcp_client}}
  end

  @spec execute_tool_via_hermes(atom() | pid(), String.t(), map()) :: {:ok, any()} | {:error, any()}
  defp execute_tool_via_hermes(mcp_client, tool_name, args) do
    Logger.debug("Executing tool '#{tool_name}' via Hermes client #{inspect(mcp_client)}")
    
    case Hermes.Client.call_tool(mcp_client, tool_name, args) do
      {:ok, result} ->
        Logger.debug("Tool '#{tool_name}' executed successfully")
        {:ok, result}
      
      {:error, reason} ->
        Logger.warning("Tool '#{tool_name}' execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Error calling Hermes.Client.call_tool for '#{tool_name}': #{inspect(error)}")
      {:error, {:hermes_error, error}}
  end

  @spec process_agent_input(any(), any(), any(), list()) :: 
    {:ok, any(), any()} | {:error, any()}
  defp process_agent_input(agent_impl, input, agent_state, tools) do
    try do
      Agent.process_input(agent_impl, input, agent_state, tools)
    rescue
      error ->
        {:error, {:agent_error, error}}
    end
  end

  @spec execute_agent_action(any(), any(), any(), function()) :: 
    {:ok, any(), any()} | {:error, any()}
  defp execute_agent_action(agent_impl, action, agent_state, tool_executor) do
    try do
      Agent.execute_action(agent_impl, action, agent_state, tool_executor)
    rescue
      error ->
        Logger.error("Agent action execution error: #{inspect(error)}")
        {:error, {:agent_execution_error, error}}
    end
  end

  @spec init_stats() :: map()
  defp init_stats do
    %{
      inputs_received: 0,
      inputs_processed: 0,
      input_errors: 0,
      actions_triggered: 0,
      actions_scheduled: 0,
      actions_executed: 0,
      action_errors: 0,
      tool_calls: 0,
      tool_errors: 0,
      autonomous_actions: 0
    }
  end

  @spec update_stats(map(), atom()) :: map()
  defp update_stats(stats, metric) do
    Map.update(stats, metric, 1, &(&1 + 1))
  end
end 