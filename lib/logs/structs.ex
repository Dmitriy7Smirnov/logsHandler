defmodule Log.Levels do
  defstruct debug: 0, info: 1, warning: 2, error: 3
end


defmodule Log.State do
  defstruct app: "", component: "", branch: "", version: 0, level: 0, msg: "", get_from_id: 0, subscriber: "", threshold: 0, times: 0
end
