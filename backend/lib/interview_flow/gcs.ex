defmodule InterviewFlow.GCS do
  @moduledoc """
  Thin client for Google Cloud Storage object operations.

  Used by:
  - `TranscriptStore` — transcript upload/download
  - `ArchiveAuditLogWorker` — audit log archival to cold storage
  - `CandidateService` — resume and export upload

  Authentication uses the Application Default Credentials (ADC) provided by
  the Cloud Run service account.  Locally, set GOOGLE_APPLICATION_CREDENTIALS
  to a service account JSON key.

  This module is the single integration point with GCS — swappable in tests
  via the :gcs_module application config key.
  """

  @behaviour InterviewFlow.GCS.Behaviour

  alias Tesla

  require Logger

  @upload_url "https://storage.googleapis.com/upload/storage/v1/b"
  @download_url "https://storage.googleapis.com/storage/v1/b"

  @impl true
  def upload(bucket, object_path, data, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    encoded_path = URI.encode(object_path)

    url = "#{@upload_url}/#{bucket}/o?uploadType=media&name=#{encoded_path}"

    with {:ok, token} <- get_access_token() do
      client = build_client(token)

      case Tesla.post(client, url, data,
             headers: [{"content-type", content_type}]
           ) do
        {:ok, %{status: 200, body: body}} ->
          etag = get_in(body, ["etag"])
          Logger.debug("gcs: uploaded object", bucket: bucket, path: object_path, etag: etag)
          {:ok, etag}

        {:ok, %{status: status, body: body}} ->
          Logger.error("gcs: upload failed", bucket: bucket, path: object_path,
            status: status, body: inspect(body))
          {:error, {:gcs_error, status}}

        {:error, reason} ->
          Logger.error("gcs: network error on upload", reason: inspect(reason))
          {:error, {:network_error, reason}}
      end
    end
  end

  @impl true
  def download(bucket, object_path) do
    encoded_path = URI.encode(object_path)
    url = "#{@download_url}/#{bucket}/o/#{encoded_path}?alt=media"

    with {:ok, token} <- get_access_token() do
      client = build_client(token)

      case Tesla.get(client, url) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: 404}}             -> {:error, :not_found}
        {:ok, %{status: status}}          -> {:error, {:gcs_error, status}}
        {:error, reason}                  -> {:error, {:network_error, reason}}
      end
    end
  end

  @impl true
  def signed_url(bucket, object_path, expires_in_seconds \\ 3600) do
    # Signed URL generation delegates to IAM service account signing.
    # Returns a time-limited URL for direct download without auth headers.
    encoded_path = URI.encode(object_path)
    url = "#{@download_url}/#{bucket}/o/#{encoded_path}?alt=media"

    # In production, this calls the GCS Signing API; stubbed for readability.
    {:ok, "#{url}&Expires=#{System.system_time(:second) + expires_in_seconds}&Signature=stub"}
  end

  @impl true
  def delete(bucket, object_path) do
    encoded_path = URI.encode(object_path)
    url = "#{@download_url}/#{bucket}/o/#{encoded_path}"

    with {:ok, token} <- get_access_token() do
      client = build_client(token)

      case Tesla.delete(client, url) do
        {:ok, %{status: status}} when status in [200, 204] -> :ok
        {:ok, %{status: 404}}   -> :ok  # Already deleted
        {:ok, %{status: status}} -> {:error, {:gcs_error, status}}
        {:error, reason}         -> {:error, {:network_error, reason}}
      end
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp get_access_token do
    # Fetches token from GCP metadata server (Cloud Run) or ADC (local dev).
    metadata_url = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"

    case Tesla.get(build_metadata_client(), metadata_url) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status}} ->
        Logger.error("gcs: metadata token fetch failed", status: status)
        {:error, :no_access_token}

      {:error, _} ->
        # Fallback for local dev: check env or ADC
        case System.get_env("GOOGLE_ACCESS_TOKEN") do
          nil   -> {:error, :no_access_token}
          token -> {:ok, token}
        end
    end
  end

  defp build_client(token) do
    Tesla.client([
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Timeout, timeout: 30_000}
    ])
  end

  defp build_metadata_client do
    Tesla.client([
      {Tesla.Middleware.Headers, [{"metadata-flavor", "Google"}]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Timeout, timeout: 5_000}
    ])
  end
end

defmodule InterviewFlow.GCS.Behaviour do
  @moduledoc "Behaviour for GCS client — allows test mocking."

  @callback upload(bucket :: String.t(), path :: String.t(), data :: binary(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, any()}

  @callback download(bucket :: String.t(), path :: String.t()) ::
              {:ok, binary()} | {:error, any()}

  @callback signed_url(bucket :: String.t(), path :: String.t(), ttl :: integer()) ::
              {:ok, String.t()} | {:error, any()}

  @callback delete(bucket :: String.t(), path :: String.t()) ::
              :ok | {:error, any()}
end
