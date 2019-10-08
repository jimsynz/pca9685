defmodule PCA9685.Device do
  alias PCA9685.{Commands, Device, OutputEnable}
  import PCA9685.Guards
  use GenServer
  require Logger

  @moduledoc """
  Allows setting of PWM values and update frequency on a PCA9685 device.
  """

  # Default configuration values
  @default_config %{
    # The default PWM output frequency
    pwm_freq: 50,
    # No output enable pin needed
    oe_pin: nil
  }

  @doc """
  Returns the currently configured PWM frequency.
  """
  def pwm_freq(device_name),
    do: GenServer.call({:via, Registry, {PCA9685.Registry, device_name}}, :pwm_freq)

  @doc """
  Configures the PWM frequency.
  """
  def pwm_freq(device_name, hz) when is_valid_pwm_frequency(hz),
    do: GenServer.call({:via, Registry, {PCA9685.Registry, device_name}}, {:pwm_freq, hz})

  def pwm_freq(_, hz), do: {:error, "#{hz}hz is not a valid PWM frequency"}

  @doc """
  Sets all channels to the specified duty cycle.
  """
  def all(device_name, on, off) when is_valid_duty_cycle(on) and is_valid_duty_cycle(off),
    do: GenServer.cast({:via, Registry, {PCA9685.Registry, device_name}}, {:all, on, off})

  def all(_, _, _), do: {:error, "Invalid duty cycle"}

  @doc """
  Sets the channel to a specified duty cycle.
  """
  def channel(device_name, channel, on, off)
      when is_valid_duty_cycle(on) and is_valid_duty_cycle(off) and is_valid_channel(channel),
      do:
        GenServer.cast(
          {:via, Registry, {PCA9685.Registry, device_name}},
          {:channel, channel, on, off}
        )

  def channel(_, _, _, _), do: {:error, "Invalid channel or duty cycle"}

  @doc """
  Enables PWM output for this device.

  Fails if there is no `oa_pin` specified in the device configuration.
  """
  @spec output_enable(term) :: :ok | {:error, term}
  def output_enable(device_name),
    do: GenServer.call({:via, Registry, {PCA9685.Registry, device_name}}, :output_enable)

  @doc """
  Disables PWM output for this device.

  Fails if there is no `oa_pin` specified in the device configuration.
  """
  @spec output_disable(term) :: :ok | {:error, term}
  def output_disable(device_name),
    do: GenServer.call({:via, Registry, {PCA9685.Registry, device_name}}, :output_disable)

  @doc false
  def start_link(config), do: GenServer.start_link(Device, config)

  @impl true
  def init(%{bus: bus, address: address} = config) do
    state = Map.merge(@default_config, config)
    name = device_name(state)

    {:ok, _} = Registry.register(PCA9685.Registry, name, self())
    Process.flag(:trap_exit, true)

    Logger.info("Connecting to PCA9685 device on #{inspect(name)}")

    with {:ok, pid} <- Commands.start_link(bus, address),
         state <- Map.put(state, :i2c, pid),
         state <- Map.put(state, :name, name),
         :ok <- Commands.initialize!(pid, state.pwm_freq),
         state <- initialize_output_enable_pin(state) do
      {:ok, state}
    end
  end

  @impl true
  def terminate(_reason, %{i2c: pid, name: name} = state) do
    Logger.info("Disconnecting from PCA9685 device on #{inspect(name)}")
    Commands.release(pid)

    case Map.get(state, :oe) do
      pid when is_pid(pid) ->
        OutputEnable.disable(pid)
        OutputEnable.release(pid)

      _ ->
        :ok
    end
  end

  @impl true
  def handle_call(:pwm_freq, _from, %{pwm_freq: hz} = state), do: {:reply, hz, state}

  def handle_call(:output_enable, _from, %{oe: pid} = state) do
    {:reply, OutputEnable.enable(pid), state}
  end

  def handle_call(:output_enable, _from, state),
    do: {:reply, {:error, "No output enable pin configured"}, state}

  def handle_call(:output_disable, _from, %{oe: pid} = state) do
    {:reply, OutputEnable.disable(pid), state}
  end

  def handle_call(:output_disable, _from, state),
    do: {:reply, {:error, "No output enable pin configured"}, state}

  @impl true
  def handle_cast({:pwm_freq, hz}, %{pwm_freq: hz} = state), do: {:noreply, state}

  def handle_cast({:pwm_freq, hz}, %{pid: pid} = state) do
    :ok = Commands.set_pwm_frequency(pid, hz)
    {:noreply, Map.put(state, :pwm_freq, hz)}
  end

  def handle_cast({:all, on, off}, %{i2c: pid} = state) do
    :ok = Commands.set_all_pwm(pid, on, off)
    {:noreply, state}
  end

  def handle_cast({:channel, channel, on, off}, %{i2c: pid} = state) do
    :ok = Commands.set_one_pwm(pid, channel, on, off)
    {:noreply, state}
  end

  defp device_name(%{bus: bus, address: address} = state) do
    state
    |> Map.get(:name, {bus, address})
  end

  defp initialize_output_enable_pin(%{oe_pin: oe_pin} = state) when is_integer(oe_pin) do
    with {:ok, pid} <- OutputEnable.start_link(oe_pin),
         :ok <- OutputEnable.enable(pid) do
      Map.put(state, :oe, pid)
    end
  end

  defp initialize_output_enable_pin(state), do: state

  @doc false
  def child_spec(config) do
    %{
      id: {PCA9685.Device, device_name(config)},
      start: {PCA9685.Device, :start_link, [config]},
      restart: :transient
    }
  end
end
