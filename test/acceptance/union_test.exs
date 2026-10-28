# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Test.Acceptance.UnionTest do
  use ExUnit.Case, async: true

  defmodule HeartRate do
    use Ash.Resource,
      domain: nil,
      data_layer: :embedded

    attributes do
      attribute(:bpm, :integer, public?: true, allow_nil?: false)
      attribute(:reading, :integer, public?: true)
      attribute(:private_note, :string)
    end

    actions do
      defaults([:read, :destroy, create: :*, update: :*])
    end
  end

  defmodule BloodPressure do
    use Ash.Resource,
      domain: nil,
      data_layer: :embedded

    attributes do
      attribute(:systolic, :integer, public?: true, allow_nil?: false)
      attribute(:diastolic, :integer, public?: true, allow_nil?: false)
      attribute(:reading, :string, public?: true)
    end

    actions do
      defaults([:read, :destroy, create: :*, update: :*])
    end
  end

  defmodule MeasurementValue do
    use Ash.Type.NewType,
      subtype_of: :union,
      constraints: [
        types: [
          heart_rate: [
            type: HeartRate,
            tag: :type,
            tag_value: "heart_rate"
          ],
          blood_pressure: [
            type: BloodPressure,
            tag: :type,
            tag_value: "blood_pressure"
          ],
          note: [
            type: :string
          ]
        ]
      ]
  end

  defmodule TaggedMeasurementValue do
    use Ash.Type.NewType,
      subtype_of: :union,
      constraints: [
        storage: :map_with_tag,
        types: [
          pulse: [type: HeartRate, tag: :type, tag_value: "heart_rate"],
          blood_pressure: [type: BloodPressure, tag: :type, tag_value: "blood_pressure"]
        ]
      ]
  end

  defmodule Measurement do
    use Ash.Resource,
      domain: Test.Acceptance.UnionTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJsonApi.Resource]

    ets do
      private?(true)
    end

    json_api do
      type "measurement"

      routes do
        base "/measurements"
        get :read
        index :read
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:value, MeasurementValue, public?: true, allow_nil?: false)
      attribute(:values, {:array, MeasurementValue}, public?: true, default: [])
      attribute(:tagged_value, TaggedMeasurementValue, public?: true)

      attribute(:direct_value, :union,
        public?: true,
        constraints: [
          types: [
            heart_rate: [type: HeartRate, tag: :type, tag_value: "heart_rate"],
            blood_pressure: [type: BloodPressure, tag: :type, tag_value: "blood_pressure"]
          ]
        ]
      )
    end

    actions do
      default_accept([:value, :values, :tagged_value, :direct_value])
      defaults([:read, :destroy, create: :*, update: :*])
    end
  end

  defmodule Domain do
    use Ash.Domain,
      otp_app: :ash_json_api,
      extensions: [AshJsonApi.Domain]

    json_api do
      authorize? false
      log_errors? false
    end

    resources do
      resource Measurement
    end
  end

  defmodule Router do
    use AshJsonApi.Router, domain: Domain
  end

  import AshJsonApi.Test

  setup do
    Application.put_env(:ash_json_api, Domain, json_api: [test_router: Router])
    :ok
  end

  test "renders an embedded resource inside a union without needing Jason.Encoder" do
    m =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "heart_rate", bpm: 72}
      })
      |> Ash.create!()

    response = Domain |> get("/measurements/#{m.id}", status: 200)
    attrs = response.resp_body["data"]["attributes"]

    assert attrs["value"] == %{"bpm" => 72, "reading" => nil}
  end

  test "renders a primitive value inside a union" do
    m =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: "feeling fine"
      })
      |> Ash.create!()

    response = Domain |> get("/measurements/#{m.id}", status: 200)
    attrs = response.resp_body["data"]["attributes"]

    assert attrs["value"] == "feeling fine"
  end

  test "renders an array of unions" do
    m =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "heart_rate", bpm: 60},
        values: [
          %{type: "heart_rate", bpm: 80},
          %{type: "blood_pressure", systolic: 120, diastolic: 80}
        ]
      })
      |> Ash.create!()

    response = Domain |> get("/measurements/#{m.id}", status: 200)
    attrs = response.resp_body["data"]["attributes"]

    assert attrs["values"] == [
             %{"bpm" => 80, "reading" => nil},
             %{"systolic" => 120, "diastolic" => 80, "reading" => nil}
           ]
  end

  test "filters a union by its variant discriminator" do
    heart_rate =
      Measurement
      |> Ash.Changeset.for_create(:create, %{value: %{type: "heart_rate", bpm: 72}})
      |> Ash.create!()

    blood_pressure =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "blood_pressure", systolic: 120, diastolic: 80}
      })
      |> Ash.create!()

    query =
      Ash.Query.filter_input(Measurement, %{
        "value" => %{"at_path" => ["type"], "eq" => "heart_rate"}
      })

    assert query.valid?
    assert Enum.map(Ash.read!(query), & &1.id) == [heart_rate.id]
    refute blood_pressure.id in Enum.map(Ash.read!(query), & &1.id)

    _conn =
      Domain
      |> get(
        "/measurements?filter[value][at_path][]=type&filter[value][eq]=heart_rate",
        status: 200
      )
      |> assert_valid_resource_objects("measurement", [heart_rate.id])

    _conn =
      Domain
      |> get(
        "/measurements?filter[and][0][value][at_path][]=type&filter[and][0][value][eq]=heart_rate&filter[and][1][value][at_path][]=value&filter[and][1][value][at_path][]=bpm&filter[and][1][value][eq]=72",
        status: 200
      )
      |> assert_valid_resource_objects("measurement", [heart_rate.id])
  end

  test "rejects paths to private union-variant fields" do
    _conn =
      Domain
      |> get(
        "/measurements?filter[value][at_path][]=value&filter[value][at_path][]=private_note&filter[value][eq]=secret",
        status: 400
      )
  end

  test "filters a direct Ash.Type.Union by its variant discriminator" do
    heart_rate =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "heart_rate", bpm: 72},
        direct_value: %{type: "heart_rate", bpm: 72}
      })
      |> Ash.create!()

    _blood_pressure =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "blood_pressure", systolic: 120, diastolic: 80},
        direct_value: %{type: "blood_pressure", systolic: 120, diastolic: 80}
      })
      |> Ash.create!()

    query =
      Ash.Query.filter_input(Measurement, %{
        "direct_value" => %{"at_path" => ["type"], "eq" => "heart_rate"}
      })

    assert query.valid?
    assert Enum.map(Ash.read!(query), & &1.id) == [heart_rate.id]
  end

  test "filters a default-storage union variant field and composes with its discriminator" do
    matching =
      Measurement
      |> Ash.Changeset.for_create(:create, %{value: %{type: "heart_rate", bpm: 72}})
      |> Ash.create!()

    _other_heart_rate =
      Measurement
      |> Ash.Changeset.for_create(:create, %{value: %{type: "heart_rate", bpm: 55}})
      |> Ash.create!()

    other_variant =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "blood_pressure", systolic: 72, diastolic: 50}
      })
      |> Ash.create!()

    query =
      Ash.Query.filter_input(Measurement, %{
        "and" => [
          %{"value" => %{"at_path" => ["type"], "eq" => "heart_rate"}},
          %{"value" => %{"at_path" => ["value", "bpm"], "eq" => 72}}
        ]
      })

    assert query.valid?
    assert Enum.map(Ash.read!(query), & &1.id) == [matching.id]
    refute other_variant.id in Enum.map(Ash.read!(query), & &1.id)
  end

  test "filters a scalar union variant through its stored value" do
    note =
      Measurement
      |> Ash.Changeset.for_create(:create, %{value: "feeling fine"})
      |> Ash.create!()

    _heart_rate =
      Measurement
      |> Ash.Changeset.for_create(:create, %{value: %{type: "heart_rate", bpm: 72}})
      |> Ash.create!()

    query =
      Ash.Query.filter_input(Measurement, %{
        "value" => %{"at_path" => ["value"], "eq" => "feeling fine"}
      })

    assert query.valid?
    assert Enum.map(Ash.read!(query), & &1.id) == [note.id]
  end

  test "characterizes the ETS-internal key for map_with_tag unions" do
    matching =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "heart_rate", bpm: 72},
        tagged_value: %{type: "heart_rate", bpm: 72}
      })
      |> Ash.create!()

    _other =
      Measurement
      |> Ash.Changeset.for_create(:create, %{
        value: %{type: "blood_pressure", systolic: 120, diastolic: 80},
        tagged_value: %{type: "blood_pressure", systolic: 120, diastolic: 80}
      })
      |> Ash.create!()

    query =
      Ash.Query.filter_input(Measurement, %{
        "tagged_value" => %{"at_path" => ["type"], "eq" => "pulse"}
      })

    assert query.valid?
    assert Enum.map(Ash.read!(query), & &1.id) == [matching.id]

    _conn =
      Domain
      |> get(
        "/measurements?filter[tagged_value][at_path][]=type&filter[tagged_value][eq]=heart_rate",
        status: 400
      )
  end

  test "generated filters describe discriminator and supported default-storage paths" do
    schemas = AshJsonApi.OpenApi.schemas([Domain], AshJsonApi.OpenApi.empty_acc())
    measurement_filter = schemas["measurement-filter"]

    assert %OpenApiSpex.Reference{"$ref": "#/components/schemas/measurement-filter-value"} =
             measurement_filter.properties.value

    assert %OpenApiSpex.Schema{anyOf: paths} = schemas["measurement-filter-value"]

    assert Enum.any?(paths, fn
             %OpenApiSpex.Schema{
               properties: %{
                 at_path: %OpenApiSpex.Schema{enum: [["type"]]},
                 eq: %OpenApiSpex.Schema{enum: ["heart_rate", "blood_pressure", "note"]}
               }
             } ->
               true

             _ ->
               false
           end)

    refute Enum.any?(paths, fn
             %OpenApiSpex.Schema{
               properties: %{
                 at_path: %OpenApiSpex.Schema{enum: [["value", "reading"]]}
               }
             } ->
               true

             _ ->
               false
           end)

    assert Enum.any?(paths, fn
             %OpenApiSpex.Schema{
               properties: %{
                 at_path: %OpenApiSpex.Schema{enum: [["value", "bpm"]]},
                 eq: %OpenApiSpex.Schema{type: :integer}
               }
             } ->
               true

             _ ->
               false
           end)

    refute Enum.any?(paths, fn
             %OpenApiSpex.Schema{
               properties: %{at_path: %OpenApiSpex.Schema{enum: [["bpm"]]}}
             } ->
               true

             _ ->
               false
           end)

    refute Map.has_key?(measurement_filter.properties, :tagged_value)
    refute Map.has_key?(schemas, "measurement-filter-tagged_value")
  end
end
