defmodule SubscriberManager do
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(_state) do
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
    IO.puts "I im here subscriber manager"
    {:ok, result} = File.read("subscribers.json")
    result
      |> String.replace("\r", "")
      |> String.replace("\n", "")
      |> Jason.decode!()
      |> Map.get("subscriptions")
      |> Enum.each(&DynamicSupervisor.start_child(MyApp.DynamicSupervisor, {SubscriberHandler, &1}))
    {:noreply, state}
  end


end
