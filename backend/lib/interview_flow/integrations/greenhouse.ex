defmodule InterviewFlow.Integrations.Greenhouse do
  @moduledoc """
  Greenhouse ATS integration.

  Greenhouse is a leading applicant tracking system used by enterprise customers.
  This integration provides:
  - Candidate import from Greenhouse applications
  - Job sync from Greenhouse job postings
  - Stage update pushback: when a candidate is moved in InterviewFlow, sync to Greenhouse
  - Scorecard export: send AI scores back to Greenhouse as scorecards

  ## Configuration

  Set per organization in org.settings["greenhouse"]:
    - api_key: Greenhouse Harvest API key (requires "Job Admin" or "Basic" API access)
    - on_behalf_of: Greenhouse user ID for API calls (required for some endpoints)

  ## Webhooks from Greenhouse

  Greenhouse sends webhooks when candidates apply or are updated. Register:
    POST /integrations/greenhouse/webhook
  as the webhook URL in Greenhouse > Configure > Dev Center > Web Hooks.

  The payload is verified via HMAC-SHA256 signature in the `Signature` header.
  """

  require Logger

  @base_url "https://harvest.greenhouse.io/v1"
  @harvest_key_header "Authorization"

  @doc """
  Imports all active applications from Greenhouse for the given job.
  """
  def import_applications(org, greenhouse_job_id) do
    with {:ok, config} <- get_config(org),
         {:ok, applications} <- fetch_applications(config, greenhouse_job_id) do
      results =
        Enum.map(applications, fn app ->
          import_single_application(org, app)
        end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      Logger.info("[Greenhouse] imported #{successes} applications, #{failures} failed for job #{greenhouse_job_id}")
      {:ok, %{imported: successes, failed: failures}}
    end
  end

  @doc """
  Syncs a candidate stage update back to Greenhouse.
  Called when a candidate's stage changes in InterviewFlow.
  """
  def push_stage_update(org, greenhouse_application_id, new_stage) do
    with {:ok, config} <- get_config(org) do
      stage_id = map_stage_to_greenhouse(new_stage)

      body = Jason.encode!(%{
        "id" => greenhouse_application_id,
        "current_stage" => %{"id" => stage_id}
      })

      case api_patch(config, "/applications/#{greenhouse_application_id}", body) do
        {:ok, _} ->
          Logger.info("[Greenhouse] stage updated for application #{greenhouse_application_id}")
          :ok

        {:error, reason} ->
          Logger.error("[Greenhouse] push_stage_update failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Exports an AI scorecard to Greenhouse for a completed interview.
  """
  def export_scorecard(org, greenhouse_application_id, scorecard_data) do
    with {:ok, config} <- get_config(org) do
      body = Jason.encode!(%{
        "interview" => %{
          "notes" => format_scorecard_notes(scorecard_data),
          "overall_recommendation" => map_score_to_recommendation(scorecard_data.composite_score),
          "attributes" => format_scorecard_attributes(scorecard_data)
        }
      })

      case api_post(config, "/applications/#{greenhouse_application_id}/scorecards", body) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Verifies a Greenhouse webhook payload signature.
  """
  def verify_webhook_signature(payload, signature, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
    Plug.Crypto.secure_compare(expected, signature)
  end

  ## Private helpers

  defp get_config(org) do
    case get_in(org.settings, ["greenhouse", "api_key"]) do
      nil -> {:error, "Greenhouse API key not configured for this organization"}
      key -> {:ok, %{api_key: key, on_behalf_of: get_in(org.settings, ["greenhouse", "on_behalf_of"])}}
    end
  end

  defp fetch_applications(config, job_id) do
    case api_get(config, "/applications?job_id=#{job_id}&per_page=500") do
      {:ok, body} -> {:ok, Jason.decode!(body)}
      error -> error
    end
  end

  defp import_single_application(org, app) do
    candidate_attrs = %{
      "name" => "#{app["candidate"]["first_name"]} #{app["candidate"]["last_name"]}",
      "email" => hd(app["candidate"]["email_addresses"] || [%{"value" => nil}])["value"],
      "org_id" => org.id,
      "external_id" => "greenhouse:#{app["candidate"]["id"]}",
      "external_application_id" => "greenhouse:#{app["id"]}"
    }

    InterviewFlow.Candidates.find_or_create_by_email(candidate_attrs)
  end

  defp api_get(config, path) do
    headers = auth_headers(config)

    case HTTPoison.get(@base_url <> path, headers) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: code, body: body}} -> {:error, "Greenhouse API #{code}: #{body}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp api_post(config, path, body) do
    headers = auth_headers(config) ++ [{"Content-Type", "application/json"}]

    case HTTPoison.post(@base_url <> path, body, headers) do
      {:ok, %{status_code: code}} when code in 200..299 -> {:ok, code}
      {:ok, %{status_code: code, body: b}} -> {:error, "Greenhouse API #{code}: #{b}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp api_patch(config, path, body) do
    headers = auth_headers(config) ++ [{"Content-Type", "application/json"}]

    case HTTPoison.patch(@base_url <> path, body, headers) do
      {:ok, %{status_code: code}} when code in 200..299 -> {:ok, code}
      {:ok, %{status_code: code, body: b}} -> {:error, "Greenhouse API #{code}: #{b}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp auth_headers(%{api_key: key, on_behalf_of: nil}) do
    encoded = Base.encode64("#{key}:")
    [{@harvest_key_header, "Basic #{encoded}"}]
  end

  defp auth_headers(%{api_key: key, on_behalf_of: obo}) do
    encoded = Base.encode64("#{key}:")
    [
      {@harvest_key_header, "Basic #{encoded}"},
      {"On-Behalf-Of", to_string(obo)}
    ]
  end

  defp map_stage_to_greenhouse(stage) do
    # Organization-specific stage IDs are configured in settings.
    # These are illustrative defaults.
    %{
      "applied" => 1,
      "screening" => 2,
      "interview" => 3,
      "offer" => 4,
      "hired" => 5,
      "rejected" => 6
    }[stage] || 2
  end

  defp map_score_to_recommendation(score) when score >= 80, do: "definitely_yes"
  defp map_score_to_recommendation(score) when score >= 60, do: "yes"
  defp map_score_to_recommendation(score) when score >= 40, do: "neutral"
  defp map_score_to_recommendation(score) when score >= 20, do: "no"
  defp map_score_to_recommendation(_), do: "definitely_no"

  defp format_scorecard_notes(scorecard) do
    """
    AI-generated scorecard from InterviewFlow

    Composite Score: #{scorecard.composite_score}/100

    Dimensions:
    #{format_dimensions(scorecard.dimensions)}

    Rubric Version: #{scorecard.rubric_version}
    """
  end

  defp format_dimensions(dimensions) do
    dimensions
    |> Enum.map(fn {k, v} -> "  - #{k}: #{v}" end)
    |> Enum.join("\n")
  end

  defp format_scorecard_attributes(scorecard) do
    scorecard.dimensions
    |> Enum.map(fn {name, score} ->
      %{
        "name" => humanize(name),
        "rating" => score_to_rating(score)
      }
    end)
  end

  defp score_to_rating(score) when score >= 80, do: "strong_yes"
  defp score_to_rating(score) when score >= 60, do: "yes"
  defp score_to_rating(score) when score >= 40, do: "neutral"
  defp score_to_rating(_), do: "no"

  defp humanize(key), do: key |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
