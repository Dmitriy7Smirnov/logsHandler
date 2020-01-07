defmodule SubscriberHandler do
  use GenServer

  @update_msg :update
  @stop_msg :stop
  @query_and_save_msg :query_and_save
  @delay 5000

# Imports only from/2 of Ecto.Query
import Ecto.Query, only: [from: 2]

  def start_link(%Log.State{subscriber: genserver_name} = state) do
    GenServer.start_link(__MODULE__, state, name: genserver_name)
  end

  @impl true
  def init(%Log.State{subscriber: table_name} = state) do
    :ets.new(table_name, [:set, :public, :named_table])
    timer_ref = :erlang.send_after(@delay, self(), @query_and_save_msg)
    {:ok, %Log.State{state | get_from_id: get_max_id(), timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(@stop_msg, _from, %Log.State{threshold: threshold, timer_ref: timer_ref} = curr_state) do
    :erlang.cancel_timer(timer_ref)
    query_and_save(%{curr_state | times: threshold - 1})
    {:reply, :ok, curr_state}
  end

  @impl true
  def handle_cast({@update_msg, new_state_msg}, %Log.State{threshold: threshold, timer_ref: timer_ref} = curr_state) do
    :erlang.cancel_timer(timer_ref)
    max_id = get_max_id()
    query_and_save(%Log.State{curr_state | times: threshold - 1})
    timer_ref = :erlang.send_after(@delay, self(), @query_and_save_msg)
    {:noreply, %Log.State{new_state_msg | get_from_id: max_id, timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(@query_and_save_msg, state) do
    state1 = query_and_save(state)
    timer_ref = :erlang.send_after(@delay, self(), @query_and_save_msg)
    {:noreply, %Log.State{state1 | timer_ref: timer_ref}}
  end

  #API functions
  def update_sub(new_state) do
    GenServer.cast(new_state.subscriber, {@update_msg, new_state})
  end

  def stop_sub(server_name) do
    GenServer.call(server_name, @stop_msg)
  end
  # API functions end

  defp query_and_save(
    %Log.State{
      app: app,
      component: _component,
      branch: _branch,
      version: _version,
      level: _level,
      get_from_id: get_from_id,
      subscriber: subscriber,
      threshold: threshold,
      times: times
      } =  state) do

    get_to_id = get_max_id()
    get_logs(get_from_id, get_to_id, app)
      |> List.foldl([], &get_new_logs(subscriber, &1, &2))
      |> Enum.each(&notify(subscriber, &1, 1))

    next_times = case times + 1 do
      ^threshold ->
        dump_logs(subscriber)
        0
      x -> x
    end

    %{state | get_from_id: get_to_id, times: next_times}
  end

  defp dump_logs(subscriber) do
    ms =  [{{:"$1",:"$2"},[{:>,:"$2", 1}],[{{:"$1",:"$2"}}]}]
    all_logs = :ets.select(subscriber, ms)
    Enum.each(all_logs, fn {log, repetitions} -> notify(subscriber, log, repetitions) end);
    :ets.delete_all_objects(subscriber)
  end

  defp get_max_id() do
    query = from logs in "logs",
      select: max(logs.id)

    case Logs.Repo.all(query) do
      [max_id] when is_integer(max_id) -> max_id
      _smth -> 0
    end
  end

  defp get_logs(from_id, to_id, app) do
    query = from logs in "logs",
      where: logs.id > ^from_id and logs.id <= ^to_id and logs.app == ^app,
      select: [:app, :level, :msg],
      order_by: [desc: logs.id]
    Logs.Repo.all(query)
  end

  defp notify(subscriber, log, repetitions) do
    path_to_file = to_string(subscriber)
    {:ok, file} = File.open(path_to_file, [:append])
    s = :io_lib.format("~p", [log])
    case repetitions do
      1 -> IO.binwrite(file,  "new msg:    #{:erlang.iolist_to_binary(s)} \n")
      reps -> IO.binwrite(file,  "#{:erlang.iolist_to_binary(s)}   repetitions = #{:erlang.integer_to_binary(reps)} \n")
    end
    File.close(file)
  end

  defp get_new_logs(ets_name, log_key, new_logs_acc) do
    case :ets.lookup(ets_name, log_key) do

      # log exist already
      [{log_key, repetitions}] ->
        :ets.insert(ets_name, {log_key, repetitions + 1})
        new_logs_acc

      # new log
      [] ->
        :ets.insert(ets_name, {log_key, 1})
        [log_key | new_logs_acc]
    end
  end
end
