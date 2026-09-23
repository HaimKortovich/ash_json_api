defmodule AshJsonApi.Plug.RawBodyReader do
  @moduledoc false

  @doc false
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}

      {:more, body, conn} ->
        {:more, body, Plug.Conn.assign(conn, :raw_body, body)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
