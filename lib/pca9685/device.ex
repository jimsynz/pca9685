defmodule PCA9685.Device do
  alias PCA9685.Device
  alias ElixirALE.I2C
  use GenServer
  use Bitwise
  require Logger

  @moduledoc """
  Allows setting of PWM values and update frequency on a PCA9685 device.
  """

  # Registers/etc:
  @pca9685_address 0x40
  @mode1 0x00
  @mode2 0x01
  @subadr1 0x02
  @subadr2 0x03
  @subadr3 0x04
  @prescale 0xFE
  @led0_on_l 0x06
  @led0_on_h 0x07
  @led0_off_l 0x08
  @led0_off_h 0x09
  @all_led_on_l 0xFA
  @all_led_on_h 0xFB
  @all_led_off_l 0xFC
  @all_led_off_h 0xFD

  # Bits:
  @restart 0x80
  @sleep 0x10
  @allcall 0x01
  @invrt 0x10
  @outdrv 0x04

  @doc """
  Returns the currently configured PWM frequency.
  """
  def pwm_freq(device_name),
    do: GenServer.call({:via, Registry, {PCA9685.Registry, device_name}}, :pwm_freq)

  @doc """
  Configures the PWM frequency.
  """
  def pwm_freq(device_name, hz),
    do: GenServer.call({:via, Registry, {PCA9685.Registry, device_name}}, {:pwm_freq, hz})

  @doc """
  Sets all channels to the specified duty cycle.
  """
  def all(device_name, on, off)
      when is_integer(on) and is_integer(off) and on >= 0 and on <= 4096 and off >= 0 and
             off <= 4096,
      do: GenServer.cast({:via, Registry, {PCA9685.Registry, device_name}}, {:all, on, off})

  @doc """
  Sets the channel to a specified duty cycle.
  """
  def channel(device_name, channel, on, off)
      when is_integer(channel) and channel >= 0 and channel <= 16 and is_integer(on) and
             is_integer(off) and on >= 0 and on <= 4096 and off >= 0 and
             off <= 4096,
      do:
        GenServer.cast(
          {:via, Registry, {PCA9685.Registry, device_name}},
          {:channel, channel, on, off}
        )

  @doc false
  def start_link(config), do: GenServer.start_link(Device, config)

  @impl true
  def init(%{bus: bus, address: address} = state) do
    name = device_name(state)

    {:ok, _} = Registry.register(PCA9685.Registry, name, self())
    Process.flag(:trap_exit, true)

    Logger.info("Connecting to PCA9685 device on #{inspect(name)}")

    state = Map.put_new(state, :pwm_freq, 60)

    with {:ok, pid} <- I2C.start_link(bus, address),
         state <- Map.put(state, :pid, pid),
         :ok <- do_set_all_pwm(state, 0, 0),
         :ok <- I2C.write(pid, <<@mode2, @outdrv>>),
         :ok <- I2C.write(pid, <<@mode1, @allcall>>),
         :ok <- :timer.sleep(5),
         <<mode1>> <- I2C.write_read(pid, <<@mode1>>, 1),
         :ok <- I2C.write(pid, <<@mode1, mode1 &&& ~~~@sleep>>),
         :ok <- :timer.sleep(5),
         :ok <- set_pwm_freq_if_required(state) do
      {:ok, state}
    end
  end

  @impl true
  def terminate(_reason, %{i2c: pid, name: name}) do
    Logger.info("Disconnecting from PCA9685 device on #{inspect(name)}")
    I2C.release(pid)
  end

  @impl true
  def handle_call(:pwm_freq, _from, %{pwm_freq: hz} = state), do: {:reply, hz, state}

  @impl true
  def handle_cast({:pwm_freq, hz}, %{pwm_freq: hz} = state), do: {:noreply, state}

  def handle_cast({:pwm_freq, hz}, %{pid: pid} = state) do
    :ok = do_set_pwm_freq(pid, hz)
    {:noreply, Map.put(state, :pwm_freq, hz)}
  end

  def handle_cast({:all, on, off}, state) do
    :ok = do_set_all_pwm(state, on, off)
    {:noreply, state}
  end

  def handle_cast({:channel, channel, on, off}, state) do
    :ok = do_set_pwm(state, channel, on, off)
    {:noreply, state}
  end

  defp device_name(%{bus: bus, address: address} = state) do
    state
    |> Map.get(:name, {bus, address})
  end

  @doc false
  def child_spec(config) do
    %{
      id: {PCA9685.Device, device_name(config)},
      start: {PCA9685.Device, :start_link, [config]},
      restart: :transient
    }
  end

  defp do_set_all_pwm(%{pid: pid}, on, off) do
    with :ok <- I2C.write(pid, <<@all_led_on_l, on &&& 0xFF>>),
         :ok <- I2C.write(pid, <<@all_led_on_h, on >>> 8>>),
         :ok <- I2C.write(pid, <<@all_led_off_l, off &&& 0xFF>>),
         :ok <- I2C.write(pid, <<@all_led_off_h, off >>> 8>>),
         do: :ok
  end

  defp set_pwm_freq_if_required(%{pwm_freq: hz} = state) when is_number(hz) and hz > 0,
    do: do_set_pwm_freq(state, hz)

  defp set_pwm_freq_if_required(_state), do: :ok

  defp do_set_pwm_freq(%{pid: pid}, freq_hz) do
    prescale = 25_000_000.0
    prescale = prescale / 4096.0
    prescale = prescale / freq_hz
    prescale = prescale - 1

    Logger.debug("Setting PWM frequency to #{freq_hz}hz")
    Logger.debug("Estimated pre-scale: #{prescale}")

    prescale = prescale + 0.5
    prescale = Float.floor(prescale)
    prescale = round(prescale)

    Logger.debug("Final pre-scale: #{prescale}")

    <<old_mode>> = I2C.write_read(pid, <<@mode1>>, 1)
    new_mode = (old_mode &&& 0x7F) ||| 0x10

    :ok = I2C.write(pid, <<@mode1, new_mode>>)
    :ok = I2C.write(pid, <<@prescale, prescale>>)
    :ok = I2C.write(pid, <<@mode1, old_mode>>)
    :ok = :timer.sleep(5)
    :ok = I2C.write(pid, <<@mode1, old_mode ||| 0x80>>)
  end

  defp do_set_pwm(%{pid: pid}, channel, on, off) do
    with :ok <- I2C.write(pid, <<@led0_on_l + 4 * channel, on &&& 0xFF>>),
         :ok <- I2C.write(pid, <<@led0_on_h + 4 * channel, on >>> 8>>),
         :ok <- I2C.write(pid, <<@led0_off_l + 4 * channel, off &&& 0xFF>>),
         :ok <- I2C.write(pid, <<@led0_off_h + 4 * channel, off >>> 8>>),
         do: :ok
  end
end
