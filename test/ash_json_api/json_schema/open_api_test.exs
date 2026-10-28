# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshJsonApi.OpenApiTest do
  use ExUnit.Case, async: true

  alias AshJsonApi.OpenApi
  alias __MODULE__.{Blogs, Author, Post}

  defmodule Circle do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute(:radius, :integer, public?: true)
    end

    actions do
      defaults([:read, create: :*, update: :*])
    end
  end

  defmodule Shape do
    use Ash.Type.NewType,
      subtype_of: :union,
      constraints: [types: [circle: [type: Circle], label: [type: :string]]]
  end

  defmodule Bio do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute(:nationality, :string, public?: true)
      attribute(:age, :integer, public?: true)
      attribute(:private_note, :string)
      attribute(:shape, Shape, public?: true)
    end

    actions do
      defaults([:read, create: :*, update: :*])
    end
  end

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
      attribute(:bio, Bio, public?: true)
      attribute(:shape, Shape, public?: true)

      attribute(:direct_shape, :union,
        public?: true,
        constraints: [
          types: [
            circle: [type: Circle, tag: :type, tag_value: "circle"],
            label: [type: :string, tag: :type, tag_value: "label"]
          ]
        ]
      )
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

  describe "filter_type/2" do
    test "with embedded resource attribute registers a path filter schema" do
      attribute = Ash.Resource.Info.attribute(Post, :bio)

      {result, _acc} = OpenApi.filter_type(attribute, Post, OpenApi.empty_acc())

      assert [{"post-filter-bio", %OpenApiSpex.Schema{anyOf: [_ | _]}}] = result
    end

    test "with a union attribute registers a discriminator and variant filter schema" do
      attribute = Ash.Resource.Info.attribute(Post, :shape)

      {result, _acc} = OpenApi.filter_type(attribute, Post, OpenApi.empty_acc())

      assert [{"post-filter-shape", %OpenApiSpex.Schema{anyOf: paths}}] = result

      assert Enum.any?(paths, fn
               %OpenApiSpex.Schema{
                 required: [:at_path],
                 properties: %{
                   at_path: %OpenApiSpex.Schema{enum: [["type"]]},
                   eq: %OpenApiSpex.Schema{enum: ["circle", "label"]}
                 }
               } ->
                 true

               _ ->
                 false
             end)

      assert Enum.any?(paths, fn
               %OpenApiSpex.Schema{
                 properties: %{
                   at_path: %OpenApiSpex.Schema{enum: [["value", "radius"]]},
                   eq: %OpenApiSpex.Schema{type: :integer}
                 }
               } ->
                 true

               _ ->
                 false
             end)
    end

    test "supports direct Ash.Type.Union attributes as well as NewTypes" do
      attribute = Ash.Resource.Info.attribute(Post, :direct_shape)

      {result, _acc} = OpenApi.filter_type(attribute, Post, OpenApi.empty_acc())

      assert [{"post-filter-direct_shape", %OpenApiSpex.Schema{anyOf: paths}}] = result
      assert Enum.any?(paths, &(&1.properties.at_path.enum == [["type"]]))
    end

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
    test "with an embedded resource builds partial filters for public fields and tagged unions" do
      attribute = Ash.Resource.Info.attribute(Post, :bio)

      {result, _acc} = OpenApi.raw_filter_type(attribute, Post, OpenApi.empty_acc())

      assert %OpenApiSpex.Schema{anyOf: paths} = result

      assert Enum.any?(paths, fn
               %OpenApiSpex.Schema{
                 properties: %{at_path: %OpenApiSpex.Schema{enum: [["nationality"]]}}
               } = schema ->
                 schema.properties.eq == %OpenApiSpex.Schema{type: :string}

               _ ->
                 false
             end)

      assert Enum.any?(paths, fn
               %OpenApiSpex.Schema{properties: %{at_path: %OpenApiSpex.Schema{enum: [["age"]]}}} =
                   schema ->
                 schema.properties.greater_than_or_equal == %OpenApiSpex.Schema{type: :integer}

               _ ->
                 false
             end)

      assert Enum.any?(paths, fn
               %OpenApiSpex.Schema{
                 properties: %{
                   at_path: %OpenApiSpex.Schema{enum: [["shape", "type"]]},
                   eq: %OpenApiSpex.Schema{enum: ["circle", "label"]}
                 }
               } ->
                 true

               _ ->
                 false
             end)

      assert Enum.any?(paths, fn
               %OpenApiSpex.Schema{
                 properties: %{
                   at_path: %OpenApiSpex.Schema{enum: [["shape", "value", "radius"]]},
                   eq: %OpenApiSpex.Schema{type: :integer}
                 }
               } ->
                 true

               _ ->
                 false
             end)

      refute Enum.any?(paths, fn
               %OpenApiSpex.Schema{
                 properties: %{at_path: %OpenApiSpex.Schema{enum: [["private_note"]]}}
               } ->
                 true

               _ ->
                 false
             end)
    end

    test "Ash can parse an explicit at_path into a union variant" do
      query =
        Ash.Query.filter_input(Post, %{
          "bio" => %{"at_path" => ["shape", "radius"], "eq" => 10}
        })

      assert query.valid?
    end

    test "Ash currently accepts an explicit path to a private embedded attribute" do
      query =
        Ash.Query.filter_input(Post, %{
          "bio" => %{"at_path" => ["private_note"], "eq" => "secret"}
        })

      assert query.valid?
    end

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
end
