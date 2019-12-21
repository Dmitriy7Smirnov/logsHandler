defmodule SubscriberHandler do
  use GenServer

  # Imports only from/2 of Ecto.Query
import Ecto.Query, only: [from: 2]

  def start_link(state) do
    # IO.inspect "Handler here"
    # IO.inspect state
    genserver_name = Map.get(state, "who") |> String.to_atom()
    # IO.inspect genserver_name
    GenServer.start_link(__MODULE__, state, name: genserver_name)
  end

  @impl true
  def init(state) do
    subscriber = Map.get(state, "who")
    create_table(String.to_atom(subscriber))
    state_struct = convert_state_struct(state)
    :erlang.send_after(1000, self(), :query_and_save)
    {:ok, %Log.State{state_struct | get_from_id: get_max_id()}}
  end

  @impl true
  def handle_call(:stop_msg, _from, %Log.State{subscriber: subscriber, threshold: threshold} = curr_state) do
    query_and_save(%{curr_state | times: threshold - 1})
    IO.inspect(subscriber, label: "HANDLE CALL: YOU UNSUSCRIBRED SUCCESSFULLY ")
    {:reply, :reply_to_sender, curr_state}
  end

  @impl true
  def handle_cast(new_state_msg, %Log.State{subscriber: subscriber, threshold: threshold} = curr_state) do
    query_and_save(%{curr_state | times: threshold - 1})
    IO.inspect(subscriber, label: "HANDLE CAST: YOU CHANGED SUBSCRIPTION FOR ")
    new_state_struct = convert_state_struct(new_state_msg)
    IO.inspect new_state_struct
    {:noreply, new_state_struct}
  end

  @impl true
  def handle_info(:query_and_save, state) do
    IO.puts "I im here HANDLER"
     state1 = query_and_save(state)
     :erlang.send_after(5000, self(), :query_and_save)
     {:noreply, state1}
  end

  defp query_and_save(%Log.State{app: app, component: _component, branch: _branch, version: _version, level: _level, get_from_id: get_from_id, subscriber: subscriber, threshold: threshold, times: times} =  state) do
    data_from_postgres_with_id = get_from_postgres(get_from_id, app)
    get_last_id = case data_from_postgres_with_id do
      [head_map | _tail_maps] -> Map.get(head_map, :id)
      [] -> get_from_id
    end
    Enum.map(data_from_postgres_with_id, &Map.delete(&1, :id))
      |> List.foldl([], &ets_update(String.to_atom(subscriber), &1, &2))
      |> Enum.each(&notify_subscriber_about_new_event(subscriber, &1))

     next_times = case times + 1 do
       ^threshold ->
         dump_all_data_to_user(subscriber)
         0
       x -> x
     end

     %{state | get_from_id: get_last_id, times: next_times}
  end

  defp dump_all_data_to_user(subscriber) do
    ms =  [{{:"$1",:"$2"},[{:>,:"$2", 1}],[{{:"$1",:"$2"}}]}]
    all_logs = :ets.select(String.to_atom(subscriber), ms)
    Enum.each(all_logs, &notify_subscriber_about_event(subscriber , &1));
    :ets.delete_all_objects(String.to_atom(subscriber))
  end

  defp convert_state_struct(state) do
    get_from_id = get_max_id()
    app = Map.get(state, "app")
    component = Map.get(state, "component")
    branch = Map.get(state, "branch")
    version = Map.get(state, "version")
    level = Map.get(state, "level")
    subscriber = Map.get(state, "who")
    threshold = Map.get(state, "threshold")
     %Log.State{app: app, component: component, branch: branch, version: version, level: level, get_from_id: get_from_id, subscriber: subscriber, threshold: threshold}
  end

  defp get_max_id() do
    query = from logs in "logs",
    select: max(logs.id)
    case Logs.Repo.all(query) do
      [max_id] when is_integer(max_id) -> max_id
      _smth -> 0
    end
  end

  defp get_from_postgres(from_id, app) do
    query = from logs in "logs",
    where: logs.id > ^from_id and logs.app == ^app,
    select: [:id, :app, :level, :msg],
    order_by: [desc: logs.id]
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

  defp ets_update(ets_name, log_key, new_logs_acc) do
    case :ets.lookup(ets_name, log_key) do
      [{log_key, repetitions}] ->
        :ets.insert(ets_name, {log_key, repetitions + 1})
        new_logs_acc
      [] ->
        :ets.insert(ets_name, {log_key, 1})
        [log_key | new_logs_acc]
    end
  end

end
