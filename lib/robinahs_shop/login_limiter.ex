defmodule RobinahsShop.LoginLimiter do
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(state), do: {:ok, state}
  def attempt(key), do: GenServer.call(__MODULE__, {:attempt, key})
  def clear(key), do: GenServer.cast(__MODULE__, {:clear, key})

  def handle_call({:attempt, key}, _from, state) do
    now = System.monotonic_time(:second)
    state = Map.reject(state, fn {_, {_, expires}} -> expires <= now end)
    {count, expires} = Map.get(state, key, {0, now + 900})

    if count >= 10 do
      {:reply, :locked, state}
    else
      {:reply, :ok, Map.put(state, key, {count + 1, expires})}
    end
  end

  def handle_cast({:clear, key}, state), do: {:noreply, Map.delete(state, key)}
end
