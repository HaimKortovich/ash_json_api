defmodule AshJsonApi.JsonSchemaPrimitiveTest do
  use ExUnit.Case, async: true
  alias AshJsonApi.JsonSchema.Primitive

  test "microsecond timestamp attributes have the same wire schema as their second-resolution variants" do
    for type <- [
          :utc_datetime_usec,
          Ash.Type.UtcDatetimeUsec,
          Ash.Type.UtcDatetime
        ] do
      assert {:ok, %{"type" => "string", "format" => "date-time"}} = Primitive.schema(type)
    end
  end

  test "decimals are numeric strings" do
    assert {:ok, %{"type" => "string", "format" => "decimal", "pattern" => pattern}} =
             Primitive.schema(:decimal)

    regex = Regex.compile!(pattern)

    for valid <- ["12", "-12.50", "+0.5", ".5", "1e3", "2.5E-4"] do
      assert Regex.match?(regex, valid), valid
      assert {:ok, _} = Ash.Type.cast_input(:decimal, valid)
    end

    for invalid <- ["", "Test", "1.2.3", "12a"], do: refute(Regex.match?(regex, invalid), invalid)
  end

  test "array length constraints become minItems/maxItems" do
    assert %{"type" => "array", "minItems" => 3, "maxItems" => 3} =
             AshJsonApi.JsonSchema.attribute_schema(%{
               type: {:array, :string},
               constraints: [min_length: 3, max_length: 3, items: []]
             })
  end

  test "string and number constraints are stated" do
    assert {:ok,
            %{"type" => "string", "minLength" => 2, "maxLength" => 9, "pattern" => "^[0-9]+$"}} =
             Primitive.schema(:string, min_length: 2, max_length: 9, match: ~r/^[0-9]+$/)

    assert {:ok, %{"pattern" => "^a$"}} =
             Primitive.schema(:string, match: {Spark.Regex, :cache, ["^a$", ""]})

    # Not expressible as an ECMAScript pattern: flags and \\A anchors.
    assert {:ok, schema} = Primitive.schema(:string, match: ~r/^a$/i)
    refute Map.has_key?(schema, "pattern")
    assert {:ok, schema} = Primitive.schema(:string, match: ~r/\Aa/)
    refute Map.has_key?(schema, "pattern")

    assert {:ok, %{"type" => "integer", "minimum" => 1, "maximum" => 5}} =
             Primitive.schema(:integer, min: 1, max: 5)

    assert {:ok, %{"exclusiveMinimum" => 0}} = Primitive.schema(:float, greater_than: 0)
  end
end
