# MCP-Powered Agent System with Protocols and GenServer

This guide shows you how to build a powerful agent system using Elixir Protocols for pluggable behavior and GenServer for state management, with MCP tools via Hermes for external capabilities. Our focus is on a **Learning Agent** that can process files and build a persistent knowledge graph.

## Key Insights from Code-Editing Agent Research

Based on the excellent blog post about building code-editing agents, we've learned that effective agents follow these principles:

- **Simple Core Loop**: LLM + loop + tools - that's the foundation
- **Well-Defined Tools**: Each tool needs a clear name, description, and input schema  
- **Model Intelligence**: Modern LLMs are excellent at deciding when and how to combine tools
- **String-Based Operations**: Work very well with current models
- **Practical Focus**: Well-defined tool functions matter more than complex abstractions

Our agent system will embody these principles while leveraging Elixir's strengths.

## Project Setup

### 1. Create New Elixir Application

```bash
mix new mcp_agent --sup
cd mcp_agent
```

### 2. Add Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:hermes_mcp, "~> 0.4"},
    {:jason, "~> 1.4"}
  ]
end
```

```bash
mix deps.get
```

## Core Architecture

### 3. Define the Agent Protocol

```elixir
# lib/mcp_agent/protocols/agent.ex
defprotocol MCPAgent.Agent do
  @doc "Initialize the agent with configuration"
  def init(agent, config)
  
  @doc "Process incoming input and return response with new state"
  def process_input(agent, input, state, tools \\ [])
  
  @doc "Decide what action to take given current state"
  def decide_action(agent, state, available_tools \\ [])
  
  @doc "Execute a specific action using available tools"
  def execute_action(agent, action, state, tool_executor)
  
  @doc "Get agent's current status/summary"
  def status(agent, state)
end
```

### 4. Create the AgentServer GenServer

```elixir
# lib/mcp_agent/agent_server.ex
defmodule MCPAgent.AgentServer do
  use GenServer
  require Logger

  @doc """
  Start an agent server with a specific agent implementation and MCP tools
  
  ## Options
  - `:agent_impl` - Module implementing the Agent protocol
  - `:agent_config` - Configuration passed to agent.init/2
  - `:mcp_client` - Name of the MCP client process
  - `:name` - Name to register this GenServer
  """
  def start_link(opts \\ []) do
    {agent_impl, opts} = Keyword.pop!(opts, :agent_impl)
    {agent_config, opts} = Keyword.pop(opts, :agent_config, %{})
    {mcp_client, opts} = Keyword.pop(opts, :mcp_client)
    
    GenServer.start_link(__MODULE__, {agent_impl, agent_config, mcp_client}, opts)
  end

  @doc "Send input to the agent"
  def send_input(pid, input) do
    GenServer.cast(pid, {:input, input})
  end

  @doc "Get the agent's current state"
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc "Get available MCP tools"
  def get_tools(pid) do
    GenServer.call(pid, :get_tools)
  end

  @doc "Trigger agent to decide and execute an action"
  def trigger_action(pid) do
    GenServer.cast(pid, :trigger_action)
  end

  # GenServer Callbacks

  def init({agent_impl, agent_config, mcp_client}) do
    # Initialize the agent
    initial_agent_state = MCPAgent.Agent.init(agent_impl, agent_config)
    
    # Get available tools from MCP
    tools = fetch_mcp_tools(mcp_client)
    
    state = %{
      agent_impl: agent_impl,
      agent_state: initial_agent_state,
      mcp_client: mcp_client,
      tools: tools,
      action_history: []
    }
    
    Logger.info("Agent server started with #{length(tools)} available tools")
    
    {:ok, state}
  end

  def handle_cast({:input, input}, state) do
    %{agent_impl: agent, agent_state: agent_state, tools: tools} = state
    
    Logger.info("Processing input: #{inspect(input)}")
    
    # Process input through the agent
    case MCPAgent.Agent.process_input(agent, input, agent_state, tools) do
      {:ok, response, new_agent_state} ->
        Logger.info("Agent response: #{inspect(response)}")
        
        new_state = %{state | agent_state: new_agent_state}
        
        # Automatically check if agent wants to take action
        maybe_trigger_action(new_state)
        
      {:error, reason} ->
        Logger.error("Agent processing error: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast(:trigger_action, state) do
    execute_agent_action(state)
  end

  def handle_call(:get_state, _from, state) do
    status = MCPAgent.Agent.status(state.agent_impl, state.agent_state)
    response = %{
      agent_status: status,
      available_tools: length(state.tools),
      recent_actions: Enum.take(state.action_history, 5)
    }
    {:reply, response, state}
  end

  def handle_call(:get_tools, _from, state) do
    {:reply, state.tools, state}
  end

  # Private Functions

  defp fetch_mcp_tools(nil), do: []
  defp fetch_mcp_tools(mcp_client) do
    case Hermes.Client.list_tools(mcp_client) do
      {:ok, %{tools: tools}} -> 
        tools
      {:error, reason} ->
        Logger.warning("Failed to fetch MCP tools: #{inspect(reason)}")
        []
    end
  end

  defp maybe_trigger_action(state) do
    case MCPAgent.Agent.decide_action(state.agent_impl, state.agent_state, state.tools) do
      {:action, action} ->
        Logger.info("Agent decided to take action: #{inspect(action)}")
        execute_agent_action_with_decision(state, action)
      
      :no_action ->
        {:noreply, state}
    end
  end

  defp execute_agent_action(state) do
    case MCPAgent.Agent.decide_action(state.agent_impl, state.agent_state, state.tools) do
      {:action, action} ->
        execute_agent_action_with_decision(state, action)
      
      :no_action ->
        Logger.info("Agent decided no action needed")
        {:noreply, state}
    end
  end

  defp execute_agent_action_with_decision(state, action) do
    tool_executor = fn tool_name, args ->
      case state.mcp_client do
        nil -> {:error, "No MCP client available"}
        client -> Hermes.Client.call_tool(client, tool_name, args)
      end
    end

    case MCPAgent.Agent.execute_action(state.agent_impl, action, state.agent_state, tool_executor) do
      {:ok, result, new_agent_state} ->
        Logger.info("Action executed successfully: #{inspect(result)}")
        
        action_record = %{
          action: action,
          result: result,
          timestamp: DateTime.utc_now()
        }
        
        new_state = %{
          state | 
          agent_state: new_agent_state,
          action_history: [action_record | state.action_history]
        }
        
        {:noreply, new_state}
      
      {:error, reason} ->
        Logger.error("Action execution failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end
end
```

### 5. Learning Agent Implementation

The Learning Agent is designed to process files and build a persistent knowledge graph using the MCP knowledge graph server.

#### Learning Agent Structure

```elixir
# lib/mcp_agent/agents/learning_agent.ex
defmodule MCPAgent.Agents.LearningAgent do
  @derive Jason.Encoder
  defstruct [:supported_file_types, :extraction_strategies, :knowledge_categories]

  def new(supported_file_types \\ [".md", ".txt", ".ex", ".exs", ".json", ".yaml"]) do
    %__MODULE__{
      supported_file_types: supported_file_types,
      extraction_strategies: %{
        ".md" => :markdown_parser,
        ".txt" => :text_parser,
        ".ex" => :elixir_code_parser,
        ".exs" => :elixir_code_parser,
        ".json" => :json_parser,
        ".yaml" => :yaml_parser
      },
      knowledge_categories: [:concepts, :functions, :documentation, :examples, :relationships]
    }
  end
end

defimpl MCPAgent.Agent, for: MCPAgent.Agents.LearningAgent do
  def init(agent, config) do
    %{
      agent: agent,
      file_queue: [],
      processed_files: MapSet.new(),
      knowledge_stats: %{
        entities_created: 0,
        relations_created: 0,
        observations_added: 0
      },
      current_task: nil,
      learning_session_id: Map.get(config, :session_id, generate_session_id())
    }
  end

  def process_input(agent, input, state, tools) do
    case parse_learning_input(input) do
      {:file_list, file_paths} ->
        # Add files to processing queue
        new_files = Enum.reject(file_paths, &MapSet.member?(state.processed_files, &1))
        new_state = %{state | file_queue: new_files ++ state.file_queue}
        
        response = "Added #{length(new_files)} files to learning queue. Total queue: #{length(new_state.file_queue)}"
        {:ok, response, new_state}
      
      {:query, question} ->
        # Query the knowledge graph
        new_state = %{state | current_task: {:answer_query, question}}
        {:ok, "Searching knowledge graph for: #{question}", new_state}
      
      {:status} ->
        status = format_learning_status(state)
        {:ok, status, state}
        
      {:learn_from, file_path} ->
        # Add single file for immediate processing
        if file_supported?(file_path, agent.supported_file_types) do
          new_state = %{state | file_queue: [file_path | state.file_queue]}
          {:ok, "Added #{file_path} for learning", new_state}
        else
          {:ok, "File type not supported: #{file_path}", state}
        end
      
      {:clear_queue} ->
        new_state = %{state | file_queue: []}
        {:ok, "Learning queue cleared", new_state}
      
      {:unknown, _} ->
        help_text = """
        Learning Agent Commands:
        - "learn from file1.md, file2.ex, file3.txt" - Add files to learning queue
        - "learn from path/to/file.md" - Add single file for learning  
        - "what do you know about X?" - Query knowledge graph
        - "status" - Show learning progress
        - "clear queue" - Clear file processing queue
        """
        {:ok, help_text, state}
    end
  end

  def decide_action(agent, state, available_tools) do
    cond do
      # Process files if queue is not empty and we have file reading tools
      length(state.file_queue) > 0 && has_file_tools?(available_tools) ->
        {:action, {:process_next_file}}
      
      # Answer query if we have one pending and knowledge graph tools
      match?({:answer_query, _}, state.current_task) && has_knowledge_tools?(available_tools) ->
        {:action, state.current_task}
      
      # Summarize learning if we have processed many files
      length(state.processed_files) > 0 && rem(MapSet.size(state.processed_files), 10) == 0 ->
        {:action, {:summarize_learning}}
        
      true ->
        :no_action
    end
  end

  def execute_action(agent, action, state, tool_executor) do
    case action do
      {:process_next_file} ->
        case state.file_queue do
          [file_path | remaining_files] ->
            case process_file_for_learning(file_path, agent, tool_executor) do
              {:ok, knowledge_extracted} ->
                new_processed = MapSet.put(state.processed_files, file_path)
                updated_stats = update_knowledge_stats(state.knowledge_stats, knowledge_extracted)
                
                new_state = %{
                  state |
                  file_queue: remaining_files,
                  processed_files: new_processed,
                  knowledge_stats: updated_stats
                }
                
                {:ok, "Learned from #{file_path}: #{format_extraction_summary(knowledge_extracted)}", new_state}
              
              {:error, reason} ->
                new_state = %{state | file_queue: remaining_files}
                {:ok, "Failed to learn from #{file_path}: #{reason}", new_state}
            end
          
          [] ->
            {:ok, "No files in queue to process", state}
        end
      
      {:answer_query, question} ->
        case search_knowledge_graph(question, tool_executor) do
          {:ok, results} ->
            answer = format_knowledge_answer(results, question)
            new_state = %{state | current_task: nil}
            {:ok, answer, new_state}
          
          {:error, reason} ->
            new_state = %{state | current_task: nil}
            {:ok, "Failed to search knowledge: #{reason}", new_state}
        end
      
      {:summarize_learning} ->
        case generate_learning_summary(state, tool_executor) do
          {:ok, summary} ->
            {:ok, "Learning Summary: #{summary}", state}
          
          {:error, reason} ->
            {:ok, "Failed to generate summary: #{reason}", state}
        end
    end
  end

  def status(agent, state) do
    %{
      type: "Learning Agent",
      session_id: state.learning_session_id,
      files_in_queue: length(state.file_queue),
      files_processed: MapSet.size(state.processed_files),
      knowledge_stats: state.knowledge_stats,
      current_task: state.current_task,
      supported_file_types: agent.supported_file_types
    }
  end

  # Private helper functions
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp parse_learning_input(input) do
    input_lower = String.downcase(String.trim(input))
    
    cond do
      String.starts_with?(input_lower, "learn from ") ->
        file_part = String.slice(input, 11..-1)
        file_paths = 
          file_part
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
        
        {:file_list, file_paths}
      
      String.starts_with?(input_lower, "what") && String.contains?(input_lower, "know") ->
        question = String.replace_prefix(input_lower, "what do you know about ", "")
        |> String.replace_suffix("?", "")
        |> String.trim()
        {:query, question}
      
      input_lower == "status" ->
        {:status}
      
      input_lower == "clear queue" ->
        {:clear_queue}
      
      true ->
        {:unknown, input}
    end
  end

  defp file_supported?(file_path, supported_types) do
    ext = Path.extname(file_path)
    ext in supported_types
  end

  defp has_file_tools?(tools) do
    Enum.any?(tools, fn tool ->
      name = tool.name || ""
      String.contains?(name, "read") && String.contains?(name, "file")
    end)
  end

  defp has_knowledge_tools?(tools) do
    knowledge_tool_names = ["search_nodes", "read_graph", "create_entities", "add_observations"]
    
    Enum.any?(tools, fn tool ->
      name = tool.name || ""
      name in knowledge_tool_names
    end)
  end

  defp process_file_for_learning(file_path, agent, tool_executor) do
    # Read the file content
    case tool_executor.("read_file", %{"path" => file_path}) do
      {:ok, %{content: content}} ->
        # Extract knowledge based on file type
        file_ext = Path.extname(file_path)
        extraction_strategy = Map.get(agent.extraction_strategies, file_ext, :text_parser)
        
        case extract_knowledge(content, file_path, extraction_strategy) do
          {:ok, knowledge} ->
            # Store knowledge in the graph
            store_knowledge_in_graph(knowledge, file_path, tool_executor)
          
          {:error, reason} ->
            {:error, "Knowledge extraction failed: #{reason}"}
        end
      
      {:error, reason} ->
        {:error, "File reading failed: #{reason}"}
    end
  end

  defp extract_knowledge(content, file_path, strategy) do
    case strategy do
      :markdown_parser ->
        extract_markdown_knowledge(content, file_path)
      
      :text_parser ->
        extract_text_knowledge(content, file_path)
      
      :elixir_code_parser ->
        extract_elixir_knowledge(content, file_path)
      
      :json_parser ->
        extract_json_knowledge(content, file_path)
      
      _ ->
        extract_text_knowledge(content, file_path)
    end
  end

  defp extract_markdown_knowledge(content, file_path) do
    entities = []
    observations = []
    relations = []
    
    # Extract headers as concepts
    headers = Regex.scan(~r/^#+\s+(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [header] -> String.trim(header) end)
    
    # Create entities for each header
    header_entities = Enum.map(headers, fn header ->
      %{
        name: normalize_entity_name("#{file_path}_#{header}"),
        entityType: "concept",
        observations: ["Defined in #{file_path}", "Header: #{header}"]
      }
    end)
    
    # Extract code blocks as examples
    code_blocks = Regex.scan(~r/```(\w+)?\n(.*?)```/s, content, capture: :all_but_first)
    |> Enum.with_index()
    |> Enum.map(fn {[lang, code], index} ->
      %{
        name: normalize_entity_name("#{file_path}_code_#{index}"),
        entityType: "example", 
        observations: [
          "Code example from #{file_path}",
          "Language: #{lang}",
          "Code: #{String.slice(code, 0, 200)}..."
        ]
      }
    end)
    
    all_entities = header_entities ++ code_blocks
    
    {:ok, %{
      entities: all_entities,
      relations: relations,
      observations: observations,
      file_path: file_path
    }}
  end

  defp extract_text_knowledge(content, file_path) do
    # Simple text extraction - treat each paragraph as an observation
    paragraphs = content
    |> String.split("\n\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.take(10)  # Limit to first 10 paragraphs
    
    entity_name = normalize_entity_name(file_path)
    
    entities = [%{
      name: entity_name,
      entityType: "document",
      observations: ["Text file: #{file_path}"] ++ paragraphs
    }]
    
    {:ok, %{
      entities: entities,
      relations: [],
      observations: [],
      file_path: file_path
    }}
  end

  defp extract_elixir_knowledge(content, file_path) do
    entities = []
    
    # Extract module definitions
    modules = Regex.scan(~r/defmodule\s+([\w\.]+)/, content, capture: :all_but_first)
    |> Enum.map(fn [module_name] -> 
      %{
        name: normalize_entity_name(module_name),
        entityType: "module",
        observations: ["Defined in #{file_path}", "Elixir module"]
      }
    end)
    
    # Extract function definitions
    functions = Regex.scan(~r/def\s+(\w+)/, content, capture: :all_but_first)
    |> Enum.map(fn [func_name] ->
      %{
        name: normalize_entity_name("#{file_path}_#{func_name}"),
        entityType: "function",
        observations: ["Function in #{file_path}", "Name: #{func_name}"]
      }
    end)
    
    all_entities = modules ++ functions
    
    {:ok, %{
      entities: all_entities,
      relations: [],
      observations: [],
      file_path: file_path
    }}
  end

  defp extract_json_knowledge(content, file_path) do
    case Jason.decode(content) do
      {:ok, data} ->
        entity_name = normalize_entity_name(file_path)
        observations = extract_json_observations(data, [])
        
        entities = [%{
          name: entity_name,
          entityType: "data",
          observations: ["JSON file: #{file_path}"] ++ observations
        }]
        
        {:ok, %{
          entities: entities,
          relations: [],
          observations: [],
          file_path: file_path
        }}
      
      {:error, _} ->
        # Fall back to text extraction if JSON parsing fails
        extract_text_knowledge(content, file_path)
    end
  end

  defp extract_json_observations(data, acc, depth \\ 0) do
    if depth > 3, do: acc  # Limit recursion depth
    
    case data do
      map when is_map(map) ->
        Enum.reduce(map, acc, fn {key, value}, acc_inner ->
          observation = "#{key}: #{inspect(value) |> String.slice(0, 100)}"
          new_acc = [observation | acc_inner]
          
          if is_map(value) or is_list(value) do
            extract_json_observations(value, new_acc, depth + 1)
          else
            new_acc
          end
        end)
      
      list when is_list(list) ->
        list
        |> Enum.take(5)  # Limit list processing
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {item, index}, acc_inner ->
          observation = "Item #{index}: #{inspect(item) |> String.slice(0, 100)}"
          [observation | acc_inner]
        end)
      
      _ ->
        acc
    end
  end

  defp normalize_entity_name(name) do
    name
    |> String.replace(~r/[^\w\-_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  defp store_knowledge_in_graph(knowledge, file_path, tool_executor) do
    # Create entities
    entities_result = if length(knowledge.entities) > 0 do
      tool_executor.("create_entities", %{"entities" => knowledge.entities})
    else
      {:ok, %{}}
    end
    
    case entities_result do
      {:ok, _} ->
        # Create relations if any
        relations_result = if length(knowledge.relations) > 0 do
          tool_executor.("create_relations", %{"relations" => knowledge.relations})
        else
          {:ok, %{}}
        end
        
        case relations_result do
          {:ok, _} ->
            {:ok, %{
              entities_created: length(knowledge.entities),
              relations_created: length(knowledge.relations),
              observations_added: Enum.sum(Enum.map(knowledge.entities, &length(&1.observations))),
              file_path: file_path
            }}
          
          {:error, reason} ->
            {:error, "Failed to create relations: #{reason}"}
        end
      
      {:error, reason} ->
        {:error, "Failed to create entities: #{reason}"}
    end
  end

  defp search_knowledge_graph(query, tool_executor) do
    case tool_executor.("search_nodes", %{"query" => query}) do
      {:ok, %{nodes: nodes}} ->
        {:ok, nodes}
      
      {:ok, result} ->
        # Handle different response formats
        {:ok, result}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_knowledge_answer(results, question) do
    case results do
      [] ->
        "I don't have specific knowledge about '#{question}' in my knowledge graph yet."
      
      nodes when is_list(nodes) ->
        summaries = nodes
        |> Enum.take(5)
        |> Enum.map(fn node ->
          name = Map.get(node, "name", "Unknown")
          type = Map.get(node, "entityType", "Unknown")
          observations = Map.get(node, "observations", [])
          
          obs_text = observations
          |> Enum.take(3)
          |> Enum.join("; ")
          
          "- #{name} (#{type}): #{obs_text}"
        end)
        |> Enum.join("\n")
        
        "Here's what I know about '#{question}':\n#{summaries}"
      
      _ ->
        "Found some information about '#{question}': #{inspect(results)}"
    end
  end

  defp generate_learning_summary(state, tool_executor) do
    # Get overview of knowledge graph
    case tool_executor.("read_graph", %{}) do
      {:ok, graph_data} ->
        summary = """
        Learning Session Summary:
        - Files processed: #{MapSet.size(state.processed_files)}
        - Entities created: #{state.knowledge_stats.entities_created}
        - Relations created: #{state.knowledge_stats.relations_created}
        - Observations added: #{state.knowledge_stats.observations_added}
        - Session ID: #{state.learning_session_id}
        """
        
        {:ok, summary}
      
      {:error, reason} ->
        {:error, "Failed to read knowledge graph: #{reason}"}
    end
  end

  defp format_learning_status(state) do
    """
    Learning Agent Status:
    - Files in queue: #{length(state.file_queue)}
    - Files processed: #{MapSet.size(state.processed_files)}
    - Entities created: #{state.knowledge_stats.entities_created}
    - Relations created: #{state.knowledge_stats.relations_created}
    - Observations added: #{state.knowledge_stats.observations_added}
    - Current task: #{inspect(state.current_task)}
    - Session: #{state.learning_session_id}
    """
  end

  defp format_extraction_summary(knowledge) do
    "#{knowledge.entities_created} entities, #{knowledge.relations_created} relations, #{knowledge.observations_added} observations"
  end

  defp update_knowledge_stats(current_stats, extraction_result) do
    %{
      entities_created: current_stats.entities_created + extraction_result.entities_created,
      relations_created: current_stats.relations_created + extraction_result.relations_created,
      observations_added: current_stats.observations_added + extraction_result.observations_added
    }
  end
end
```

### 6. Task Automation Agent

We'll also keep the Task Automation Agent for completeness:

```elixir
# lib/mcp_agent/agents/task_automation.ex
defmodule MCPAgent.Agents.TaskAutomation do
  @derive Jason.Encoder
  defstruct [:task_queue, :automation_rules, :execution_history]

  def new(automation_rules \\ []) do
    %__MODULE__{
      task_queue: [],
      automation_rules: automation_rules,
      execution_history: []
    }
  end
end

defimpl MCPAgent.Agent, for: MCPAgent.Agents.TaskAutomation do
  def init(agent, config) do
    %{
      agent: agent,
      pending_tasks: [],
      completed_tasks: [],
      failed_tasks: [],
      auto_execute: Map.get(config, :auto_execute, true)
    }
  end

  def process_input(agent, input, state, tools) do
    case parse_task_input(input) do
      {:add_task, task} ->
        new_state = %{state | pending_tasks: [task | state.pending_tasks]}
        {:ok, "Task added: #{task.name}", new_state}
      
      {:list_tasks} ->
        task_summary = summarize_tasks(state)
        {:ok, task_summary, state}
      
      {:execute_task, task_id} ->
        case find_task(state.pending_tasks, task_id) do
          {:ok, task} ->
            new_state = mark_task_for_execution(state, task)
            {:ok, "Task #{task.name} queued for execution", new_state}
          
          :not_found ->
            {:ok, "Task not found", state}
        end
      
      _ ->
        {:ok, "I can help with task automation. Try 'add task: <description>' or 'list tasks'", state}
    end
  end

  def decide_action(agent, state, available_tools) do
    cond do
      state.auto_execute && length(state.pending_tasks) > 0 ->
        {:action, {:execute_next_task}}
      
      length(state.failed_tasks) > 0 ->
        {:action, {:retry_failed_tasks}}
      
      true ->
        :no_action
    end
  end

  def execute_action(agent, action, state, tool_executor) do
    case action do
      {:execute_next_task} ->
        case state.pending_tasks do
          [task | remaining_tasks] ->
            case execute_task_with_tools(task, tool_executor) do
              {:ok, result} ->
                completed_task = %{task | result: result, completed_at: DateTime.utc_now()}
                new_state = %{
                  state |
                  pending_tasks: remaining_tasks,
                  completed_tasks: [completed_task | state.completed_tasks]
                }
                {:ok, "Task '#{task.name}' completed successfully", new_state}
              
              {:error, reason} ->
                failed_task = %{task | error: reason, failed_at: DateTime.utc_now()}
                new_state = %{
                  state |
                  pending_tasks: remaining_tasks,
                  failed_tasks: [failed_task | state.failed_tasks]
                }
                {:ok, "Task '#{task.name}' failed: #{reason}", new_state}
            end
          
          [] ->
            {:ok, "No pending tasks to execute", state}
        end
      
      {:retry_failed_tasks} ->
        # Move failed tasks back to pending with retry count
        retryable_tasks = Enum.map(state.failed_tasks, fn task ->
          %{task | retry_count: (task.retry_count || 0) + 1}
        end)
        
        new_state = %{
          state |
          pending_tasks: retryable_tasks ++ state.pending_tasks,
          failed_tasks: []
        }
        
        {:ok, "Retrying #{length(retryable_tasks)} failed tasks", new_state}
    end
  end

  def status(agent, state) do
    %{
      type: "Task Automation Agent",
      pending_tasks: length(state.pending_tasks),
      completed_tasks: length(state.completed_tasks),
      failed_tasks: length(state.failed_tasks),
      auto_execute: state.auto_execute
    }
  end

  # Private helper functions
  defp parse_task_input("add task: " <> description) do
    task = %{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(),
      name: String.trim(description),
      created_at: DateTime.utc_now(),
      type: :manual
    }
    {:add_task, task}
  end

  defp parse_task_input("list tasks"), do: {:list_tasks}
  defp parse_task_input("execute " <> task_id), do: {:execute_task, String.trim(task_id)}
  defp parse_task_input(_), do: {:unknown}

  defp summarize_tasks(state) do
    """
    Task Summary:
    - Pending: #{length(state.pending_tasks)}
    - Completed: #{length(state.completed_tasks)}
    - Failed: #{length(state.failed_tasks)}
    """
  end

  defp find_task(tasks, task_id) do
    case Enum.find(tasks, fn task -> task.id == task_id end) do
      nil -> :not_found
      task -> {:ok, task}
    end
  end

  defp mark_task_for_execution(state, task) do
    updated_tasks = Enum.map(state.pending_tasks, fn t ->
      if t.id == task.id, do: %{t | priority: :high}, else: t
    end)
    %{state | pending_tasks: updated_tasks}
  end

  defp execute_task_with_tools(task, tool_executor) do
    # This would contain logic to determine which tools to use for the task
    # and execute them in sequence
    case task.type do
      :manual ->
        # For manual tasks, we might use a general-purpose execution tool
        tool_executor.("execute_command", %{"command" => task.name})
      
      _ ->
        {:ok, "Task executed (simulation)"}
    end
  end
end
```

### 7. Application Setup with MCP Knowledge Graph Server

```elixir
# lib/mcp_agent/application.ex
defmodule MCPAgent.Application do
  use Application
  require Logger

  def start(_type, _args) do
    children = [
      # Knowledge Graph MCP Server (using mcp-knowledge-graph)
      {Hermes.Transport.STDIO, [
        name: MCPAgent.KnowledgeTransport,
        client: MCPAgent.KnowledgeClient,
        command: "npx",  
        args: ["-y", "mcp-knowledge-graph", "--memory-path", "./knowledge/learning_memory.jsonl"]
      ]},
      
      # Knowledge Graph MCP Client
      {Hermes.Client, [
        name: MCPAgent.KnowledgeClient,
        transport: [layer: Hermes.Transport.STDIO, name: MCPAgent.KnowledgeTransport],
        client_info: %{
          "name" => "MCPAgent",
          "version" => "1.0.0"
        },
        capabilities: %{
          "roots" => %{"listChanged" => true},
          "sampling" => %{}
        }
      ]},
      
      # Filesystem MCP Server (optional - could implement our own read_file tool instead)
      {Hermes.Transport.STDIO, [
        name: MCPAgent.FilesystemTransport,
        client: MCPAgent.FilesystemClient,
        command: "mcp-filesystem-server",  # Adjust based on installation
        args: ["--root", "."]
      ]},
      
      # Filesystem MCP Client
      {Hermes.Client, [
        name: MCPAgent.FilesystemClient,
        transport: [layer: Hermes.Transport.STDIO, name: MCPAgent.FilesystemTransport],
        client_info: %{
          "name" => "MCPAgent",
          "version" => "1.0.0"
        },
        capabilities: %{
          "roots" => %{"listChanged" => true},
          "sampling" => %{}
        }
      ]},
      
      # Learning Agent (primary focus)
      {MCPAgent.AgentServer, [
        name: MCPAgent.LearningAgent,
        agent_impl: MCPAgent.Agents.LearningAgent,
        agent_config: %{
          session_id: "learning_session_#{:os.system_time(:second)}",
          supported_file_types: [".md", ".txt", ".ex", ".exs", ".json", ".yaml", ".yml", ".js", ".py"]
        },
        mcp_client: MCPAgent.KnowledgeClient  # Use knowledge graph client
      ]},
      
      # Task Automation Agent  
      {MCPAgent.AgentServer, [
        name: MCPAgent.TaskAgent,
        agent_impl: MCPAgent.Agents.TaskAutomation,
        agent_config: %{auto_execute: true},
        mcp_client: MCPAgent.FilesystemClient  # Use filesystem client for tasks
      ]}
    ]

    opts = [strategy: :one_for_one, name: MCPAgent.Supervisor]
    Logger.info("Starting MCP Agent system with Learning Agent focus...")
    Supervisor.start_link(children, opts)
  end
end
```

### 8. Usage Examples

```elixir
# lib/mcp_agent/examples.ex
defmodule MCPAgent.Examples do
  @doc "Demonstrate learning agent functionality"
  def demo_learning do
    # Start learning from files
    MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "learn from README.md, lib/mcp_agent.ex, mix.exs")
    
    # Check learning progress
    :timer.sleep(2000)  # Give it time to process
    status = MCPAgent.AgentServer.get_state(MCPAgent.LearningAgent)
    IO.inspect(status, label: "Learning Agent Status")
    
    # Query the knowledge
    MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "what do you know about MCP?")
    MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "what do you know about agents?")
    
    # Get final status
    :timer.sleep(1000)
    final_status = MCPAgent.AgentServer.get_state(MCPAgent.LearningAgent)
    IO.inspect(final_status, label: "Final Learning Status")
  end

  @doc "Create a learning session for a specific project"
  def learn_from_project(project_files) do
    file_list = Enum.join(project_files, ", ")
    MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "learn from #{file_list}")
    
    # Trigger processing
    MCPAgent.AgentServer.trigger_action(MCPAgent.LearningAgent)
    
    # Get available tools
    tools = MCPAgent.AgentServer.get_tools(MCPAgent.LearningAgent)
    IO.inspect(tools, label: "Available MCP Tools")
  end

  @doc "Demonstrate task automation with learning"
  def demo_task_automation do
    # Add some tasks
    MCPAgent.AgentServer.send_input(MCPAgent.TaskAgent, "add task: analyze project structure")
    MCPAgent.AgentServer.send_input(MCPAgent.TaskAgent, "add task: generate documentation")
    
    # Check task status
    task_status = MCPAgent.AgentServer.get_state(MCPAgent.TaskAgent)
    IO.inspect(task_status, label: "Task Agent Status")
  end

  @doc "Interactive learning session"
  def interactive_learning do
    IO.puts("Starting interactive learning session...")
    IO.puts("Commands:")
    IO.puts("  learn from <files> - Add files to learning queue")
    IO.puts("  what do you know about <topic>? - Query knowledge")
    IO.puts("  status - Show learning progress")
    IO.puts("  quit - Exit session")
    
    learning_loop()
  end

  defp learning_loop do
    input = IO.gets("Learning> ") |> String.trim()
    
    case input do
      "quit" ->
        IO.puts("Learning session ended.")
        
      "" ->
        learning_loop()
        
      command ->
        MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, command)
        :timer.sleep(500)  # Give it time to process
        learning_loop()
    end
  end
end
```

### 9. Testing

```elixir
# test/mcp_agent/learning_agent_test.exs
defmodule MCPAgent.LearningAgentTest do
  use ExUnit.Case
  
  # Mock learning agent for testing
  defmodule MockLearningAgent do
    defstruct [:supported_file_types]
    def new(types \\ [".md", ".txt"]), do: %__MODULE__{supported_file_types: types}
  end
  
  defimpl MCPAgent.Agent, for: MCPAgent.LearningAgentTest.MockLearningAgent do
    def init(agent, _config) do
      %{
        agent: agent,
        file_queue: [],
        processed_files: MapSet.new(),
        knowledge_stats: %{entities_created: 0, relations_created: 0, observations_added: 0}
      }
    end
    
    def process_input(agent, input, state, _tools) do
      case String.starts_with?(input, "learn from ") do
        true ->
          file_part = String.slice(input, 11..-1)
          files = String.split(file_part, ",") |> Enum.map(&String.trim/1)
          new_state = %{state | file_queue: files ++ state.file_queue}
          {:ok, "Added #{length(files)} files", new_state}
          
        false ->
          {:ok, "Learning agent ready", state}
      end
    end
    
    def decide_action(_agent, state, _tools) do
      if length(state.file_queue) > 0 do
        {:action, :process_file}
      else
        :no_action
      end
    end
    
    def execute_action(_agent, :process_file, state, _tool_executor) do
      [_file | remaining] = state.file_queue
      new_processed = MapSet.put(state.processed_files, "test_file")
      new_stats = %{state.knowledge_stats | entities_created: state.knowledge_stats.entities_created + 1}
      
      new_state = %{
        state | 
        file_queue: remaining,
        processed_files: new_processed,
        knowledge_stats: new_stats
      }
      
      {:ok, "Processed file", new_state}
    end
    
    def status(_agent, state) do
      %{
        type: "Mock Learning Agent",
        files_processed: MapSet.size(state.processed_files),
        files_in_queue: length(state.file_queue),
        knowledge_stats: state.knowledge_stats
      }
    end
  end
  
  test "learning agent processes files correctly" do
    agent = MockLearningAgent.new()
    
    {:ok, pid} = MCPAgent.AgentServer.start_link([
      agent_impl: agent,
      agent_config: %{}
    ])
    
    # Add files for learning
    MCPAgent.AgentServer.send_input(pid, "learn from file1.md, file2.txt")
    
    # Give it time to process
    :timer.sleep(100)
    
    state = MCPAgent.AgentServer.get_state(pid)
    assert state.agent_status.files_in_queue == 2
  end

  test "learning agent extracts knowledge correctly" do
    # Test knowledge extraction functions
    content = """
    # Test Document
    
    This is a test document with some content.
    
    ## Section 1
    
    Some information here.
    
    ```elixir
    def test_function do
      :ok
    end
    ```
    """
    
    {:ok, knowledge} = MCPAgent.Agents.LearningAgent.extract_markdown_knowledge(content, "test.md")
    
    assert length(knowledge.entities) > 0
    assert Enum.any?(knowledge.entities, &(&1.entityType == "concept"))
    assert Enum.any?(knowledge.entities, &(&1.entityType == "example"))
  end
end
```

## Usage Guide

### Setting Up the Learning Agent System

1. **Install MCP Knowledge Graph Server**:
   ```bash
   npm install -g mcp-knowledge-graph
   ```

2. **Install Filesystem MCP Server (optional)**:
   ```bash
   # Follow instructions from https://github.com/mark3labs/mcp-filesystem-server
   ```

3. **Start your application**:
   ```bash
   mix run --no-halt
   ```

### Using the Learning Agent

#### Basic Learning Commands

```elixir
# Add files to learning queue
MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "learn from README.md, lib/my_module.ex")

# Query learned knowledge  
MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "what do you know about GenServer?")

# Check learning progress
MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "status")

# Clear the learning queue
MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "clear queue")
```

#### Interactive Learning

```elixir
# Start an interactive learning session
MCPAgent.Examples.interactive_learning()
```

#### Querying Knowledge

```elixir
# Query specific topics
MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "what do you know about protocols?")
MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "what do you know about supervision trees?")
```

### Available Operations

```elixir
# Send input to learning agent
MCPAgent.AgentServer.send_input(MCPAgent.LearningAgent, "your input here")

# Get agent status and learning progress
MCPAgent.AgentServer.get_state(MCPAgent.LearningAgent)

# List available MCP tools (knowledge graph + filesystem)
MCPAgent.AgentServer.get_tools(MCPAgent.LearningAgent)

# Manually trigger learning action
MCPAgent.AgentServer.trigger_action(MCPAgent.LearningAgent)
```

## Key Features

This learning agent system provides:

- **Multi-format Learning**: Supports markdown, text, Elixir code, JSON, and YAML files
- **Knowledge Graph Storage**: Persistent knowledge storage using MCP knowledge graph server
- **Intelligent Extraction**: Different parsing strategies for different file types
- **Query Interface**: Natural language queries to access learned knowledge
- **Progress Tracking**: Statistics on learning progress and knowledge growth
- **Session Management**: Support for multiple learning sessions
- **Protocol-based Design**: Easily extensible with new agent types
- **MCP Integration**: Leverages external tools through Model Context Protocol
- **Real-time Processing**: Async file processing and knowledge building

The system embodies the key insight from the code-editing agent research: **simplicity wins**. The core loop is straightforward - process input, decide actions, execute tools, repeat - but the combination is powerful enough to build a comprehensive learning system.

This architecture gives you a solid foundation for building intelligent agents that can learn from your codebase and help you understand complex projects through natural language queries!