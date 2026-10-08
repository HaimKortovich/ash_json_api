defmodule AshJsonApi.Webhook.GenerateResource do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  def transform(dsl) do
    secret_store = Transformer.get_option(dsl, [:webhooks, :secret_store], :data_layer)

    if secret_store do
      domain = Transformer.get_persisted(dsl, :module)
      module = Module.concat(domain, WebhookSecret)
      config = secret_store_config(dsl)

      management_route_prefix =
        Transformer.get_option(dsl, [:webhooks], :management_route_prefix, "/")

      define_resource(
        module,
        domain,
        config,
        Transformer.get_option(dsl, [:webhooks], :roles, []),
        management_route_prefix
      )

      {:ok,
       Transformer.add_entity(
         dsl,
         [:resources],
         %Ash.Domain.Dsl.ResourceReference{resource: module},
         type: :append
       )}
    else
      {:ok, dsl}
    end
  end

  def before?(AshJsonApi.Domain.Transformers.SetBaseRoutes), do: true
  def before?(_), do: false

  defp secret_store_config(dsl) do
    for key <- [
          :data_layer,
          :repo,
          :table,
          :organization_attribute,
          :event_attribute,
          :encryption_key
        ],
        into: %{} do
      {key, Transformer.get_option(dsl, [:webhooks, :secret_store], key)}
    end
  end

  defp define_resource(module, domain, config, roles, management_route_prefix) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      # The generated module is compiled while the importing domain is being
      # compiled. Spark only accepts extensions whose modules are already
      # loaded, so make the configured extensions/data layer available before
      # compiling the generated resource.
      Code.ensure_loaded(AshJsonApi.Resource)
      Code.ensure_loaded(config.data_layer)
      Code.ensure_loaded(AshRbac)

      body = resource_ast(module, domain, config, roles, management_route_prefix)
      source = "defmodule #{inspect(module)} do\n#{Macro.to_string(body)}\nend"

      Code.with_diagnostics(fn ->
        Code.compile_string(source, "generated webhook resource")
      end)
    end
  end

  defp resource_ast(_module, domain, config, roles, management_route_prefix) do
    data_layer = config.data_layer
    organization_attribute = config.organization_attribute
    event_attribute = config.event_attribute
    encryption_key = config.encryption_key

    extensions =
      [AshJsonApi.Resource] ++ if Code.ensure_loaded?(AshRbac), do: [AshRbac], else: []

    authorizers = if Code.ensure_loaded?(AshRbac), do: [Ash.Policy.Authorizer], else: []

    rbac_ast = rbac_ast(roles, [:id, organization_attribute, event_attribute])
    rbac_imports = if Code.ensure_loaded?(AshRbac), do: rbac_imports_ast(), else: nil

    route_matchers = route_matchers_ast(management_route_prefix)

    quote do
      use Ash.Resource,
        domain: nil,
        data_layer: unquote(data_layer),
        extensions: unquote(extensions),
        authorizers: unquote(authorizers)

      @persist {:domain, unquote(domain)}

      require AshJsonApi.Resource
      import AshJsonApi.Resource
      unquote(rbac_imports)
      unquote(data_layer_config(data_layer, config))

      json_api do
        type "webhook_secret"

        routes do
          base unquote(management_route_prefix)
          index :read
          get :read
          post :create, metadata: &__MODULE__.creation_metadata/3
          patch :rotate, route: "/:id/rotate", metadata: &__MODULE__.creation_metadata/3
          delete :destroy
        end
      end

      multitenancy do
        strategy(:attribute)
        attribute(unquote(organization_attribute))
      end

      attributes do
        uuid_primary_key(:id, public?: true)
        attribute(unquote(organization_attribute), :string, allow_nil?: false, public?: true)
        attribute(unquote(event_attribute), :string, allow_nil?: false, public?: true)
        attribute(:secret_ciphertext, :string, allow_nil?: false)
        timestamps(type: :utc_datetime_usec)
      end

      actions do
        read :read do
          primary? true
        end

        create :create do
          accept([unquote(event_attribute)])

          change(
            {AshJsonApi.Webhook.GenerateSecretChange,
             encryption_key: unquote(Macro.escape(encryption_key)),
             organization_attribute: unquote(organization_attribute)}
          )
        end

        update :rotate do
          primary? false
          require_atomic?(false)

          change(
            {AshJsonApi.Webhook.GenerateSecretChange,
             encryption_key: unquote(Macro.escape(encryption_key)),
             organization_attribute: unquote(organization_attribute)}
          )
        end

        destroy(:destroy)
      end

      unquote(rbac_ast)

      def creation_metadata(_subject, result, _request) do
        case result.__metadata__[:webhook_secret] do
          nil -> %{}
          secret -> %{"secret" => secret}
        end
      end

      def __ash_json_api_webhook_config__, do: unquote(Macro.escape(config))

      unquote_splicing(route_matchers)
    end
  end

  defp route_matchers_ast(management_route_prefix) do
    route = fn path -> Path.join(management_route_prefix, path) end

    [
      {:get, route.("/"), :read, :read, :index, AshJsonApi.Controllers.Index, nil},
      {:get, route.("/:id"), :read, :read, :get, AshJsonApi.Controllers.Get, nil},
      {:post, route.("/"), :create, :create, :post, AshJsonApi.Controllers.Post, :metadata},
      {:patch, route.("/:id/rotate"), :rotate, :update, :patch, AshJsonApi.Controllers.Patch,
       :metadata},
      {:delete, route.("/:id"), :destroy, :destroy, :delete, AshJsonApi.Controllers.Delete, nil}
    ]
    |> Enum.flat_map(&route_matcher_ast/1)
  end

  defp route_matcher_ast({method, route, action, action_type, type, controller, metadata}) do
    segments = String.split(route, "/", trim: true)

    args =
      Enum.map(segments, fn
        ":" <> param -> {String.to_atom(param), [], Elixir}
        param -> param
      end)

    params =
      segments
      |> Enum.filter(&String.starts_with?(&1, ":"))
      |> Enum.map(fn ":" <> param -> {param, {String.to_atom(param), [], Elixir}} end)

    params = {:%{}, [], params}

    route = %AshJsonApi.Resource.Route{
      route: route,
      action: action,
      action_type: action_type,
      method: method,
      type: type,
      controller: controller
    }

    route_ast =
      if metadata do
        quote do
          route = unquote(Macro.escape(route))
          %{route | metadata: &__MODULE__.creation_metadata/3}
        end
      else
        Macro.escape(route)
      end

    [
      quote do
        def json_api_match_route(unquote(method), [unquote_splicing(args)]) do
          {:ok, unquote(route_ast), unquote(params)}
        end

        def json_api_match_route(unquote(String.upcase(to_string(method))), [
              unquote_splicing(args)
            ]) do
          {:ok, unquote(route_ast), unquote(params)}
        end
      end
    ]
  end

  defp data_layer_config(AshPostgres.DataLayer, config) do
    quote do
      require AshPostgres.DataLayer
      import AshPostgres.DataLayer

      postgres do
        table(unquote(config.table))
        repo(unquote(config.repo))
      end
    end
  end

  defp data_layer_config(_data_layer, _config), do: nil

  defp rbac_imports_ast do
    quote do
      require AshRbac
      import AshRbac
    end
  end

  defp rbac_ast([], _public_fields), do: nil

  defp rbac_ast(roles, public_fields) do
    unless Code.ensure_loaded?(AshRbac) do
      raise "AshJsonApi webhook roles require the optional ash_rbac dependency"
    end

    role_blocks =
      Enum.map(roles, fn {role, actions} ->
        quote do
          role unquote(role) do
            fields(unquote(public_fields))
            actions(unquote(actions))
          end
        end
      end)

    quote do
      rbac do
        (unquote_splicing(role_blocks))
      end
    end
  end
end
