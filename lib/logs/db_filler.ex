defmodule DBFiller do
  use GenServer

  @delay 10

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    send(self(), :fill_db)
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
  def handle_info(:fill_db, state) do
    log = %Logs.Log{app: gen_app(), component: gen_component(), branch: gen_branch(), version: Enum.random(1..5), level: Enum.random(0..3), msg: gen_msg()}
    Logs.Repo.insert(log)
    :erlang.send_after(@delay, self(), :fill_db)
    {:noreply, state}
  end

  defp gen_app() do
    case Enum.random(0..5) do
      0 -> "app0"
      1 -> "app1"
      2 -> "app2"
      3 -> "app3"
      4 -> "app4"
      5 -> "app5"
    end
  end

  defp gen_component() do
    case Enum.random(0..1) do
      0 -> "client"
      1 -> "server"
    end
  end

  defp gen_branch() do
    case Enum.random(0..2) do
      0 -> "branch0"
      1 -> "branch1"
      2 -> "branch2"
    end
  end

  defp gen_msg() do
    case Enum.random(0..5) do
      0 -> "message0"
      1 -> "message1"
      2 -> "message2"
      3 -> "message3"
      4 -> "message4"
      5 -> "message5"
    end
  end

end
