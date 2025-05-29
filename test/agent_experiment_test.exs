defmodule AgentExperimentTest do
  use ExUnit.Case
  doctest AgentExperiment

  test "greets the world" do
    assert AgentExperiment.hello() == :world
  end
end
