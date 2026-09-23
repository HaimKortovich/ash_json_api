if Code.ensure_loaded?(OpenApiSpex) do
  defmodule AshJsonApi.OpenApi.Webhook do
    @moduledoc """
    Typed definition for an OpenAPI webhook.

    Webhooks are represented internally with OpenApiSpex structs and converted
    to a root-level OpenAPI `webhooks` object only when rendered.
    """

    alias OpenApiSpex.{MediaType, Operation, PathItem, Reference, RequestBody, Response, Schema}

    @enforce_keys [:name, :operation]
    defstruct [:name, :operation]

    @type t :: %__MODULE__{
            name: String.t(),
            operation: Operation.t()
          }

    @spec new(atom | String.t(), keyword) :: t
    def new(name, opts) when (is_atom(name) or is_binary(name)) and is_list(opts) do
      name = to_string(name)
      content_type = Keyword.get(opts, :content_type, "application/json")

      payload_schema =
        opts
        |> Keyword.get(:payload_schema, %Schema{type: :object})
        |> validate_schema!()

      responses =
        opts
        |> Keyword.get(:responses, %{
          "200" => %Response{description: "Webhook received"}
        })
        |> validate_responses!()

      request_body = %RequestBody{
        description: Keyword.get(opts, :request_description),
        content: %{content_type => %MediaType{schema: payload_schema}},
        required: Keyword.get(opts, :required, true)
      }

      operation = %Operation{
        operationId: Keyword.get(opts, :operation_id, "#{name}Webhook"),
        summary: Keyword.get(opts, :summary, "#{name} webhook"),
        description: Keyword.get(opts, :description),
        requestBody: request_body,
        responses: responses,
        security: Keyword.get(opts, :security)
      }

      %__MODULE__{name: name, operation: operation}
    end

    @spec path_item(t) :: PathItem.t()
    def path_item(%__MODULE__{operation: operation}) do
      %PathItem{post: operation}
    end

    defp validate_schema!(schema) do
      if is_struct(schema, Schema) or is_struct(schema, Reference) or is_atom(schema) do
        schema
      else
        raise ArgumentError,
              "webhook payload_schema must be an OpenApiSpex.Schema, Reference, or schema module"
      end
    end

    defp validate_responses!(responses) when is_map(responses) do
      if Enum.all?(responses, fn {_status, response} ->
           is_struct(response, Response) or is_struct(response, Reference)
         end) do
        responses
      else
        raise ArgumentError,
              "webhook responses must map status codes to OpenApiSpex.Response or Reference structs"
      end
    end

    defp validate_responses!(_responses) do
      raise ArgumentError, "webhook responses must be a map"
    end
  end
end
