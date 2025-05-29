defprotocol MCPAgent.Agent do
  @moduledoc """
  Protocol defining the core behavior for all MCP-enabled agents.
  
  This protocol provides a consistent interface for agent implementations,
  allowing them to process inputs, make decisions, execute actions, and
  maintain state while leveraging MCP tools for external capabilities.
  
  ## Agent Lifecycle
  
  1. **Initialization**: Agent is initialized with configuration via `init/2`
  2. **Input Processing**: Agent processes user inputs via `process_input/4`
  3. **Action Decision**: Agent decides what actions to take via `decide_action/3`
  4. **Action Execution**: Agent executes actions using tools via `execute_action/4`
  5. **Status Reporting**: Agent reports its current state via `status/2`
  
  ## Example Implementation
  
      defmodule MyAgent do
        defstruct [:name, :data]
        
        def new(name), do: %__MODULE__{name: name, data: []}
      end
      
      defimpl MCPAgent.Agent, for: MyAgent do
        def init(agent, config) do
          %{agent: agent, processed_count: 0, config: config}
        end
        
        def process_input(agent, input, state, tools) do
          new_state = %{state | processed_count: state.processed_count + 1}
          {:ok, "Processed input", new_state}
        end
        
        def decide_action(agent, state, available_tools) do
          if state.processed_count > 3 do
            {:action, :summarize}
          else
            :no_action
          end
        end
        
        def execute_action(agent, action, state, tool_executor) do
          case action do
            :summarize ->
              {:ok, "Summary completed", state}
            _ ->
              {:error, "Unknown action"}
          end
        end
        
        def status(agent, state) do
          %{
            agent_name: agent.name,
            processed_count: state.processed_count
          }
        end
      end
  """

  @doc """
  Initialize the agent with configuration.
  
  This function is called when an agent is first started and should
  return the initial state that will be passed to other protocol functions.
  
  ## Parameters
  
  - `agent` - The agent struct implementing this protocol
  - `config` - A map containing configuration options for the agent
  
  ## Returns
  
  Returns the initial state for the agent (can be any term).
  """
  @spec init(t(), map()) :: any()
  def init(agent, config)

  @doc """
  Process incoming input and return response with new state.
  
  This is the main entry point for user interactions with the agent.
  The agent should process the input, potentially modify its state,
  and return an appropriate response.
  
  ## Parameters
  
  - `agent` - The agent struct implementing this protocol
  - `input` - The input to process (typically a string, but can be any term)
  - `state` - The current agent state
  - `tools` - List of available MCP tools (optional, defaults to empty list)
  
  ## Returns
  
  - `{:ok, response, new_state}` - Success with response and updated state
  - `{:error, reason}` - Error occurred during processing
  """
  @spec process_input(t(), any(), any(), list()) :: 
    {:ok, any(), any()} | {:error, any()}
  def process_input(agent, input, state, tools \\ [])

  @doc """
  Decide what action to take given current state.
  
  This function allows the agent to proactively decide what actions
  to take based on its current state and available tools. It's called
  after input processing and can trigger autonomous behavior.
  
  ## Parameters
  
  - `agent` - The agent struct implementing this protocol
  - `state` - The current agent state
  - `available_tools` - List of available MCP tools (optional, defaults to empty list)
  
  ## Returns
  
  - `{:action, action_term}` - Agent wants to execute the specified action
  - `:no_action` - Agent doesn't need to take any action currently
  """
  @spec decide_action(t(), any(), list()) :: 
    {:action, any()} | :no_action
  def decide_action(agent, state, available_tools \\ [])

  @doc """
  Execute a specific action using available tools.
  
  This function is called when an action needs to be executed, either
  as a result of `decide_action/3` or triggered manually. The agent
  can use the tool_executor function to interact with MCP tools.
  
  ## Parameters
  
  - `agent` - The agent struct implementing this protocol
  - `action` - The action to execute (as returned by `decide_action/3`)
  - `state` - The current agent state
  - `tool_executor` - Function to execute MCP tools: `(tool_name, args) -> result`
  
  ## Returns
  
  - `{:ok, result, new_state}` - Action executed successfully
  - `{:error, reason}` - Action execution failed
  """
  @spec execute_action(t(), any(), any(), function()) :: 
    {:ok, any(), any()} | {:error, any()}
  def execute_action(agent, action, state, tool_executor)

  @doc """
  Get agent's current status/summary.
  
  This function provides insight into the agent's current state
  and can be used for monitoring, debugging, or user interfaces.
  
  ## Parameters
  
  - `agent` - The agent struct implementing this protocol
  - `state` - The current agent state
  
  ## Returns
  
  Returns a map containing status information about the agent.
  """
  @spec status(t(), any()) :: map()
  def status(agent, state)
end 