defmodule MCPAgent.AgentServer do
  @moduledoc """
  GenServer for managing individual agent instances with MCP tool integration.
  
  The AgentServer provides a supervised, stateful container for agent implementations
  that follow the MCPAgent.Agent protocol. It handles agent lifecycle, state management,
  input processing, and coordination with MCP tools.
  
  ## Architecture
  
  The AgentServer is designed to be tool-agnostic and work with any MCP client:
  
  - **Tool Discovery**: Uses Hermes.Client.list_tools/1 to dynamically discover available tools
  - **Tool Execution**: Uses Hermes.Client.call_tool/3 to execute tools via MCP protocol
  - **Separation of Concerns**: Does not define or hard-code specific tools
  - **Generic Design**: Works with any MCP server (knowledge graph, filesystem, etc.)
  
  ## MCP Integration
  
  The server expects an MCP client (from Hermes library) that handles:
  - Connection to external MCP servers (npm packages, separate processes)
  - Tool discovery and schema validation
  - Tool execution and result handling
  
  Example MCP clients: knowledge graph server, filesystem server, web search server
  
  ## Features
  
  - Agent initialization with configuration
  - Asynchronous input processing
  - State management and persistence
  - Dynamic MCP tool discovery and integration
  - Action triggering and execution
  - Status monitoring and reporting
  - Performance metrics and statistics
  
  ## Usage
  
      # Start an agent server with MCP client
      {:ok, pid} = MCPAgent.AgentServer.start_link([
        agent_impl: MyAgent.new("research-agent"),
        agent_config: %{domain: "AI research"},
        mcp_client: MCPAgent.KnowledgeClient  # Hermes client connected to knowledge server
      ])
      
      # Send input to the agent
      MCPAgent.AgentServer.send_input(pid, "research quantum computing")
      
      # Get current state and discovered tools
      state = MCPAgent.AgentServer.get_state(pid)
      tools = MCPAgent.AgentServer.get_tools(pid)  # Tools from MCP server
      
      # Trigger action decision (may use MCP tools)
      MCPAgent.AgentServer.trigger_action(pid)
  """
  
  use GenServer
  require Logger

  alias MCPAgent.Agent

  # Note: Hermes is used for MCP client communication
  # The dependency should be available when the AgentServer is used with real MCP clients

  # Client API

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
    GenServer.start_link(__MODULE__, init_args, opts)
  end

  @doc """
  Send input to the agent for processing.
  
  This is an asynchronous operation that will trigger the agent's
  process_input/4 function and potentially lead to autonomous actions.
  
  ## Parameters
  
  - `server` - The GenServer PID or registered name
  - `input` - Input to send to the agent (any term)
  
  ## Examples
  
      MCPAgent.AgentServer.send_input(pid, "research quantum computing")
      MCPAgent.AgentServer.send_input(:my_agent, %{command: "analyze", data: data})
  """
  @spec send_input(GenServer.server(), any()) :: :ok
  def send_input(server, input) do
    GenServer.cast(server, {:input, input})
  end

  @doc """
  Get the agent's current state and status information.
  
  Returns a map containing the agent's status, available tools count,
  and recent action history.
  
  ## Parameters
  
  - `server` - The GenServer PID or registered name
  
  ## Returns
  
  Returns a map with:
  - `:agent_status` - Status from agent.status/2
  - `:available_tools` - Number of available MCP tools
  - `:recent_actions` - List of recent actions (last 5)
  - `:server_info` - Server metadata
  """
  @spec get_state(GenServer.server()) :: map()
  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Get the list of available MCP tools.
  
  Returns the current list of tools available from the MCP client.
  
  ## Parameters
  
  - `server` - The GenServer PID or registered name
  
  ## Returns
  
  Returns a list of tool maps or an empty list if no MCP client is configured.
  """
  @spec get_tools(GenServer.server()) :: list()
  def get_tools(server) do
    GenServer.call(server, :get_tools)
  end

  @doc """
  Manually trigger the agent to decide and potentially execute an action.
  
  This bypasses the normal input-driven action flow and asks the agent
  to evaluate its current state and decide if any actions should be taken.
  
  ## Parameters
  
  - `server` - The GenServer PID or registered name
  """
  @spec trigger_action(GenServer.server()) :: :ok
  def trigger_action(server) do
    GenServer.cast(server, :trigger_action)
  end

  @doc """
  Get server statistics and performance metrics.
  
  Returns information about the server's operation including uptime,
  message counts, and performance data.
  
  ## Parameters
  
  - `server` - The GenServer PID or registered name
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(server) do
    GenServer.call(server, :get_stats)
  end

  # GenServer Callbacks

  @impl GenServer
  def init({agent_impl, agent_config, mcp_client}) do
    Logger.info("Starting AgentServer with agent: #{inspect(agent_impl)}")
    
    # Initialize the agent using the protocol
    try do
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
      
      Logger.info("AgentServer initialized successfully with #{length(tools)} tools")
      
      # Schedule periodic tool refresh if MCP client is configured
      if mcp_client do
        schedule_tool_refresh()
      end
      
      {:ok, state}
    rescue
      error ->
        Logger.error("Failed to initialize agent: #{inspect(error)}")
        {:stop, {:initialization_failed, error}}
    end
  end

  @impl GenServer
  def handle_cast({:input, input}, state) do
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
        
        # Check if agent wants to take an action after processing input
        {:noreply, maybe_trigger_autonomous_action(new_state)}
      
      {:error, reason} ->
        Logger.warning("Agent input processing failed: #{inspect(reason)}")
        
        new_state = %{
          state | 
          stats: update_stats(updated_stats, :input_error)
        }
        
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_cast(:trigger_action, state) do
    Logger.debug("Manually triggering action decision")
    
    updated_stats = update_stats(state.stats, :action_triggered)
    new_state = %{state | stats: updated_stats}
    
    {:noreply, execute_agent_action_cycle(new_state)}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    agent_status = Agent.status(state.agent_impl, state.agent_state)
    
    response = %{
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
    
    {:reply, response, state}
  end

  @impl GenServer
  def handle_call(:get_tools, _from, state) do
    {:reply, state.tools, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats_with_uptime = Map.put(state.stats, :uptime_seconds, 
      DateTime.diff(DateTime.utc_now(), state.started_at))
    
    {:reply, stats_with_uptime, state}
  end

  @impl GenServer
  def handle_info(:refresh_tools, state) do
    Logger.debug("Refreshing MCP tools")
    
    new_tools = fetch_mcp_tools(state.mcp_client)
    new_state = %{state | tools: new_tools}
    
    # Schedule next refresh
    schedule_tool_refresh()
    
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:tool_call_attempted, tool_name}, state) do
    Logger.debug("Tool call attempted: #{tool_name}")
    updated_stats = update_stats(state.stats, :tool_calls)
    {:noreply, %{state | stats: updated_stats}}
  end

  @impl GenServer
  def handle_info({:tool_call_success, tool_name}, state) do
    Logger.debug("Tool call succeeded: #{tool_name}")
    # Tool success is already counted in tool_calls, no additional stat needed
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:tool_call_error, tool_name}, state) do
    Logger.debug("Tool call failed: #{tool_name}")
    updated_stats = update_stats(state.stats, :tool_errors)
    {:noreply, %{state | stats: updated_stats}}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helper Functions

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

  @spec maybe_trigger_autonomous_action(map()) :: map()
  defp maybe_trigger_autonomous_action(state) do
    case Agent.decide_action(state.agent_impl, state.agent_state, state.tools) do
      {:action, action} ->
        Logger.debug("Agent decided to take autonomous action: #{inspect(action)}")
        updated_stats = update_stats(state.stats, :autonomous_actions)
        new_state = %{state | stats: updated_stats}
        execute_action_with_decision(new_state, action)
      
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

  @spec execute_agent_action_cycle(map()) :: map()
  defp execute_agent_action_cycle(state) do
    case Agent.decide_action(state.agent_impl, state.agent_state, state.tools) do
      {:action, action} ->
        Logger.debug("Executing decided action: #{inspect(action)}")
        execute_action_with_decision(state, action)
      
      :no_action ->
        Logger.debug("No action decided during manual trigger")
        state
      
      other ->
        Logger.warning("Unexpected action decision: #{inspect(other)}")
        state
    end
  rescue
    error ->
      Logger.error("Error in action cycle: #{inspect(error)}")
      state
  end

  @spec execute_action_with_decision(map(), any()) :: map()
  defp execute_action_with_decision(state, action) do
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
      # Send stats update to the server process
      send(self(), {:tool_call_attempted, tool_name})
      
      case execute_mcp_tool(mcp_client, tool_name, args) do
        {:ok, _result} = success ->
          send(self(), {:tool_call_success, tool_name})
          success
        
        {:error, _reason} = error ->
          send(self(), {:tool_call_error, tool_name})
          error
      end
    end
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

  @spec schedule_tool_refresh() :: reference()
  defp schedule_tool_refresh do
    # Refresh tools every 30 seconds
    Process.send_after(self(), :refresh_tools, 30_000)
  end
end 