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
end
