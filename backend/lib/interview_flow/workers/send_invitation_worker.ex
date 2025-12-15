defmodule InterviewFlow.Workers.SendInvitationWorker do
  @moduledoc """
  Oban worker responsible for delivering invitation emails after an admin
  invites a new team member to their company workspace.

  Uses Tesla to call a transactional email API (e.g., SendGrid or Postmark)
  configured via the MAILER_API_KEY and MAILER_FROM environment variables.

  Retry strategy: 3 attempts with exponential back-off built into Oban.
  The job is considered permanently failed after the third attempt and is
  marked :discarded — an alert is raised via Telemetry for monitoring.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3

  require Logger

  alias InterviewFlow.Accounts
  alias InterviewFlow.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invitation_id" => invitation_id}}) do
    invitation =
      case Repo.get(InterviewFlow.Accounts.Invitation, invitation_id) do
        nil -> {:error, :not_found}
        inv -> {:ok, inv}
      end

    with {:ok, inv} <- invitation,
         true <- InterviewFlow.Accounts.Invitation.valid?(inv),
         {:ok, inviter} <- get_inviter(inv.invited_by_id),
         {:ok, company} <- get_company(inv.company_id) do
      send_email(inv, inviter, company)
    else
      {:error, :not_found} ->
        # Invitation was deleted — no-op, don't retry
        Logger.warning("SendInvitationWorker: invitation #{invitation_id} not found, skipping")
        :ok

      false ->
        # Already accepted or expired — no-op
        Logger.info("SendInvitationWorker: invitation #{invitation_id} is no longer valid, skipping")
        :ok

      {:error, reason} ->
        Logger.error("SendInvitationWorker: failed for invitation #{invitation_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_inviter(user_id) do
    case Repo.get(InterviewFlow.Accounts.User, user_id) do
      nil -> {:error, :inviter_not_found}
      user -> {:ok, user}
    end
  end

  defp get_company(company_id) do
    case Repo.get(InterviewFlow.Accounts.Company, company_id) do
      nil -> {:error, :company_not_found}
      company -> {:ok, company}
    end
  end

  defp send_email(invitation, inviter, company) do
    invite_url = build_invite_url(invitation.token)

    payload = %{
      from: %{email: mailer_from(), name: "InterviewFlow"},
      to: [%{email: invitation.email, name: invitation.full_name || invitation.email}],
      subject: "#{inviter.full_name} invited you to #{company.name} on InterviewFlow",
      text_body: text_body(invitation, inviter, company, invite_url),
      html_body: html_body(invitation, inviter, company, invite_url)
    }

    case mailer_client().post("/email", payload) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        :telemetry.execute([:interview_flow, :invitation_email, :sent], %{}, %{invitation_id: invitation.id})
        :ok

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Email API returned #{status}: #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Email transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_invite_url(token) do
    base = Application.get_env(:interview_flow, :app_base_url, "http://localhost:3000")
    "#{base}/accept-invitation?token=#{token}"
  end

  defp text_body(invitation, inviter, company, url) do
    name = invitation.full_name || "there"

    """
    Hi #{name},

    #{inviter.full_name} has invited you to join #{company.name} on InterviewFlow
    as a #{invitation.role}.

    Accept your invitation here:
    #{url}

    This link expires in 7 days. If you didn't expect this invitation, you can
    safely ignore this email.

    — The InterviewFlow Team
    """
  end

  defp html_body(invitation, inviter, company, url) do
    name = invitation.full_name || "there"

    """
    <p>Hi #{name},</p>
    <p>#{inviter.full_name} has invited you to join <strong>#{company.name}</strong>
    on InterviewFlow as a <strong>#{invitation.role}</strong>.</p>
    <p>
      <a href="#{url}" style="display:inline-block;padding:12px 24px;background:#4f46e5;color:#fff;border-radius:8px;text-decoration:none;font-weight:600;">
        Accept Invitation
      </a>
    </p>
    <p style="color:#6b7280;font-size:13px;">
      This link expires in 7 days. If you didn't expect this invitation,
      you can safely ignore this email.
    </p>
    """
  end

  defp mailer_client do
    middleware = [
      {Tesla.Middleware.BaseUrl, Application.get_env(:interview_flow, :mailer_base_url, "https://api.sendgrid.com/v3")},
      {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{System.get_env("MAILER_API_KEY", "")}"}]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Retry, delay: 500, max_retries: 2},
    ]

    Tesla.client(middleware, Tesla.Adapter.Hackney)
  end

  defp mailer_from do
    System.get_env("MAILER_FROM", "noreply@interviewflow.io")
  end
end
