defmodule SubscriberManager do
  use GenServer

  @ets_name :subscriber_manager
  @subscriber_state_key "subscriber_state_key"

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    create_table()
    send(self(), :subscribers_start)
    {:ok, %{name: 1}}
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
  def handle_info(:subscribers_start, state) do
    {:ok, result} = File.read("subscribers.json")
    subscribers = result
      |> String.replace("\r", "")
      |> String.replace("\n", "")
      |> Jason.decode!()
      |> Map.get("subscriptions")

    {subs_for_create, subs_for_update, subs_for_delete_names} = ets_update(subscribers, {[], [], []})
      IO.inspect "SUBSCRIBERS START HERE"
      IO.inspect(subs_for_create, label: "for create")
      IO.inspect(subs_for_update, label: "for update")
      IO.inspect(subs_for_delete_names, label: "for delete")

    create_subs_processes(subs_for_create)
    updata_subs(subs_for_update)
    delete_subs(subs_for_delete_names)

    :erlang.send_after(10000, self(), :subscribers_start)
    {:noreply, state}
  end

  defp create_subs_processes(subs_for_create) do
    Enum.each(subs_for_create, &DynamicSupervisor.start_child(MyApp.DynamicSupervisor, {SubscriberHandler, &1}))
    subs_for_create
  end

  defp updata_subs(subs_for_update) do
    Enum.each(subs_for_update, &GenServer.cast(&1 |> Map.get("who") |> String.to_atom(), &1))
  end



  defp delete_subs(subs_for_delete_names) do
    IO.inspect(subs_for_delete_names, label: "DELETE SUBS")
    subs_for_delete_names
      |> Enum.map(&(&1 |> String.to_atom()))
      |> Enum.map(&GenServer.call(&1, :stop_msg))
    subs_for_delete_names
      |> Enum.each(&DynamicSupervisor.terminate_child(MyApp.DynamicSupervisor, Process.whereis(&1 |> String.to_atom())))
    subs_for_delete_names
      |> Enum.each(&:ets.delete(@ets_name, &1))
    case :ets.lookup(@ets_name, @subscriber_state_key) do
      [{@subscriber_state_key, all_prev_subs_names}] ->
        :ets.insert(@ets_name, {@subscriber_state_key, all_prev_subs_names -- subs_for_delete_names})
      [] ->
        :ignore
    end
  end

  defp create_table() do
    :ets.new(@ets_name, [:set, :private, :named_table])
  end

  defp ets_update([], {subs_for_create, subs_for_update, all_current_subs_names}) do
    subs_for_delete_names = case :ets.lookup(@ets_name, @subscriber_state_key) do
      [{@subscriber_state_key, all_prev_subs_names}] ->
        :ets.insert(@ets_name, {@subscriber_state_key, all_current_subs_names})
        all_prev_subs_names -- all_current_subs_names
      [] ->
        :ets.insert(@ets_name, {@subscriber_state_key, all_current_subs_names})
        []
    end
    {subs_for_create, subs_for_update, subs_for_delete_names}
  end

  defp ets_update([sub_param | subs_params], {subs_for_create, subs_for_update, all_current_subs_names}) do
    subscriber = Map.get(sub_param, "who")
    {new_subs_for_create, new_subs_for_update, new_all_current_subs_names} = case :ets.lookup(@ets_name, subscriber) do
      [{^subscriber, ^sub_param}] ->
        # data exists already
        {subs_for_create, subs_for_update, [subscriber | all_current_subs_names]}
      [{^subscriber, _old_sub_param}] ->
        :ets.insert(@ets_name, {subscriber, sub_param})
        {subs_for_create, [sub_param | subs_for_update], [subscriber | all_current_subs_names]}
      [] ->
        :ets.insert(@ets_name, {subscriber, sub_param})
        {[sub_param | subs_for_create], subs_for_update, [subscriber | all_current_subs_names]}
    end
    ets_update(subs_params, {new_subs_for_create, new_subs_for_update, new_all_current_subs_names} )
  end

end
