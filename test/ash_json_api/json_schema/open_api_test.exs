# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshJsonApi.OpenApiTest do
  use ExUnit.Case, async: true

  alias AshJsonApi.OpenApi
  alias __MODULE__.{Blogs, Author, Post}

  defmodule Author do
    use Ash.Resource,
      domain: Blogs,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJsonApi.Resource]

    json_api do
      type("author")
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:name, :string, public?: true)
    end

    relationships do
      has_many(:posts, Post, public?: true)
    end

    actions do
      default_accept(:*)
      defaults([:read, :update, :destroy])

      create :create do
        primary? true
        accept([:id, :name])
      end
    end

    aggregates do
      count(:posts_count, :posts, description: "Count of posts")
    end
  end

  defmodule Post do
    use Ash.Resource,
      domain: Blogs,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJsonApi.Resource]

    json_api do
      type("post")
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:view_count, :integer, public?: true, description: "View count of the post")
    end

    relationships do
      belongs_to(:author, Author, public?: true, attribute_public?: false)
    end

    actions do
      default_accept(:*)
      defaults([:read, :update, :destroy])

      create :create do
        primary? true
        accept([:id, :view_count])
      end
    end

    calculations do
      calculate(:calc, :string, expr("calc"), description: "A calculation")
    end
  end

  defmodule Blogs do
    use Ash.Domain

    resources do
      resource Author
      resource Post
    end
  end

  defmodule SharedWebhookPayload do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute(:event_id, :string, allow_nil?: false)
    end
  end

  defmodule FirstProviderWebhook do
    use Ash.Resource,
      domain: DuplicateWebhooks,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJsonApi.Resource]

    json_api do
      type("first_provider_webhook")

      routes do
        route(:post, "/webhooks/forms/:org_id/provider-one/application", :receive,
          webhook?: true
        )
      end
    end

    actions do
      action(:receive, :map) do
        argument(:payload, :struct,
          allow_nil?: false,
          constraints: [instance_of: SharedWebhookPayload]
        )

        run(fn _input, _context -> {:ok, %{}} end)
      end
    end
  end

  defmodule SecondProviderWebhook do
    use Ash.Resource,
      domain: DuplicateWebhooks,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJsonApi.Resource]

    json_api do
      type("second_provider_webhook")

      routes do
        route(:post, "/webhooks/forms/:org_id/provider-two/application", :receive,
          webhook?: true
        )
      end
    end

    actions do
      action(:receive, :map) do
        argument(:payload, :struct,
          allow_nil?: false,
          constraints: [instance_of: SharedWebhookPayload]
        )

        run(fn _input, _context -> {:ok, %{}} end)
      end
    end
  end

  defmodule DuplicateWebhooks do
    use Ash.Domain, extensions: [AshJsonApi.Domain]

    resources do
      resource(FirstProviderWebhook)
      resource(SecondProviderWebhook)
    end
  end

  describe "filter_type/2" do
    test "with attribute" do
      resource = Post
      attribute = Ash.Resource.Info.attribute(Post, :view_count)

      {result, _acc} = OpenApi.filter_type(attribute, resource, OpenApi.empty_acc())

      assert result == [
               {"post-filter-view_count",
                %OpenApiSpex.Schema{
                  type: :object,
                  description: "View count of the post",
                  properties: %{
                    in: %OpenApiSpex.Schema{
                      type: :array,
                      items: %OpenApiSpex.Schema{type: :integer}
                    },
                    eq: %OpenApiSpex.Schema{type: :integer},
                    is_nil: %OpenApiSpex.Schema{type: :boolean},
                    not_eq: %OpenApiSpex.Schema{type: :integer},
                    less_than: %OpenApiSpex.Schema{type: :integer},
                    greater_than: %OpenApiSpex.Schema{type: :integer},
                    less_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                    greater_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                    is_distinct_from: %OpenApiSpex.Schema{type: :integer},
                    is_not_distinct_from: %OpenApiSpex.Schema{type: :integer}
                  },
                  additionalProperties: false
                }}
             ]
    end

    test "with aggregate" do
      resource = Author
      aggregate = Ash.Resource.Info.aggregate(Author, :posts_count)

      {result, _acc} = OpenApi.filter_type(aggregate, resource, OpenApi.empty_acc())

      assert result == [
               {
                 "author-filter-posts_count",
                 %OpenApiSpex.Schema{
                   type: :object,
                   properties: %{
                     in: %OpenApiSpex.Schema{
                       type: :array,
                       items: %OpenApiSpex.Schema{type: :integer}
                     },
                     eq: %OpenApiSpex.Schema{type: :integer},
                     is_nil: %OpenApiSpex.Schema{type: :boolean},
                     not_eq: %OpenApiSpex.Schema{type: :integer},
                     less_than: %OpenApiSpex.Schema{type: :integer},
                     greater_than: %OpenApiSpex.Schema{type: :integer},
                     less_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                     greater_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                     is_distinct_from: %OpenApiSpex.Schema{type: :integer},
                     is_not_distinct_from: %OpenApiSpex.Schema{type: :integer}
                   },
                   additionalProperties: false,
                   description: "Count of posts"
                 }
               }
             ]
    end

    test "with calculation" do
      resource = Post
      calculation = Ash.Resource.Info.calculation(Post, :calc)

      {result, _acc} = OpenApi.filter_type(calculation, resource, OpenApi.empty_acc())

      assert result == [
               {"post-filter-calc",
                %OpenApiSpex.Schema{
                  type: :object,
                  description: "A calculation",
                  properties: %{
                    in: %OpenApiSpex.Schema{
                      type: :array,
                      items: %OpenApiSpex.Schema{type: :string}
                    },
                    eq: %OpenApiSpex.Schema{type: :string},
                    is_nil: %OpenApiSpex.Schema{type: :boolean},
                    not_eq: %OpenApiSpex.Schema{type: :string},
                    less_than: %OpenApiSpex.Schema{type: :string},
                    greater_than: %OpenApiSpex.Schema{type: :string},
                    less_than_or_equal: %OpenApiSpex.Schema{type: :string},
                    greater_than_or_equal: %OpenApiSpex.Schema{type: :string},
                    contains: %OpenApiSpex.Schema{type: :string},
                    string_ends_with: %OpenApiSpex.Schema{type: :string},
                    string_starts_with: %OpenApiSpex.Schema{type: :string},
                    is_distinct_from: %OpenApiSpex.Schema{type: :string},
                    is_not_distinct_from: %OpenApiSpex.Schema{type: :string}
                  },
                  required: [],
                  additionalProperties: false
                }}
             ]
    end
  end

  describe "raw_filter_type/2" do
    test "with attribute" do
      resource = Post
      attribute = Ash.Resource.Info.attribute(Post, :view_count)

      {result, _acc} = OpenApi.raw_filter_type(attribute, resource, OpenApi.empty_acc())

      assert result == %OpenApiSpex.Schema{
               type: :object,
               description: "View count of the post",
               properties: %{
                 in: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :integer}},
                 eq: %OpenApiSpex.Schema{type: :integer},
                 is_nil: %OpenApiSpex.Schema{type: :boolean},
                 not_eq: %OpenApiSpex.Schema{type: :integer},
                 less_than: %OpenApiSpex.Schema{type: :integer},
                 greater_than: %OpenApiSpex.Schema{type: :integer},
                 less_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                 greater_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                 is_distinct_from: %OpenApiSpex.Schema{type: :integer},
                 is_not_distinct_from: %OpenApiSpex.Schema{type: :integer}
               },
               additionalProperties: false
             }
    end

    test "with aggregate" do
      resource = Author
      aggregate = Ash.Resource.Info.aggregate(Author, :posts_count)

      {result, _acc} = OpenApi.raw_filter_type(aggregate, resource, OpenApi.empty_acc())

      assert result == %OpenApiSpex.Schema{
               type: :object,
               properties: %{
                 in: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :integer}},
                 eq: %OpenApiSpex.Schema{type: :integer},
                 is_nil: %OpenApiSpex.Schema{type: :boolean},
                 greater_than: %OpenApiSpex.Schema{type: :integer},
                 not_eq: %OpenApiSpex.Schema{type: :integer},
                 less_than: %OpenApiSpex.Schema{type: :integer},
                 less_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                 greater_than_or_equal: %OpenApiSpex.Schema{type: :integer},
                 is_distinct_from: %OpenApiSpex.Schema{type: :integer},
                 is_not_distinct_from: %OpenApiSpex.Schema{type: :integer}
               },
               additionalProperties: false,
               description: "Count of posts"
             }
    end

    test "with calculation" do
      resource = Post
      calculation = Ash.Resource.Info.calculation(Post, :calc)

      {result, _acc} = OpenApi.raw_filter_type(calculation, resource, OpenApi.empty_acc())

      assert result == %OpenApiSpex.Schema{
               type: :object,
               description: "A calculation",
               properties: %{
                 in: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}},
                 eq: %OpenApiSpex.Schema{type: :string},
                 is_nil: %OpenApiSpex.Schema{type: :boolean},
                 not_eq: %OpenApiSpex.Schema{type: :string},
                 less_than: %OpenApiSpex.Schema{type: :string},
                 greater_than: %OpenApiSpex.Schema{type: :string},
                 less_than_or_equal: %OpenApiSpex.Schema{type: :string},
                 greater_than_or_equal: %OpenApiSpex.Schema{type: :string},
                 contains: %OpenApiSpex.Schema{type: :string},
                 string_ends_with: %OpenApiSpex.Schema{type: :string},
                 string_starts_with: %OpenApiSpex.Schema{type: :string},
                 is_distinct_from: %OpenApiSpex.Schema{type: :string},
                 is_not_distinct_from: %OpenApiSpex.Schema{type: :string}
               },
               required: [],
               additionalProperties: false
             }
    end
  end

  describe "webhooks/1 and spec_json/2" do
    test "uses route identity when generated webhook payload names collide" do
      spec = OpenApi.spec_json(domain: [DuplicateWebhooks])

      assert Map.has_key?(spec["webhooks"], "providerOneApplication")
      assert Map.has_key?(spec["webhooks"], "providerTwoApplication")
      refute Map.has_key?(spec["webhooks"], "sharedWebhookPayload")
    end

    test "renders OpenAPI 3.1 webhooks at the document root" do
      definition =
        OpenApi.webhook(:lead_created,
          operation_id: "leadCreatedWebhook",
          summary: "Lead created",
          payload_schema: %OpenApiSpex.Schema{
            type: :object,
            properties: %{id: %OpenApiSpex.Schema{type: :string}},
            required: [:id]
          },
          security: [%{"webhookSignature" => []}]
        )

      assert %AshJsonApi.OpenApi.Webhook{} = definition

      assert %OpenApiSpex.PathItem{post: %OpenApiSpex.Operation{}} =
               AshJsonApi.OpenApi.Webhook.path_item(definition)

      assert %OpenApiSpex.RequestBody{
               content: %{"application/json" => %OpenApiSpex.MediaType{}}
             } = definition.operation.requestBody

      assert %OpenApiSpex.Response{} = definition.operation.responses["200"]

      document = OpenApi.spec_json(webhooks: [definition])

      assert document["openapi"] == "3.1.0"

      assert document["webhooks"]["lead_created"]["post"]["operationId"] ==
               "leadCreatedWebhook"

      assert document["webhooks"]["lead_created"]["post"]["requestBody"]["content"][
               "application/json"
             ]["schema"]["required"] == ["id"]
    end

    test "rejects untyped payload schemas" do
      assert_raise ArgumentError, ~r/payload_schema/, fn ->
        OpenApi.webhook(:lead_created, payload_schema: %{"type" => "object"})
      end
    end
  end
end
