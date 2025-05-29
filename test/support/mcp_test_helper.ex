defmodule MCPAgent.Test.MCPTestHelper do
  @moduledoc """
  Test helper for mocking MCP client behavior in tests.
  
  This module provides utilities for testing AgentServer functionality
  without requiring real MCP servers or embedding mock logic in production code.
  """

  @doc """
  Creates a mock MCP client that implements the basic Hermes.Client interface.
  
  This is a GenServer that responds to list_tools and call_tool messages
  with predictable responses for testing.
  """
  def start_mock_mcp_client(opts \\ []) do
    tools = Keyword.get(opts, :tools, default_mock_tools())
    tool_responses = Keyword.get(opts, :tool_responses, %{})
    
    Agent.start_link(fn ->
      %{
        tools: tools,
        tool_responses: tool_responses,
        call_history: []
      }
    end)
  end

  @doc """
  Mock implementation of Hermes.Client.list_tools/1
  """
  def mock_list_tools(client_pid) do
    Agent.get(client_pid, fn state ->
      {:ok, %{tools: state.tools}}
    end)
  end

  @doc """
  Mock implementation of Hermes.Client.call_tool/3
  """
  def mock_call_tool(client_pid, tool_name, args) do
    Agent.get_and_update(client_pid, fn state ->
      # Record the call
      call_record = %{
        tool_name: tool_name,
        args: args,
        timestamp: DateTime.utc_now()
      }
      
      new_state = %{
        state | 
        call_history: [call_record | state.call_history]
      }
      
      # Return response
      response = case Map.get(state.tool_responses, tool_name) do
        nil -> default_tool_response(tool_name, args)
        response -> response
      end
      
      {response, new_state}
    end)
  end

  @doc """
  Get the call history from a mock client for assertions
  """
  def get_call_history(client_pid) do
    Agent.get(client_pid, &(&1.call_history))
  end

  @doc """
  Update the tools available from a mock client
  """
  def set_mock_tools(client_pid, tools) do
    Agent.update(client_pid, &(%{&1 | tools: tools}))
  end

  @doc """
  Set custom responses for specific tools
  """
  def set_tool_response(client_pid, tool_name, response) do
    Agent.update(client_pid, fn state ->
      %{state | tool_responses: Map.put(state.tool_responses, tool_name, response)}
    end)
  end

  # Private functions

  defp default_mock_tools do
    [
      %{
        name: "test_tool_1",
        description: "A test tool for unit testing",
        inputSchema: %{
          type: "object",
          properties: %{
            message: %{type: "string", description: "Test message"}
          }
        }
      },
      %{
        name: "test_tool_2", 
        description: "Another test tool",
        inputSchema: %{
          type: "object",
          properties: %{
            value: %{type: "integer", description: "Test value"}
          }
        }
      }
    ]
  end

  defp default_tool_response(tool_name, args) do
    {:ok, %{
      message: "Mock execution of #{tool_name}",
      tool_name: tool_name,
      args: args,
      timestamp: DateTime.utc_now(),
      mock: true
    }}
  end
end 