defmodule AshJsonApi.Webhook.Management do
  @moduledoc """
  Configuration helpers for exposing webhook-management routes.

  Webhook management is intentionally opt-in and resource-owned. The host
  application remains responsible for authorization, tenant scoping, and the
  resource actions themselves. The generated routes use the same Ash request
  pipeline as every other JSON:API route, so normal Ash policies, custom
  roles, actors, and tenants are preserved.

  Enable the defaults with `webhook_management? true`, or enable them while
  overriding actions with `webhook_management: [create: :issue]`.

  If the importing application provides `ash_rbac`, it can add its normal
  `AshRbac` resource extension and define roles for these actions. This
  library does not load or require `AshRbac` itself; ordinary Ash policies
  remain the fallback when that dependency is absent.
  """

  @default_actions [
    index: :read,
    get: :read,
    create: :create,
    update: :update,
    destroy: :destroy
  ]

  @spec actions(keyword) :: keyword
  def actions(opts) when is_list(opts), do: Keyword.merge(@default_actions, opts)

  @spec enabled?(boolean | keyword) :: boolean
  def enabled?(value), do: value == true or is_list(value)
end
