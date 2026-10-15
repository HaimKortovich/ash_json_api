# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshJsonApi.Resource.Transformers.VerifyOpenApiAttributes do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  def transform(dsl) do
    attributes = Transformer.get_entities(dsl, [:attributes])

    dsl
    |> Transformer.get_entities([:json_api, :open_api])
    |> Enum.each(fn %{name: name, transform: transform} ->
      unless Enum.any?(attributes, &(&1.name == name)) do
        raise Spark.Error.DslError,
          module: __MODULE__,
          path: [:json_api, :open_api, :attribute, name],
          message: "OpenAPI customization references unknown attribute #{inspect(name)}"
      end

      unless is_function(transform, 1) or is_function(transform, 2) do
        raise Spark.Error.DslError,
          module: __MODULE__,
          path: [:json_api, :open_api, :attribute, name, :transform],
          message: "OpenAPI attribute transform must be a one- or two-argument function"
      end
    end)

    {:ok, dsl}
  end

  def after?(AshJsonApi.Resource.Transformers.RequirePrimaryKey), do: true
  def after?(_), do: false
end
