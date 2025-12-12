defmodule PCA9685.Device do
  @options_schema NimbleOptions.new!(
                    bus: [
                      type: :string,
                      required: true,
                      doc: "The I2C bus name (e.g. `\"i2c-1\"`)."
                    ],
                    address: [
                      type: {:in, 0..127},
                      required: true,
                      doc: "The I2C address of the device (0-127, e.g. `0x40`)."
                    ],
                    pwm_freq: [
                      type: {:in, 24..1526},
                      default: 50,
                      doc: "The PWM frequency in Hz."
                    ],
                    oscillator_freq: [
                      type: :pos_integer,
                      default: 25_000_000,
                      doc:
                        "The PCA9685 internal oscillator frequency in Hz. Nominally 25MHz but varies per chip (23-27MHz). Calibrate for precise pulse width control."
                    ],
                    oe_pin: [
                      type: :non_neg_integer,
                      doc: "GPIO pin number for output enable (directly connected to OE\\ pin)."
                    ],
                    name: [
                      type: :any,
                      doc:
                        "GenServer name for registration (e.g. `MyPWM` or `{:via, Registry, key}`)."
                    ]
                  )

  @moduledoc """
  GenServer managing a PCA9685 device connection.

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """

  use GenServer

  alias PCA9685.Chip
  alias Wafer.Driver.Circuits.GPIO, as: GPIODriver
  alias Wafer.{GPIO, Release}
  require Logger

  @doc """
  Returns the currently configured PWM frequency.
  """
  @spec pwm_freq(GenServer.server()) :: pos_integer()
  def pwm_freq(server),
    do: GenServer.call(server, :pwm_freq)

  @doc """
  Configures the PWM frequency (24-1526 Hz).
  """
  @spec pwm_freq(GenServer.server(), pos_integer()) :: :ok | {:error, term()}
  def pwm_freq(server, hz) when is_integer(hz) and hz >= 24 and hz <= 1526,
    do: GenServer.call(server, {:pwm_freq, hz})

  def pwm_freq(_, hz), do: {:error, "#{hz}hz is not a valid PWM frequency (must be 24-1526)"}

  @doc """
  Sets all channels to the specified duty cycle (0-4095).
  """
  @spec all(GenServer.server(), 0..4095, 0..4095) :: :ok | {:error, term()}
  def all(server, on, off)
      when is_integer(on) and on in 0..4095 and is_integer(off) and off in 0..4095,
      do: GenServer.cast(server, {:all, on, off})

  def all(_, _, _), do: {:error, "Invalid duty cycle (must be 0-4095)"}

  @doc """
  Reads all channels' duty cycles.

  Returns a list of 16 `{on, off}` tuples, one for each channel.
  """
  @spec get_all(GenServer.server()) :: {:ok, list({0..4095, 0..4095})} | {:error, term()}
  def get_all(server),
    do: GenServer.call(server, :get_all)

  @doc """
  Sets the channel (0-15) to a specified duty cycle (0-4095).
  """
  @spec channel(GenServer.server(), 0..15, 0..4095, 0..4095) :: :ok | {:error, term()}
  def channel(server, channel, on, off)
      when is_integer(channel) and channel in 0..15 and
             is_integer(on) and on in 0..4095 and
             is_integer(off) and off in 0..4095,
      do: GenServer.cast(server, {:channel, channel, on, off})

  def channel(_, _, _, _), do: {:error, "Invalid channel (0-15) or duty cycle (0-4095)"}

  @doc """
  Reads a channel's duty cycle.

  Returns `{on, off}` values (0-4095).
  """
  @spec get_channel(GenServer.server(), 0..15) :: {:ok, {0..4095, 0..4095}} | {:error, term()}
  def get_channel(server, channel) when is_integer(channel) and channel in 0..15,
    do: GenServer.call(server, {:get_channel, channel})

  def get_channel(_, _), do: {:error, "Invalid channel (0-15)"}

  @doc """
  Sets a channel's PWM pulse width in microseconds.

  This is useful for servo control where pulse widths are typically:
  - 1000µs (1ms) for minimum position
  - 1500µs for centre position
  - 2000µs (2ms) for maximum position

  The conversion accounts for the configured oscillator frequency and PWM
  frequency to calculate the correct register values.

  ## Example

      # Move servo on channel 0 to centre position
      PCA9685.Device.pulse_width(pid, 0, 1500)

  """
  @spec pulse_width(GenServer.server(), 0..15, pos_integer()) :: :ok | {:error, term()}
  def pulse_width(server, channel, microseconds)
      when is_integer(channel) and channel in 0..15 and
             is_integer(microseconds) and microseconds > 0,
      do: GenServer.cast(server, {:pulse_width, channel, microseconds})

  def pulse_width(_, _, _), do: {:error, "Invalid channel (0-15) or pulse width"}

  @doc """
  Reads a channel's PWM pulse width in microseconds.

  This is the inverse of `pulse_width/3`, converting the raw register values
  back to microseconds based on the configured oscillator and PWM frequency.
  """
  @spec get_pulse_width(GenServer.server(), 0..15) :: {:ok, pos_integer()} | {:error, term()}
  def get_pulse_width(server, channel) when is_integer(channel) and channel in 0..15,
    do: GenServer.call(server, {:get_pulse_width, channel})

  def get_pulse_width(_, _), do: {:error, "Invalid channel (0-15)"}

  @doc """
  Enables PWM output for this device.

  Fails if there is no `oe_pin` specified in the device configuration.
  """
  @spec output_enable(GenServer.server()) :: :ok | {:error, term()}
  def output_enable(server),
    do: GenServer.call(server, :output_enable)

  @doc """
  Disables PWM output for this device.

  Fails if there is no `oe_pin` specified in the device configuration.
  """
  @spec output_disable(GenServer.server()) :: :ok | {:error, term()}
  def output_disable(server),
    do: GenServer.call(server, :output_disable)

  @doc """
  Starts a PCA9685 device GenServer.

  See module documentation for available options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    opts = NimbleOptions.validate!(opts, @options_schema)
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @impl GenServer
  def init(opts) do
    bus = Keyword.fetch!(opts, :bus)
    address = Keyword.fetch!(opts, :address)
    pwm_freq = Keyword.fetch!(opts, :pwm_freq)
    oscillator_freq = Keyword.fetch!(opts, :oscillator_freq)
    oe_pin = Keyword.get(opts, :oe_pin)

    Process.flag(:trap_exit, true)

    Logger.info("Connecting to PCA9685 device on #{bus}:#{inspect(address)}")

    with {:ok, chip} <- Chip.acquire(bus: bus, address: address),
         {:ok, chip} <- Chip.initialize(chip, pwm_freq, oscillator_freq) do
      state = %{
        chip: chip,
        pwm_freq: pwm_freq,
        oscillator_freq: oscillator_freq,
        bus: bus,
        address: address
      }

      init_output_enable(state, oe_pin)
    end
  end

  @impl GenServer
  def terminate(_reason, %{chip: chip, bus: bus, address: address} = state) do
    Logger.info("Disconnecting from PCA9685 device on #{bus}:#{inspect(address)}")
    Release.release(chip)

    case Map.get(state, :oe) do
      %GPIODriver{} = gpio ->
        GPIO.write(gpio, 1)
        Release.release(gpio)

      _ ->
        :ok
    end
  end

  @impl GenServer
  def handle_call(:pwm_freq, _from, %{pwm_freq: hz} = state),
    do: {:reply, hz, state}

  def handle_call({:pwm_freq, hz}, _from, %{chip: chip, oscillator_freq: osc_freq} = state) do
    case Chip.set_pwm_frequency(chip, hz, osc_freq) do
      {:ok, chip} ->
        {:reply, :ok, %{state | chip: chip, pwm_freq: hz}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:output_enable, _from, %{oe: gpio} = state) do
    case GPIO.write(gpio, 0) do
      {:ok, gpio} -> {:reply, :ok, %{state | oe: gpio}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:output_enable, _from, state),
    do: {:reply, {:error, "No output enable pin configured"}, state}

  def handle_call(:output_disable, _from, %{oe: gpio} = state) do
    case GPIO.write(gpio, 1) do
      {:ok, gpio} -> {:reply, :ok, %{state | oe: gpio}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:output_disable, _from, state),
    do: {:reply, {:error, "No output enable pin configured"}, state}

  def handle_call(:get_all, _from, %{chip: chip} = state) do
    {:reply, Chip.get_all_pwm(chip), state}
  end

  def handle_call({:get_channel, channel}, _from, %{chip: chip} = state) do
    {:reply, Chip.get_channel_pwm(chip, channel), state}
  end

  def handle_call({:get_pulse_width, channel}, _from, %{chip: chip} = state) do
    case Chip.get_channel_pwm(chip, channel) do
      {:ok, {_on, off}} ->
        microseconds = ticks_to_microseconds(off, state.pwm_freq, state.oscillator_freq)
        {:reply, {:ok, microseconds}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_cast({:all, on, off}, %{chip: chip} = state) do
    case Chip.set_all_pwm(chip, on, off) do
      {:ok, chip} -> {:noreply, %{state | chip: chip}}
      {:error, _} -> {:noreply, state}
    end
  end

  def handle_cast({:channel, channel, on, off}, %{chip: chip} = state) do
    case Chip.set_channel_pwm(chip, channel, on, off) do
      {:ok, chip} -> {:noreply, %{state | chip: chip}}
      {:error, _} -> {:noreply, state}
    end
  end

  def handle_cast({:pulse_width, channel, microseconds}, %{chip: chip} = state) do
    ticks = microseconds_to_ticks(microseconds, state.pwm_freq, state.oscillator_freq)

    case Chip.set_channel_pwm(chip, channel, 0, ticks) do
      {:ok, chip} -> {:noreply, %{state | chip: chip}}
      {:error, _} -> {:noreply, state}
    end
  end

  defp microseconds_to_ticks(microseconds, pwm_freq, oscillator_freq) do
    prescale = round(oscillator_freq / 4096.0 / pwm_freq - 1 + 0.5)
    pulselength_us = 1_000_000.0 * (prescale + 1) / oscillator_freq
    ticks = round(microseconds / pulselength_us)
    min(ticks, 4095)
  end

  defp ticks_to_microseconds(ticks, pwm_freq, oscillator_freq) do
    prescale = round(oscillator_freq / 4096.0 / pwm_freq - 1 + 0.5)
    pulselength_us = 1_000_000.0 * (prescale + 1) / oscillator_freq
    round(ticks * pulselength_us)
  end

  defp init_output_enable(state, nil), do: {:ok, state}

  defp init_output_enable(state, pin) when is_integer(pin) do
    with {:ok, gpio} <- GPIODriver.acquire(pin: pin, direction: :out),
         {:ok, gpio} <- GPIO.write(gpio, 0) do
      {:ok, Map.put(state, :oe, gpio)}
    end
  end

  @doc false
  def child_spec(opts) do
    opts = NimbleOptions.validate!(opts, @options_schema)

    %{
      id: {__MODULE__, Keyword.get(opts, :name, make_ref())},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end
end
