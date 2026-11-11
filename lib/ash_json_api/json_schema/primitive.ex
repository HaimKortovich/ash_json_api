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
    :utc_datetime_usec,
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
      Ash.Type.String ->
        {:ok, string_schema(constraints)}

      Ash.Type.CiString ->
        {:ok, string_schema(constraints)}

      Ash.Type.Boolean ->
        {:ok, %{"type" => "boolean"}}

      Ash.Type.Integer ->
        {:ok, number_schema(%{"type" => "integer"}, constraints)}

      Ash.Type.Float ->
        {:ok, number_schema(%{"type" => "number", "format" => "float"}, constraints)}

      Ash.Type.Decimal ->
        {:ok, decimal_schema()}

      Ash.Type.Date ->
        {:ok, %{"type" => "string", "format" => "date"}}

      Ash.Type.UtcDatetime ->
        {:ok, %{"type" => "string", "format" => "date-time"}}

      Ash.Type.UtcDatetimeUsec ->
        {:ok, %{"type" => "string", "format" => "date-time"}}

      Ash.Type.NaiveDatetime ->
        {:ok, %{"type" => "string", "format" => "date-time"}}

      Ash.Type.Time ->
        {:ok, %{"type" => "string", "format" => "time"}}

      Ash.Type.UUID ->
        {:ok, %{"type" => "string", "format" => "uuid"}}

      Ash.Type.UUIDv7 ->
        {:ok, %{"type" => "string", "format" => "uuid"}}

      Ash.Type.Atom ->
        {:ok, atom_schema(constraints)}

      Ash.Type.DurationName ->
        {:ok, duration_name_schema()}

      _ ->
        :error
    end
  end

  # Input is checked against these constraints, so the schema states them.
  defp string_schema(constraints) do
    %{"type" => "string"}
    |> put_constraint("minLength", constraints[:min_length])
    |> put_constraint("maxLength", constraints[:max_length])
    |> put_constraint("pattern", pattern(constraints[:match]))
  end

  defp number_schema(schema, constraints) do
    schema
    |> put_constraint("minimum", constraints[:min])
    |> put_constraint("maximum", constraints[:max])
    |> put_constraint("exclusiveMinimum", constraints[:greater_than])
    |> put_constraint("exclusiveMaximum", constraints[:less_than])
  end

  defp put_constraint(schema, _key, nil), do: schema
  defp put_constraint(schema, key, value), do: Map.put(schema, key, value)

  # JSON Schema patterns are ECMAScript regexes. Only publish a pattern when the
  # Elixir regex means the same there: no flags, anchors or inline groups that
  # ECMAScript lacks.
  defp pattern(%Regex{} = regex), do: pattern({Regex.source(regex), Regex.opts(regex)})
  defp pattern({Spark.Regex, :cache, [source, opts]}), do: pattern({source, opts})

  defp pattern({source, opts}) when is_binary(source) and opts in ["", []] do
    if String.contains?(source, ["\\A", "\\z", "\\Z", "(?"]), do: nil, else: source
  end

  defp pattern(_regex), do: nil

  # Decimals travel as strings; the pattern accepts what Decimal parsing accepts
  # (sign, fraction, exponent) so clients know the string must be a number.
  defp decimal_schema do
    %{
      "type" => "string",
      "format" => "decimal",
      "pattern" => "^[-+]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][-+]?[0-9]+)?$"
    }
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
