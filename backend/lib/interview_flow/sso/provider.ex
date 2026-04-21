defmodule InterviewFlow.SSO.Provider do
  @moduledoc """
  Behaviour for SSO provider integrations.

  Supported providers:
  - Okta (SAML 2.0 + OIDC)
  - Google Workspace (OIDC)
  - Azure AD (OIDC)
  - Generic SAML 2.0

  Each provider implements this behaviour. The SSOController delegates
  to the appropriate provider based on org.sso_provider.
  """

  @type assertion :: %{
    email: String.t(),
    name: String.t() | nil,
    groups: [String.t()],
    attributes: map()
  }

  @callback authorize_url(config :: map()) :: {:ok, String.t()} | {:error, term()}
  @callback handle_callback(config :: map(), params :: map()) :: {:ok, assertion()} | {:error, term()}
  @callback refresh_token(config :: map(), refresh_token :: String.t()) :: {:ok, map()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour InterviewFlow.SSO.Provider

      def child_spec(_), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}, type: :worker}
    end
  end
end
