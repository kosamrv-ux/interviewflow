defmodule InterviewFlow.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      InterviewFlow.Repo,
      {DNSCluster, query: Application.get_env(:interview_flow, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: InterviewFlow.PubSub},
      {Finch, name: InterviewFlow.Finch},
      {Oban, Application.fetch_env!(:interview_flow, Oban)},
      InterviewFlowWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: InterviewFlow.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    InterviewFlowWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
