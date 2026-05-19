defmodule InterviewFlow.Candidates.ResumeParser do
  @moduledoc """
  Resume text extraction with robust UTF-8 encoding handling.

  Bug discovered in production (May 2026):
  Resumes exported from Windows applications often use Windows-1252 encoding
  (a superset of Latin-1) rather than UTF-8. When we extracted text from these
  PDFs and passed it to the AI scoring service, the Python service raised
  `UnicodeDecodeError`, causing scoring jobs to fail silently.

  The text was stored in Postgres as a TEXT column, which requires valid UTF-8.
  Inserting invalid UTF-8 sequences caused Ecto to raise `Postgrex.Error`.

  Fix:
  1. Detect encoding using `uchardet` (wrapped via Port/System.cmd)
  2. Transcode to UTF-8 using `iconv` if not already UTF-8/ASCII
  3. Strip null bytes and control characters that survive transcoding
  4. Replace any remaining invalid UTF-8 sequences with the Unicode replacement char

  This is applied at resume upload time (before GCS storage of text) and
  again at scoring time as a safety net.
  """

  require Logger

  @replacement_char "�"

  @doc """
  Sanitizes extracted resume text to valid UTF-8.
  Returns the cleaned string.
  """
  def sanitize_text(nil), do: nil
  def sanitize_text(""), do: ""

  def sanitize_text(text) when is_binary(text) do
    text
    |> maybe_transcode()
    |> strip_null_bytes()
    |> strip_control_chars()
    |> ensure_utf8()
  end

  @doc """
  Extracts text from a PDF binary, sanitizing encoding.
  Delegates to the Python AI service's text extraction endpoint for accuracy.
  """
  def extract_from_pdf(pdf_binary) do
    with {:ok, raw_text} <- call_python_extractor(pdf_binary) do
      {:ok, sanitize_text(raw_text)}
    end
  end

  ## Private

  defp maybe_transcode(text) do
    if String.valid?(text) do
      text
    else
      # Try to detect and transcode from common encodings
      case detect_encoding(text) do
        {:ok, "UTF-8"} ->
          # Already UTF-8 but invalid — handle in ensure_utf8
          text

        {:ok, encoding} ->
          Logger.info("[ResumeParser] transcoding from #{encoding} to UTF-8")
          transcode(text, encoding)

        :error ->
          Logger.warning("[ResumeParser] could not detect encoding, will replace invalid sequences")
          text
      end
    end
  end

  defp detect_encoding(binary) do
    # Use uchardet via System.cmd for encoding detection
    tmp = System.tmp_dir!() |> Path.join("resume_#{:erlang.unique_integer([:positive])}.bin")

    try do
      File.write!(tmp, binary)

      case System.cmd("uchardet", [tmp], stderr_to_stdout: true) do
        {encoding, 0} ->
          enc = String.trim(encoding)
          if enc in ["unknown", ""], do: :error, else: {:ok, enc}

        _ ->
          :error
      end
    after
      File.rm(tmp)
    end
  rescue
    _ -> :error
  end

  defp transcode(binary, from_encoding) do
    case System.cmd("iconv", ["-f", from_encoding, "-t", "UTF-8//TRANSLIT//IGNORE"],
           input: binary,
           stderr_to_stdout: true
         ) do
      {transcoded, 0} -> transcoded
      _ -> binary
    end
  rescue
    _ -> binary
  end

  defp strip_null_bytes(text), do: String.replace(text, <<0>>, "")

  defp strip_control_chars(text) do
    # Strip ASCII control chars (0x00-0x1F) except tab, newline, carriage return
    String.replace(text, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  defp ensure_utf8(text) do
    if String.valid?(text) do
      text
    else
      # Replace invalid byte sequences with the replacement character
      text
      |> :unicode.characters_to_binary(:latin1, :utf8)
      |> case do
        {:error, valid, _rest} -> valid <> @replacement_char
        {:incomplete, valid, _rest} -> valid
        result when is_binary(result) -> result
      end
    end
  end

  defp call_python_extractor(pdf_binary) do
    ai_service_url = Application.get_env(:interview_flow, :ai_service_url, "http://localhost:8001")
    url = "#{ai_service_url}/extract-text"
    headers = [{"Content-Type", "application/pdf"}]

    case HTTPoison.post(url, pdf_binary, headers, recv_timeout: 30_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"text" => text}} -> {:ok, text}
          _ -> {:error, :invalid_response}
        end

      {:ok, %{status_code: code, body: body}} ->
        Logger.error("[ResumeParser] AI service returned #{code}: #{body}")
        {:error, "extraction failed (#{code})"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
