defmodule InterviewFlow.Interviews.TranscriptStore do
  @moduledoc """
  Stores and retrieves interview transcripts from Google Cloud Storage.

  Transcripts are large binary payloads (JSON from speech-to-text) that
  are stored in GCS rather than Postgres to avoid bloating the main database.

  Object naming convention:
    `transcripts/{session_id}/{timestamp}.json`

  Metadata (session_id, object_key, size) is recorded on the VideoSession
  record so we can locate the transcript without listing GCS.
  """

  require Logger

  alias InterviewFlow.Interviews.VideoSession
  alias InterviewFlow.Repo

  @bucket Application.compile_env(:interview_flow, :gcs_bucket, "interviewflow-transcripts-dev")

  @doc """
  Uploads a raw transcript JSON payload to GCS and records the object key
  on the VideoSession record.

  Returns `{:ok, object_key}` or `{:error, reason}`.
  """
  @spec store(VideoSession.t(), binary()) :: {:ok, String.t()} | {:error, any()}
  def store(%VideoSession{id: session_id} = session, transcript_json)
      when is_binary(transcript_json) do
    ts = DateTime.utc_now() |> DateTime.to_unix()
    object_key = "transcripts/#{session_id}/#{ts}.json"

    Logger.info("transcript_store: uploading transcript",
      session_id: session_id,
      size_bytes: byte_size(transcript_json)
    )

    with :ok <- gcs_upload(object_key, transcript_json),
         {:ok, _} <- record_transcript_key(session, object_key) do
      {:ok, object_key}
    else
      {:error, reason} = err ->
        Logger.error("transcript_store: upload failed",
          session_id: session_id,
          reason: inspect(reason)
        )
        err
    end
  end

  @doc """
  Downloads and returns the transcript JSON for a video session.

  Returns `{:ok, json_binary}` or `{:error, :not_found | reason}`.
  """
  @spec fetch(VideoSession.t()) :: {:ok, binary()} | {:error, any()}
  def fetch(%VideoSession{transcript_object_key: nil}),
    do: {:error, :not_found}

  def fetch(%VideoSession{transcript_object_key: object_key}) do
    gcs_download(object_key)
  end

  @doc "Returns the GCS public URL for a transcript (requires public read ACL in dev)."
  @spec public_url(String.t()) :: String.t()
  def public_url(object_key) do
    "https://storage.googleapis.com/#{@bucket}/#{object_key}"
  end

  # ── GCS helpers ──────────────────────────────────────────────────────────

  defp gcs_upload(object_key, body) do
    client = gcs_client()

    case Tesla.put(client, "/#{object_key}", body,
           headers: [{"content-type", "application/json"}]
         ) do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      {:ok, %{status: status, body: body}} -> {:error, %{status: status, body: body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp gcs_download(object_key) do
    client = gcs_client()

    case Tesla.get(client, "/#{object_key}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, %{status: status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp gcs_client do
    base = "https://storage.googleapis.com/#{@bucket}"

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{gcs_token()}"}]},
      {Tesla.Middleware.Timeout, timeout: 15_000}
    ])
  end

  defp gcs_token do
    # In Cloud Run: use metadata server token
    # In local dev: use GOOGLE_APPLICATION_CREDENTIALS file
    Application.get_env(:interview_flow, :gcs_access_token, "dev_token")
  end

  defp record_transcript_key(session, object_key) do
    session
    |> Ecto.Changeset.change(%{transcript_object_key: object_key})
    |> Repo.update()
  end
end
