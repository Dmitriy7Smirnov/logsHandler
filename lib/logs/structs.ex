defmodule Log.State do
  defstruct app: "",
    component: "",
    branch: "",
    version: 0,
    level: 0,
    msg: "",
    get_from_id: 0,
    subscriber: :unknown,
    threshold: 0,
    times: 0
end
