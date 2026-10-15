# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(OpenApiSpex) do
  defmodule Test.Acceptance.OpenApiAttributeTest do
    use ExUnit.Case, async: true

    alias OpenApiSpex.Schema

    defmodule Address do
      use Ash.Resource,
        data_layer: :embedded,
        extensions: [AshJsonApi.Resource]

      json_api do
        type("address")

        open_api do
          attribute(:postal_code,
            transform: fn schema, context ->
              schema
              |> Map.put("format", "postal-code")
              |> Map.put("x-context-path", context.path)
            end
          )
        end
      end

      attributes do
        attribute(:postal_code, :string, public?: true)
      end
    end

    defmodule Circle do
      use Ash.Resource,
        data_layer: :embedded,
        extensions: [AshJsonApi.Resource]

      json_api do
        type("circle")

        open_api do
          attribute(:radius,
            transform: fn schema ->
              Map.put(schema, "x-ui", %{"input_type" => "number"})
            end
          )
        end
      end

      attributes do
        attribute(:radius, :integer, public?: true)
      end
    end

    defmodule Shape do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            circle: [type: Circle, tag: :type, tag_value: "circle"],
            label: [type: :string]
          ]
        ]
    end

    defmodule User do
      use Ash.Resource,
        data_layer: Ash.DataLayer.Ets,
        domain: Test.Acceptance.OpenApiAttributeTest.Api,
        extensions: [AshJsonApi.Resource]

      json_api do
        type("user")

        open_api do
          attribute(:email,
            transform: fn schema, context ->
              schema
              |> Map.put("format", "email")
              |> Map.put("x-ui", %{
                "autocomplete" => "email",
                "input_type" => "email",
                "direction" => to_string(context.direction)
              })
            end
          )

          attribute(:display_name,
            transform: fn schema ->
              Map.put(schema, "x-ui", %{"input_type" => "text"})
            end
          )
        end

        routes do
          base "/users"
          get :read
          post :create
          patch :update
        end
      end

      attributes do
        uuid_primary_key(:id)
        attribute(:email, :string, public?: true)
        attribute(:display_name, :string, public?: true)
        attribute(:address, Address, public?: true)
        attribute(:shape, Shape, public?: true)
      end

      actions do
        default_accept(:*)
        defaults([:read, :create, :update])
      end
    end

    defmodule Api do
      use Ash.Domain,
        extensions: [AshJsonApi.Domain]

      resources do
        resource User
      end
    end

    defp user_schema do
      schemas()["user"]
    end

    defp user_attributes do
      %Schema{properties: properties} = user_schema()
      properties.attributes.properties
    end

    defp schemas do
      AshJsonApi.OpenApi.schemas([Api], AshJsonApi.OpenApi.empty_acc())
    end

    test "applies one and two argument transforms to read schemas" do
      properties = user_attributes()
      email = properties["email"]
      display_name = properties["display_name"]

      assert email["x-ui"] == %{
               "autocomplete" => "email",
               "input_type" => "email",
               "direction" => "read"
             }

      assert email["format"] == "email"
      assert display_name["x-ui"] == %{"input_type" => "text"}
    end

    test "applies transforms to embedded attributes with a nested path" do
      properties = user_attributes()
      %Schema{properties: address_properties} = properties["address"]

      assert address_properties["postal_code"]["x-context-path"] == [
               "components",
               "schemas",
               "user",
               "properties",
               "attributes",
               "properties",
               "address",
               "properties",
               "postal_code"
             ]
    end

    test "applies transforms to union branch attributes" do
      schemas = schemas()
      properties = schemas["user"].properties.attributes.properties
      assert %{"oneOf" => [%{"$ref" => circle_ref} | _]} = properties["shape"]

      circle_schema_name = circle_ref |> String.split("/") |> List.last()
      %Schema{properties: circle_properties} = schemas[circle_schema_name]
      assert circle_properties["radius"]["x-ui"] == %{"input_type" => "number"}
    end

    test "applies transforms to write schemas automatically" do
      spec = AshJsonApi.OpenApi.spec(domains: [Api])

      %Schema{properties: body_properties} =
        spec.paths["/users"].post.requestBody.content["application/vnd.api+json"].schema

      data_properties = body_properties.data
      properties = data_properties.properties.attributes.properties

      assert properties["email"]["x-ui"]["direction"] == "write"
      assert properties["email"]["format"] == "email"
    end

    test "normalizes the generated document to OpenAPI 3.1.1" do
      document = AshJsonApi.OpenApi.spec(domains: [Api]) |> AshJsonApi.OpenApi.to_map()

      assert document["openapi"] == "3.1.1"
      assert document["jsonSchemaDialect"] == "https://spec.openapis.org/oas/3.1/dialect/base"

      email =
        document["components"]["schemas"]["user"]["properties"]["attributes"]["properties"][
          "email"
        ]

      assert email["format"] == "email"
      assert email["x-ui"]["autocomplete"] == "email"
      refute has_key_recursive?(document, "nullable")
      refute has_key_recursive?(document, "extensions")
    end

    test "unknown attributes fail during resource compilation" do
      assert_raise Spark.Error.DslError, ~r/unknown attribute :missing/, fn ->
        Code.compile_string("""
        defmodule Test.UnknownOpenApiAttribute do
          use Ash.Resource, domain: nil, extensions: [AshJsonApi.Resource]

          attributes do
            uuid_primary_key :id
          end

          json_api do
            type "unknown_open_api_attribute"

            open_api do
              attribute :missing, transform: fn schema -> schema end
            end
          end
        end
        """)
      end
    end

    test "invalid transform arity fails during resource compilation" do
      assert_raise Spark.Error.DslError, ~r/transform option/, fn ->
        Code.compile_string("""
        defmodule Test.InvalidOpenApiAttributeTransform do
          use Ash.Resource, domain: nil, extensions: [AshJsonApi.Resource]

          attributes do
            uuid_primary_key :id
            attribute :email, :string, public?: true
          end

          json_api do
            type "invalid_open_api_attribute_transform"

            open_api do
              attribute :email, transform: fn _schema, _context, _extra -> :invalid end
            end
          end
        end
        """)
      end
    end

    defp has_key_recursive?(map, key) when is_map(map) do
      Map.has_key?(map, key) or
        Enum.any?(map, fn {_key, value} -> has_key_recursive?(value, key) end)
    end

    defp has_key_recursive?(list, key) when is_list(list),
      do: Enum.any?(list, &has_key_recursive?(&1, key))

    defp has_key_recursive?(_, _key), do: false
  end
end
