# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshJsonApi.Resource.Transformers.AddWebhookManagementRoutes do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshJsonApi.Resource.Route
  alias AshJsonApi.Webhook.Management
  alias Spark.Dsl.Transformer

  @routes [
    {:index, :index, "/", :get},
    {:get, :get, "/:id", :get},
    {:create, :post, "/", :post},
    {:update, :patch, "/:id", :patch},
    {:destroy, :delete, "/:id", :delete}
  ]

  def transform(dsl) do
    enabled? = Transformer.get_option(dsl, [:json_api], :webhook_management?, false)
    config = Transformer.get_option(dsl, [:json_api], :webhook_management, [])

    if Management.enabled?(enabled?) or config != [] do
      add_routes(dsl, config)
    else
      {:ok, dsl}
    end
  end

  def before?(AshJsonApi.Resource.Transformers.PrependRoutePrefix), do: true
  def before?(_), do: false

  defp add_routes(dsl, config) do
    actions = Management.actions(config)
    existing_routes = Transformer.get_entities(dsl, [:json_api, :routes])
    route_definitions = AshJsonApi.Resource.routes()[:entities]

    Enum.reduce_while(@routes, {:ok, dsl}, fn {key, type, path, method}, {:ok, dsl} ->
      case Keyword.get(actions, key) do
        nil ->
          {:cont, {:ok, dsl}}

        action ->
          if Enum.any?(existing_routes, &same_route?(&1, method, path)) do
            {:cont, {:ok, dsl}}
          else
            with {:ok, route} <- build_route(route_definitions, type, action, path) do
              {:cont,
               {:ok,
                Transformer.add_entity(dsl, [:json_api, :routes], route,
                  type: :append
                )}}
            else
              {:error, message} ->
                raise Spark.Error.DslError,
                  module: Transformer.get_persisted(dsl, :module),
                  path: [:json_api, :webhook_management],
                  message: message
            end
          end
      end
    end)
  end

  defp same_route?(route, method, path), do: route.method == method and route.route == path

  defp build_route(route_definitions, type, action, path) do
    definition = Enum.find(route_definitions, &(&1.name == type))

    case definition do
      nil ->
        {:error, "could not find JSON:API route definition #{inspect(type)}"}

      definition ->
        with {:ok, route} <-
               Spark.Dsl.Entity.build(definition, [{:action, action}], [], nil, %{}) do
          {:ok, %Route{route | route: path}}
        end
    end
  end
end
