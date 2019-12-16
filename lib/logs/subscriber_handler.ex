defmodule SubscriberHandler do
  use GenServer

  # Imports only from/2 of Ecto.Query
import Ecto.Query, only: [from: 2]



  def start_link(state) do
    IO.inspect "Handler here"
    IO.inspect state
    genserver_name = Map.get(state, "who") |> String.to_atom()
    IO.inspect genserver_name
    GenServer.start_link(__MODULE__, state, name: genserver_name)
  end

  @impl true
  def init(state) do
    get_from_id = get_max_id()
    app = Map.get(state, "app")
    component = Map.get(state, "component")
    branch = Map.get(state, "branch")
    version = Map.get(state, "version")
    level = Map.get(state, "level")
    subscriber = Map.get(state, "who")
    threshold = Map.get(state, "threshold")
    create_table(String.to_atom(subscriber))
    state_struct = %Log.State{app: app, component: component, branch: branch, version: version, level: level, get_from_id: get_from_id, subscriber: subscriber, threshold: threshold}
    :erlang.send_after(1000, self(), :query_and_save)
    {:ok, state_struct}
  end

  @impl true
  def handle_call(msg, _from, state) do
    {:reply, state, msg}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:query_and_save, %Log.State{app: app, component: _component, branch: _branch, version: _version, level: _level, get_from_id: get_from_id, subscriber: subscriber, threshold: threshold, times: times} =  state) do
    IO.puts "I im here HANDLER"
    get_to_id = get_max_id()
    data_from_postgres = get_from_postgres(get_from_id, get_to_id, app)
    new_logs_list = ets_update(String.to_atom(subscriber), data_from_postgres, [])
    Enum.each(new_logs_list, &notify_subscriber_about_new_event(subscriber, &1))

     next_times = case times + 1 do
       ^threshold ->
         ms =  [{{:"$1",:"$2"},[{:>,:"$2", 1}],[{{:"$1",:"$2"}}]}]
         all_logs = :ets.select(String.to_atom(subscriber), ms)
         Enum.each(all_logs, &notify_subscriber_about_event(subscriber , &1));
         :ets.delete_all_objects(String.to_atom(subscriber))
         0
       x -> x
     end

     state1 = %{state | get_from_id: get_to_id, times: next_times}
     :erlang.send_after(5000, self(), :query_and_save)
     {:noreply, state1}
  end

  defp get_max_id() do
    query = from logs in "logs",
    select: max(logs.id)
    [max_id] = Logs.Repo.all(query)
    max_id
  end

  defp get_from_postgres(from_id, to_id, app) do
    query = from logs in "logs",
    where: logs.id > ^from_id and logs.id <= ^to_id and logs.app == ^app,
    select: [:app, :level, :msg]
    Logs.Repo.all(query)
  end


  defp notify_subscriber_about_new_event(recipient, new_log) do
    path_to_file = recipient
    {:ok, file} = File.open(path_to_file, [:append])
    s = :io_lib.format("~p~n", [new_log])
    IO.binwrite(file,  "new msg:    " <> :erlang.iolist_to_binary(s))
    File.close(file)
  end

  defp notify_subscriber_about_event(recipient, {log, repetitions}) do
    path_to_file = recipient
    {:ok, file} = File.open(path_to_file, [:append])
    s = :io_lib.format("~p", [log])
    IO.binwrite(file,  :erlang.iolist_to_binary(s) <> "  repetitions = " <> :erlang.integer_to_binary(repetitions) <> "\n")
    File.close(file)
  end

  defp create_table(table_name) do
    :ets.new(table_name, [:set, :public, :named_table])
  end


  defp ets_update(_ets_name, [], new_logs_list) do
    new_logs_list
  end

  defp ets_update(ets_name, [head_key | tail], new_logs_list) do
    new_logs_list1 = case :ets.lookup(ets_name, head_key) do
      [{head_key, repetitions}] ->
        :ets.insert(ets_name, {head_key, repetitions + 1})
        new_logs_list
      [] ->
        :ets.insert(ets_name, {head_key, 1})
        [head_key | new_logs_list]
    end
    ets_update(ets_name, tail, new_logs_list1)
  end

end
