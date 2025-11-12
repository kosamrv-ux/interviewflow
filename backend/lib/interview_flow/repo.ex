defmodule InterviewFlow.Repo do
  use Ecto.Repo,
    otp_app: :interview_flow,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Wraps a function in a transaction and returns `{:ok, result}` or `{:error, reason}`.
  """
  def transact(fun) when is_function(fun, 0) do
    transaction(fn ->
      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> rollback(reason)
        other -> other
      end
    end)
  end
end
