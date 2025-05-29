defmodule MCPAgent.AgentServer.Server do
  @moduledoc """
  Pure GenServer implementation for AgentServer.
  
  This module contains only GenServer callbacks and message handling.
  All business logic is delegated to MCPAgent.AgentServer.Impl.
  """
  
  use GenServer
  require Logger
  
  alias MCPAgent.AgentServer.Impl

  # GenServer Callbacks

  @impl GenServer
  def init({agent_impl, agent_config, mcp_client}) do
    Logger.info("Starting AgentServer with agent: #{inspect(agent_impl)}")
    
    case Impl.init_state(agent_impl, agent_config, mcp_client) do
      {:ok, state} ->
        # Schedule periodic tool refresh if MCP client is configured
        if mcp_client do
          schedule_tool_refresh()
        end
        
        {:ok, state}
      
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_cast({:input, input}, state) do
    case Impl.process_input(state, input) do
      {:ok, _response, new_state} ->
        # Check if agent wants to take an autonomous action
        final_state = Impl.maybe_autonomous_action(new_state)
        {:noreply, final_state}
      
      {:error, _reason, new_state} ->
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_cast(:trigger_action, state) do
    new_state = Impl.trigger_action(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    response = Impl.get_state_response(state)
    {:reply, response, state}
  end

  @impl GenServer
  def handle_call(:get_tools, _from, state) do
    tools = Impl.get_tools(state)
    {:reply, tools, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = Impl.get_stats(state)
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_info(:refresh_tools, state) do
    new_state = Impl.refresh_tools(state)
    
    # Schedule next refresh
    schedule_tool_refresh()
    
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:tool_call_attempted, tool_name}, state) do
    Logger.debug("Tool call attempted: #{tool_name}")
    new_state = Impl.update_tool_stats(state, :attempted)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:tool_call_success, tool_name}, state) do
    Logger.debug("Tool call succeeded: #{tool_name}")
    new_state = Impl.update_tool_stats(state, :success)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:tool_call_error, tool_name}, state) do
    Logger.debug("Tool call failed: #{tool_name}")
    new_state = Impl.update_tool_stats(state, :error)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private server functions
  
  @spec schedule_tool_refresh() :: reference()
  defp schedule_tool_refresh do
    # Refresh tools every 30 seconds
    Process.send_after(self(), :refresh_tools, 30_000)
  end
end 