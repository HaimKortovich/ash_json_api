# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshJsonApi.Resource.OpenApiAttribute do
  @moduledoc false

  defstruct [:name, :transform, __identifier__: nil, __spark_metadata__: nil]
end
