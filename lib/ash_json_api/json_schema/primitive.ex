# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshJsonApi.JsonSchema.Primitive do
  @moduledoc false

  @type_aliases [
    :string,
    :ci_string,
    :boolean,
    :integer,
    :float,
    :decimal,
    :date,
    :utc_datetime,
    :naive_datetime,
    :time,
    :uuid,
    :uuid_v7,
    :uuidv7,
    :atom,
    :duration_name
  ]

  @doc false
  def schema(type, constraints \\ []) do
    type = if type in @type_aliases, do: Ash.Type.get_type(type), else: type
    constraints = constraints || []

    case type do
      Ash.Type.String -> {:ok, %{"type" => "string"}}
      Ash.Type.CiString -> {:ok, %{"type" => "string"}}
      Ash.Type.Boolean -> {:ok, %{"type" => "boolean"}}
      Ash.Type.Integer -> {:ok, %{"type" => "integer"}}
      Ash.Type.Float -> {:ok, %{"type" => "number", "format" => "float"}}
      Ash.Type.Decimal -> {:ok, %{"type" => "string"}}
      Ash.Type.Date -> {:ok, %{"type" => "string", "format" => "date"}}
      Ash.Type.UtcDatetime -> {:ok, %{"type" => "string", "format" => "date-time"}}
      Ash.Type.NaiveDatetime -> {:ok, %{"type" => "string", "format" => "date-time"}}
      Ash.Type.Time -> {:ok, %{"type" => "string", "format" => "time"}}
      Ash.Type.UUID -> {:ok, %{"type" => "string", "format" => "uuid"}}
      Ash.Type.UUIDv7 -> {:ok, %{"type" => "string", "format" => "uuid"}}
      Ash.Type.Atom -> {:ok, atom_schema(constraints)}
      Ash.Type.DurationName -> {:ok, duration_name_schema()}
      _ -> :error
    end
  end

  defp atom_schema(constraints) do
    case constraints[:one_of] do
      nil -> %{"type" => "string"}
      values -> %{"type" => "string", "enum" => Enum.map(values, &to_string/1)}
    end
  end

  defp duration_name_schema do
    %{
      "type" => "string",
      "enum" => Enum.map(Ash.Type.DurationName.values(), &to_string/1)
    }
  end
end
