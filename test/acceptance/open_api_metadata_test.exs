defmodule Test.Acceptance.OpenApiMetadataTest do
  use ExUnit.Case, async: true

  defmodule Item do
    use Ash.Resource,
      domain: Test.Acceptance.OpenApiMetadataTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJsonApi.Resource]

    ets do
      private?(true)
    end

    json_api do
      type "metadata_item"

      routes do
        base "/metadata-items"
        get :read
        post :create
        index :read

        index :offset do
          route "/offset"
          metadata fn _, _, _ -> %{"trace_id" => "trace-1"} end

          metadata_schema %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["trace_id"],
            "properties" => %{"trace_id" => %{"type" => "string", "minLength" => 1}}
          }
        end

        index :keyset do
          route "/keyset"
        end

        index :read do
          route "/custom"
          metadata fn _, _, _ -> %{"dynamic" => true} end
        end
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, public?: true)
      attribute(:captured_at, :utc_datetime_usec, public?: true)
    end

    actions do
      defaults([:read, create: [:name, :captured_at]])

      read :offset do
        pagination(offset?: true, countable: true, required?: false)
      end

      read :keyset do
        pagination(keyset?: true, countable: true, required?: false)
      end
    end
  end

  defmodule Domain do
    use Ash.Domain, otp_app: :ash_json_api, extensions: [AshJsonApi.Domain]

    json_api do
      log_errors? false
    end

    resources do
      resource Item
    end
  end

  defmodule Router do
    use AshJsonApi.Router, domain: Domain
  end

  setup do
    Application.put_env(:ash_json_api, Domain, json_api: [test_router: Router])
    item = Item |> Ash.Changeset.for_create(:create, %{name: "example"}) |> Ash.create!()
    document = AshJsonApi.OpenApi.spec(domains: [Domain]) |> AshJsonApi.OpenApi.to_map()
    %{item: item, document: document}
  end

  test "actual non-paginated and single responses have closed typed metadata", ctx do
    list = response("/metadata-items")
    one = response("/metadata-items/#{ctx.item.id}")
    assert_valid!(ctx.document, "/metadata-items", list)
    assert_valid!(ctx.document, "/metadata-items/{id}", one)
    assert list["meta"] == %{}
    assert one["data"]["meta"] == %{}

    for invalid <- [
          put_in(one, ["meta", "unknown"], 1),
          put_in(one, ["data", "meta", "unknown"], 1),
          put_in(one, ["data", "meta", "keyset"], 1),
          put_in(one, ["jsonapi", "version"], "2.0"),
          put_in(one, ["links", "self"], 123),
          put_in(one, ["data", "type"], "wrong-resource")
        ] do
      assert {:error, _} = validate(ctx.document, "/metadata-items/{id}", invalid)
    end
  end

  test "actual offset/keyset page metadata and nullable pagination links validate", ctx do
    for path <- ["/metadata-items/offset", "/metadata-items/keyset"] do
      body = response(path <> "?page[limit]=1&page[count]=true")
      assert body["meta"]["page"]["limit"] == 1
      assert body["meta"]["page"]["total"] == 1
      assert body["links"]["next"] == nil
      assert_valid!(ctx.document, path, body)

      assert {:error, _} =
               validate(ctx.document, path, put_in(body, ["meta", "page", "total"], "one"))

      assert {:error, _} =
               validate(ctx.document, path, put_in(body, ["meta", "page", "unknown"], 1))
    end

    body = response("/metadata-items/offset?page[limit]=1")
    assert body["meta"]["trace_id"] == "trace-1"
    assert_valid!(ctx.document, "/metadata-items/offset", body)

    assert {:error, _} =
             validate(
               ctx.document,
               "/metadata-items/offset",
               put_in(body, ["meta", "trace_id"], 1)
             )

    assert {:error, _} =
             validate(
               ctx.document,
               "/metadata-items/offset",
               update_in(body, ["meta"], &Map.delete(&1, "trace_id"))
             )

    assert {:error, _} =
             validate(
               ctx.document,
               "/metadata-items/offset",
               put_in(body, ["meta", "trace_id"], "")
             )
  end

  test "undeclared callback output remains honestly open", ctx do
    schema = schema(ctx.document, "/metadata-items/custom")
    assert schema["properties"]["meta"]["additionalProperties"] == true
    assert_valid!(ctx.document, "/metadata-items/custom", response("/metadata-items/custom"))
  end

  test "deepObject query parameters explicitly declare exploded encoding", ctx do
    parameters = ctx.document["paths"]["/metadata-items/offset"]["get"]["parameters"]
    deep = Enum.filter(parameters, &(&1["style"] == "deepObject"))
    assert Enum.any?(deep, &(&1["name"] == "page"))
    assert Enum.any?(deep, &(&1["name"] == "fields"))
    assert Enum.all?(deep, &(&1["explode"] == true))
  end

  test "known write timestamps and resource tags are typed; no includes means no included items",
       ctx do
    input =
      get_in(ctx.document, [
        "paths",
        "/metadata-items",
        "post",
        "requestBody",
        "content",
        "application/vnd.api+json",
        "schema"
      ])

    tag = input["properties"]["data"]["properties"]["type"]
    assert tag["type"] == "string"
    assert tag["enum"] == ["metadata_item"]

    timestamp =
      input["properties"]["data"]["properties"]["attributes"]["properties"]["captured_at"]

    assert timestamp["type"] == ["string", "null"]
    assert timestamp["format"] == "date-time"
    validator = JsonXema.new(timestamp)
    assert :ok = JsonXema.validate(validator, "2026-11-09T12:00:00.123456Z")
    assert :ok = JsonXema.validate(validator, nil)
    assert {:error, _} = JsonXema.validate(validator, 123)
    assert schema(ctx.document, "/metadata-items")["properties"]["included"]["items"] == false

    assert {:error, _} =
             validate(
               ctx.document,
               "/metadata-items",
               Map.put(response("/metadata-items"), "included", [%{}])
             )
  end

  test "default error response describes the actual JSON:API envelope", ctx do
    conn = AshJsonApi.Test.get(Domain, "/metadata-items/#{Ash.UUID.generate()}", status: 404)

    schema =
      ctx.document["components"]["schemas"]["error_document"]
      |> Map.put("definitions", ctx.document["components"]["schemas"])
      |> rebase()

    validator = JsonXema.new(schema)
    assert :ok = JsonXema.validate(validator, conn.resp_body)
    assert {:error, _} = JsonXema.validate(validator, conn.resp_body["errors"])

    assert {:error, _} =
             JsonXema.validate(validator, Map.put(conn.resp_body, "errors", "not-an-array"))

    assert ctx.document["components"]["responses"]["errors"]["content"][
             "application/vnd.api+json"
           ]["schema"] ==
             %{"$ref" => "#/components/schemas/error_document"}
  end

  defp response(path) do
    conn = AshJsonApi.Test.get(Domain, path, status: 200)
    conn.resp_body
  end

  defp schema(document, path),
    do:
      get_in(document, [
        "paths",
        path,
        "get",
        "responses",
        "200",
        "content",
        "application/vnd.api+json",
        "schema"
      ])

  defp assert_valid!(document, path, body), do: assert(:ok = validate(document, path, body))

  defp validate(document, path, body) do
    schema =
      schema(document, path)
      |> Map.put("definitions", document["components"]["schemas"])
      |> rebase()

    JsonXema.validate(JsonXema.new(schema), body)
  end

  defp rebase(value) when is_map(value),
    do:
      Map.new(value, fn
        {"$ref", "#/components/schemas/" <> name} -> {"$ref", "#/definitions/" <> name}
        {key, value} -> {key, rebase(value)}
      end)

  defp rebase(value) when is_list(value), do: Enum.map(value, &rebase/1)
  defp rebase(value), do: value
end
