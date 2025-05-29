defmodule MCPAgent.AgentTest do
  use ExUnit.Case, async: true

  describe "protocol definition" do
    test "protocol exists and is properly defined" do
      assert Code.ensure_loaded?(MCPAgent.Agent)
      
      # Verify protocol functions exist
      functions = MCPAgent.Agent.__protocol__(:functions)
      expected_functions = [
        {:init, 2},
        {:process_input, 4},
        {:decide_action, 3},
        {:execute_action, 4},
        {:status, 2}
      ]
      
      for func <- expected_functions do
        assert func in functions, "Expected function #{inspect(func)} not found in protocol"
      end
    end

    test "protocol module has correct attributes" do
      assert MCPAgent.Agent.__protocol__(:module) == MCPAgent.Agent
      assert is_list(MCPAgent.Agent.__protocol__(:functions))
    end
  end

  describe "protocol structure validation" do
    test "all protocol functions have correct arities" do
      functions = MCPAgent.Agent.__protocol__(:functions)
      
      # Validate specific function signatures
      assert {:init, 2} in functions
      assert {:process_input, 4} in functions  
      assert {:decide_action, 3} in functions
      assert {:execute_action, 4} in functions
      assert {:status, 2} in functions
    end

    test "protocol supports implementation discovery" do
      # Test that the protocol framework supports extension
      assert is_atom(MCPAgent.Agent)
      assert function_exported?(MCPAgent.Agent, :__protocol__, 1)
      
      # Protocol should support implementation discovery
      assert function_exported?(MCPAgent.Agent, :impl_for, 1)
      assert function_exported?(MCPAgent.Agent, :impl_for!, 1)
    end
  end

  describe "protocol documentation" do
    test "protocol has comprehensive documentation" do
      docs = Code.fetch_docs(MCPAgent.Agent)
      assert {:docs_v1, _, :elixir, _, module_doc, _, _} = docs
      
      # Check that module has documentation
      refute module_doc == %{"en" => ""}
      refute module_doc == :none
    end

    test "all protocol functions are documented" do
      {:docs_v1, _, :elixir, _, _, _, function_docs} = Code.fetch_docs(MCPAgent.Agent)
      
      documented_functions = for {{:function, name, arity}, _, _, _, _} <- function_docs do
        {name, arity}
      end
      
      expected_functions = [
        {:init, 2},
        {:process_input, 4},
        {:decide_action, 3},
        {:execute_action, 4},
        {:status, 2}
      ]
      
      for func <- expected_functions do
        assert func in documented_functions, "Function #{inspect(func)} is not documented"
      end
    end
  end

  describe "protocol contract validation" do
    test "init/2 function signature is correct" do
      assert {:init, 2} in MCPAgent.Agent.__protocol__(:functions)
    end

    test "process_input/4 function signature is correct" do
      assert {:process_input, 4} in MCPAgent.Agent.__protocol__(:functions)
    end

    test "decide_action/3 function signature is correct" do
      assert {:decide_action, 3} in MCPAgent.Agent.__protocol__(:functions)
    end

    test "execute_action/4 function signature is correct" do
      assert {:execute_action, 4} in MCPAgent.Agent.__protocol__(:functions)
    end

    test "status/2 function signature is correct" do
      assert {:status, 2} in MCPAgent.Agent.__protocol__(:functions)
    end
  end

  describe "protocol behavior specs" do
    test "protocol defines callback specs" do
      behaviours = MCPAgent.Agent.behaviour_info(:callbacks)
      
      expected_callbacks = [
        {:init, 2},
        {:process_input, 4},
        {:decide_action, 3},
        {:execute_action, 4},
        {:status, 2}
      ]
      
      for callback <- expected_callbacks do
        assert callback in behaviours, "Expected callback #{inspect(callback)} not found"
      end
    end
  end

  describe "protocol extensibility" do
    test "protocol supports fallback implementations" do
      implementations = MCPAgent.Agent.__protocol__(:impls)
      
      # Should return either a list or a consolidated tuple
      case implementations do
        {:consolidated, impls} when is_list(impls) -> 
          assert true
        impls when is_list(impls) -> 
          assert true
        _ -> 
          flunk("Expected implementations to be a list or {:consolidated, list}, got: #{inspect(implementations)}")
      end
    end

    test "protocol consolidation state is trackable" do
      # The protocol should be consolidated unless in debug mode
      consolidated = MCPAgent.Agent.__protocol__(:consolidated?)
      assert is_boolean(consolidated)
    end
  end
end 