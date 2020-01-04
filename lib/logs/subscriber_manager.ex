defmodule SubscriberManager do
  use GenServer

  @ets_subs_structs :subscriber_structs
  @ets_subs_names :subscriber_keys
  @curr_subscribers_key "curr_subscribers_key"
  @deley 10000


  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    :ets.new(@ets_subs_structs, [:set, :private, :named_table])
    :ets.new(@ets_subs_names, [:set, :private, :named_table])
    :ets.insert(@ets_subs_names, {@curr_subscribers_key, []})
    send(self(), :subscribers_update)
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
  def handle_info(:subscribers_update, state) do
    {:ok, file_data} = File.read("subscribers.json")
    %{"subscriptions" => subscribers} = Jason.decode!(file_data)
    subscribers_struct = Enum.map(subscribers, &to_struct(&1))
    {subs_for_create, subs_for_update, all_current_subs_names} = List.foldl(subscribers_struct, {[], [], []}, &ets_update(&1, &2))

    # get subscriber names for delete
    [{@curr_subscribers_key, all_prev_subs_names}] = :ets.lookup(@ets_subs_names, @curr_subscribers_key)
    subs_for_delete_names = all_prev_subs_names -- all_current_subs_names

    # save all current subscriber names
    :ets.insert(@ets_subs_names, {@curr_subscribers_key, all_current_subs_names})

    # create subscribers
    Enum.each(subs_for_create, &DynamicSupervisor.start_child(MyApp.DynamicSupervisor, {SubscriberHandler, &1}))

    # update subscribers
    Enum.each(subs_for_update, &SubscriberHandler.update_sub(&1))

    # delete subscribers
    Enum.each(subs_for_delete_names, &delete(&1))

    :erlang.send_after(@deley, self(), :subscribers_update)
    {:noreply, state}
  end

  defp to_struct(
    %{
      "app" => app,
      "component" => component,
      "branch" => branch,
      "version" => version,
      "level" => level,
      "who" => who,
      "threshold" => threshold
    }
  ) do
    %Log.State{
      app: app,
      component: component,
      branch: branch,
      version: version,
      level: level,
      subscriber: String.to_atom(who),
      threshold: threshold
    }
  end

  defp delete(subscriber) do
    SubscriberHandler.stop_sub(subscriber)
    DynamicSupervisor.terminate_child(MyApp.DynamicSupervisor, Process.whereis(subscriber))
    :ets.delete(@ets_subs_structs, subscriber)
  end

  defp ets_update(subscriber_struct, {subs_for_create, subs_for_update, all_current_subs_names}) do
    subscriber = subscriber_struct.subscriber
    case :ets.lookup(@ets_subs_structs, subscriber) do
      # data exists already
      [{^subscriber, ^subscriber_struct}] ->
        {subs_for_create, subs_for_update, [subscriber | all_current_subs_names]}
      # data was changed
      [{^subscriber, _old_sub_param}] ->
        :ets.insert(@ets_subs_structs, {subscriber, subscriber_struct})
        {subs_for_create, [subscriber_struct | subs_for_update], [subscriber | all_current_subs_names]}
      # new data
      [] ->
        :ets.insert(@ets_subs_structs, {subscriber, subscriber_struct})
        {[subscriber_struct | subs_for_create], subs_for_update, [subscriber | all_current_subs_names]}
    end
  end
end
