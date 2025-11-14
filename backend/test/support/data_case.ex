defmodule InterviewFlow.DataCase do
  @moduledoc """
  Test case template for tests that interact with the database.
  Sets up an Ecto sandbox, imports Ecto.Changeset helpers, and
  provides the `errors_on/1` helper for asserting changeset errors.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias InterviewFlow.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import InterviewFlow.DataCase
      import InterviewFlow.Factory
    end
  end

  setup tags do
    InterviewFlow.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(InterviewFlow.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Returns the errors in a changeset as a flat map of field => [message].

  ## Example

      assert %{email: ["can't be blank"]} = errors_on(changeset)
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
