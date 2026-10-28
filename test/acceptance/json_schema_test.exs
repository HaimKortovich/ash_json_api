# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Test.Acceptance.JsonSchemaTest do
  use ExUnit.Case, async: true

  defmodule Node do
    use Ash.Resource,
      data_layer: :embedded,
      extensions: [
        AshJsonApi.Resource
      ]

    json_api do
      type("node")
    end

    attributes do
      attribute(:name, :string, public?: true)
      attribute(:child, :struct, constraints: [instance_of: __MODULE__], public?: true)
    end
  end

  defmodule Author do
    use Ash.Resource,
      domain: Test.Acceptance.JsonSchemaTest.Blogs,
      data_layer: Ash.DataLayer.Ets,
      extensions: [
        AshJsonApi.Resource
      ]

    ets do
      private?(true)
    end

    json_api do
      type("author")

      routes do
        base("/authors")
        get(:read)
        index(:read)
        patch(:update)
      end
    end

    actions do
      default_accept(:*)
      defaults([:create, :read, :update, :destroy])
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:name, :string, public?: true)
    end

    relationships do
      has_many(:posts, Test.Acceptance.JsonSchemaTest.Post,
        destination_attribute: :author_id,
        public?: true
      )
    end
  end

  defmodule Post do
    use Ash.Resource,
      domain: Test.Acceptance.JsonSchemaTest.Blogs,
      data_layer: Ash.DataLayer.Ets,
      extensions: [
        AshJsonApi.Resource
      ]

    ets do
      private?(true)
    end

    json_api do
      type("post")

      routes do
        base("/posts")
        get(:read)
        index(:read)
        post(:create, relationship_arguments: [{:id, :author}])
      end
    end

    actions do
      default_accept(:*)
      defaults([:read, :update, :destroy])

      create :create do
        primary? true
        accept([:id, :name, :hidden])
        argument(:author, :uuid)

        change(manage_relationship(:author, type: :append_and_remove))
      end
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:hidden, :string, public?: true)

      attribute(:email, :string,
        public?: true,
        allow_nil?: true,
        constraints: [
          match: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
        ]
      )
    end

    relationships do
      belongs_to(:author, Test.Acceptance.JsonSchemaTest.Author, allow_nil?: false, public?: true)
    end
  end

  defmodule Tree do
    use Ash.Resource,
      domain: Test.Acceptance.JsonSchemaTest.Blogs,
      data_layer: Ash.DataLayer.Ets,
      extensions: [
        AshJsonApi.Resource
      ]

    ets do
      private?(true)
    end

    json_api do
      type("tree")

      routes do
        base("/trees")
        get(:read)
        index(:read)
      end
    end

    actions do
      default_accept(:*)
      defaults([:create, :read, :update, :destroy])
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:root, Node, public?: true)
    end
  end

  defmodule Blogs do
    use Ash.Domain,
      otp_app: :ash_json_api,
      extensions: [
        AshJsonApi.Domain
      ]

    json_api do
      log_errors?(false)
    end

    resources do
      resource(Post)
      resource(Author)
      resource(Tree)
    end
  end

  setup do
    Application.put_env(:ash_json_api, Blogs, json_api: [test_router: Router])

    json_api = AshJsonApi.JsonSchema.generate([Blogs])

    %{json_api: json_api}
  end

  describe "generate json api schema" do
    test "prepends slashes to hrefs", %{json_api: json_api} do
      assert Enum.all?(
               json_api["links"],
               fn %{"href" => href} ->
                 # Just one slash
                 String.starts_with?(href, "/") &&
                   !String.starts_with?(href, "//")
               end
             )
    end

    test "handles self-referential embedded resources without infinite loop" do
      # This should complete without timing out
      # If it loops infinitely, the test will timeout
      json_api = AshJsonApi.JsonSchema.generate([Blogs])

      # Basic assertion to ensure schema was generated
      assert is_map(json_api)
      assert Map.has_key?(json_api, "links")
    end

    test "handles self-referential embedded resources in OpenAPI schema without infinite loop" do
      # This should complete without timing out
      # If it loops infinitely, the test will timeout
      open_api_spec = AshJsonApi.OpenApi.spec(domain: [Blogs])

      # Basic assertion to ensure schema was generated
      assert %OpenApiSpex.OpenApi{} = open_api_spec
      schemas = open_api_spec.components.schemas
      assert is_map(schemas)

      # Verify that the embedded resource with JSON API type gets its own schema
      assert Map.has_key?(schemas, "node-type")
      node_schema = schemas["node-type"]
      assert node_schema.type == :object

      # Verify that tree resource uses $ref to reference the node schema
      tree_schema = schemas["tree"]
      assert tree_schema.type == :object
      tree_attributes = tree_schema.properties.attributes
      root_property = tree_attributes.properties["root"]

      # Should be nullable (because the attribute allows nil)
      assert root_property.nullable == true
      assert root_property.type == :object

      # The child property within the node schema should reference the node schema
      child_property = root_property.properties["child"]
      assert child_property["$ref"] == "#/components/schemas/node-type"
      assert child_property["nullable"] == true
    end

    test "handles recursive embedded inputs for create/update operations without infinite loop" do
      # This test ensures that embedded resources with self-references in input schemas
      # (for create/update operations) properly use $ref references and don't cause stack overflow
      import ExUnit.CaptureLog

      # Create a standalone test module for this specific test
      defmodule RecursiveInputTest do
        defmodule RecursiveComment do
          use Ash.Resource,
            data_layer: :embedded,
            extensions: [AshJsonApi.Resource]

          json_api do
            type("recursive-comment")
          end

          attributes do
            attribute(:content, :string, public?: true)
            attribute(:parent, :struct, constraints: [instance_of: __MODULE__], public?: true)

            attribute(:replies, {:array, :struct},
              constraints: [items: [instance_of: __MODULE__]],
              public?: true
            )
          end
        end

        defmodule ArticleWithComments do
          use Ash.Resource,
            domain: Test.Acceptance.JsonSchemaTest.RecursiveInputTest.BlogDomain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshJsonApi.Resource]

          ets do
            private?(true)
          end

          json_api do
            type("article-with-comments")

            routes do
              base("/articles")
              get(:read)
              post(:create)
              patch(:update)
            end
          end

          actions do
            default_accept(:*)
            defaults([:read, :create, :update])
          end

          attributes do
            uuid_primary_key(:id, writable?: true)
            attribute(:title, :string, public?: true)
            attribute(:main_comment, RecursiveComment, public?: true)
          end
        end

        defmodule BlogDomain do
          use Ash.Domain,
            otp_app: :ash_json_api,
            extensions: [AshJsonApi.Domain]

          json_api do
            log_errors?(false)
          end

          resources do
            resource(ArticleWithComments)
          end
        end
      end

      log =
        capture_log(fn ->
          # Generate spec outside capture_log first to check it
          spec = AshJsonApi.OpenApi.spec(domain: [RecursiveInputTest.BlogDomain])

          # Verify spec generation completes without stack overflow
          assert %OpenApiSpex.OpenApi{} = spec

          # Check that the create operation request body is properly generated
          create_path = spec.paths["/articles"]
          assert create_path != nil

          create_op = create_path.post
          assert create_op != nil

          # Verify the request body schema exists
          assert create_op.requestBody != nil

          # The key test is that we got here without stack overflow
          # Additional checks to verify the schemas are properly structured
          schemas = spec.components.schemas

          # Verify the main resource schema exists
          assert Map.has_key?(schemas, "article-with-comments")

          # Verify the embedded recursive-comment schema exists
          assert Map.has_key?(schemas, "recursive-comment-type")

          # Check patch operation as well
          patch_path = spec.paths["/articles/{id}"]
          assert patch_path != nil

          patch_op = patch_path.patch
          assert patch_op != nil
          assert patch_op.requestBody != nil

          # Verify that any referenced schemas exist in components
          # This ensures client generation tools won't fail with missing $ref errors
          schema_keys = Map.keys(schemas)

          # If there are any input schemas, they should be properly defined
          input_schemas = Enum.filter(schema_keys, &String.contains?(&1, "-input-"))

          Enum.each(input_schemas, fn schema_name ->
            schema = Map.get(schemas, schema_name)
            assert schema != nil, "Schema #{schema_name} should be defined"
            assert schema.type == :object, "Schema #{schema_name} should be an object type"
          end)
        end)

      # Additionally verify that warnings were logged for recursive input types
      # This proves the recursion detection is working
      if log != "" do
        assert log =~ "recursive" or log =~ "Recursive",
               "Expected some indication of recursive type handling in logs"
      end
    end
  end

  describe "union attribute schema" do
    defmodule TaggedValue do
      use Ash.TypedStruct

      typed_struct do
        field(:value, :string, allow_nil?: false)
      end
    end

    defmodule TaggedPayload do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          storage: :map_with_tag,
          types: [
            email: [type: TaggedValue, tag: :type, tag_value: "email"],
            phone: [type: TaggedValue, tag: :type, tag_value: "phone"]
          ]
        ]
    end

    defmodule UntaggedPayload do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            string: [type: :string],
            integer: [type: :integer],
            float: [type: :float]
          ]
        ]
    end

    defmodule FloatType do
      use Ash.Type.NewType, subtype_of: :float
    end

    test "discriminated union renders oneOf with tag enums" do
      schema = AshJsonApi.JsonSchema.attribute_schema(%{type: TaggedPayload, constraints: []})

      assert %{"oneOf" => [email_variant, phone_variant]} = schema
      assert schema["discriminator"]["propertyName"] == "type"

      assert get_in(email_variant, ["properties", "type", "enum"]) == ["email"]
      assert get_in(phone_variant, ["properties", "type", "enum"]) == ["phone"]

      assert email_variant["type"] == "object"
      assert "type" in email_variant["required"]
      assert "value" in email_variant["required"]
    end

    test "component-aware schema generation names and registers tagged variants" do
      {schema, schemas} =
        AshJsonApi.JsonSchema.attribute_schema(
          %{type: TaggedPayload, name: :contact, constraints: []},
          schemas: %{}
        )

      assert schema["oneOf"] == [
               %{"$ref" => "#/components/schemas/email"},
               %{"$ref" => "#/components/schemas/phone"}
             ]

      refute Map.has_key?(schema, "discriminator")
      assert schemas["email"]["properties"]["type"]["enum"] == ["email"]
      assert "type" in schemas["email"]["required"]
      assert schemas["phone"]["properties"]["type"]["enum"] == ["phone"]
      assert "type" in schemas["phone"]["required"]
    end

    test "untagged union renders anyOf" do
      schema = AshJsonApi.JsonSchema.attribute_schema(%{type: UntaggedPayload, constraints: []})

      assert Map.has_key?(schema, "anyOf")
      assert length(schema["anyOf"]) == 3
      assert %{"type" => "number", "format" => "float"} in schema["anyOf"]
      refute Map.has_key?(schema, "discriminator")
    end

    test "float aliases and NewTypes render as JSON Schema numbers" do
      assert AshJsonApi.JsonSchema.attribute_schema(%{type: :float}) == %{
               "type" => "number",
               "format" => "float"
             }

      assert AshJsonApi.JsonSchema.attribute_schema(%{type: FloatType}) == %{
               "type" => "number",
               "format" => "float"
             }
    end

    test "arrays of float aliases render numeric items" do
      assert AshJsonApi.JsonSchema.attribute_schema(%{type: {:array, :float}}) == %{
               "type" => "array",
               "items" => %{"type" => "number", "format" => "float"}
             }
    end

    test "legacy boolean and integer schemas continue accepting strings" do
      assert AshJsonApi.JsonSchema.attribute_schema(%{type: Ash.Type.Boolean}) == %{
               "type" => ["boolean", "string"],
               "match" => "^(true|false)$"
             }

      assert AshJsonApi.JsonSchema.attribute_schema(%{type: Ash.Type.Integer}) == %{
               "type" => ["integer", "string"],
               "match" => "^[1-9][0-9]*$"
             }
    end
  end

  describe "typed struct schema" do
    defmodule DefaultedStruct do
      use Ash.TypedStruct

      typed_struct do
        field(:name, :string, allow_nil?: false)
        field(:source, :atom, allow_nil?: false, default: :api)
        field(:count, :integer, allow_nil?: false, default: fn -> 0 end)
        field(:note, :string)
        field(:ratio, :float)
      end
    end

    test "fields with defaults are not required" do
      schema = AshJsonApi.JsonSchema.attribute_schema(%{type: DefaultedStruct, constraints: []})

      assert schema["required"] == ["name"]
      assert schema["type"] == "object"

      assert "source" in Map.keys(schema["properties"])
      assert "count" in Map.keys(schema["properties"])
      assert "note" in Map.keys(schema["properties"])
      assert schema["properties"]["ratio"] == %{"type" => "number", "format" => "float"}
      refute "note" in schema["required"]
    end

    test "structs without a declaring typed struct keep constraints-derived required fields" do
      schema =
        AshJsonApi.JsonSchema.attribute_schema(%{
          type: Ash.Type.Struct,
          constraints: [
            fields: [
              name: [type: :string, allow_nil?: false],
              extra: [type: :string, allow_nil?: false, default: "x"]
            ]
          ]
        })

      assert schema["required"] == ["name"]
    end

    test "plain struct without fields renders an open object" do
      schema =
        AshJsonApi.JsonSchema.attribute_schema(%{type: Ash.Type.Struct, constraints: []})

      assert schema == %{"type" => "object"}
    end
  end
end
