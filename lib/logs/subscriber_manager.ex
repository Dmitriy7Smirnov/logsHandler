defmodule SubscriberManager do
  use GenServer

  @ets_name :subscriber_manager
  @curr_subscribers_keys "curr_subscribers_keys"

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    create_table()
    send(self(), :subscribers_start)
    {:ok, %{}}
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
    {:ok, file_data} = File.read("subscribers.json")
    %{"subscriptions" => subscribers} = Jason.decode!(file_data)


    {subs_for_create, subs_for_update, subs_for_delete_names} = ets_update(subscribers, {[], [], []})
      IO.inspect "SUBSCRIBERS START HERE"
      IO.inspect(subs_for_create, label: "for create")
      IO.inspect(subs_for_update, label: "for update")
      IO.inspect(subs_for_delete_names, label: "for delete")

    create_subs_processes(subs_for_create)
    update_subs(subs_for_update)
    delete_subs(subs_for_delete_names)

    :erlang.send_after(10000, self(), :subscribers_start)
    {:noreply, state}
  end

  defp create_subs_processes(subs_for_create) do
    Enum.each(subs_for_create, &DynamicSupervisor.start_child(MyApp.DynamicSupervisor, {SubscriberHandler, &1}))
  end

  defp update_subs(subs_for_update) do
    Enum.each(subs_for_update, &GenServer.cast(String.to_atom(Map.get(&1, "who")), &1))
  end

  defp delete_subs(subs_for_delete_names) do
    IO.inspect(subs_for_delete_names, label: "DELETE SUBS")
    subs_for_delete_names
      |> Enum.map(&(String.to_atom(&1)))
      |> Enum.map(&GenServer.call(&1, :stop_msg))
    subs_for_delete_names
      |> Enum.each(&DynamicSupervisor.terminate_child(MyApp.DynamicSupervisor, Process.whereis(String.to_atom(&1))))
    subs_for_delete_names
      |> Enum.each(&:ets.delete(@ets_name, &1))
    case :ets.lookup(@ets_name, @curr_subscribers_keys) do
      [{@curr_subscribers_keys, all_prev_subs_names}] ->
        :ets.insert(@ets_name, {@curr_subscribers_keys, all_prev_subs_names -- subs_for_delete_names})
      [] ->
        :ignore
    end
  end

  defp create_table() do
    :ets.new(@ets_name, [:set, :private, :named_table])
  end

  defp ets_update([], {subs_for_create, subs_for_update, all_current_subs_names}) do
    subs_for_delete_names = :ets.lookup(@ets_name, @curr_subscribers_keys) -- all_current_subs_names
    :ets.insert(@ets_name, {@curr_subscribers_keys, all_current_subs_names})
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
