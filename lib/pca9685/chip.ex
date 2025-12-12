defmodule PCA9685.Chip do
  @moduledoc """
  Wafer connection for PCA9685 16-channel, 12-bit PWM driver.

  This module implements the `Wafer.Conn` behaviour and provides low-level
  access to the PCA9685 device over I2C.
  """

  use Wafer.Registers
  @behaviour Wafer.Conn

  @derive [Wafer.Chip, Wafer.I2C, Wafer.Release]
  defstruct [:conn]

  alias Wafer.Chip
  alias Wafer.Driver.Circuits.I2C, as: I2CDriver
  import Bitwise
  import PCA9685.Guards
  require Logger

  @led0_on_l_addr 0x06
  @all_led_on_l_addr 0xFA

  @ai 0x20
  @sleep 0x10
  @allcall 0x01
  @outdrv 0x04

  defregister(:mode1, 0x00, :rw)
  defregister(:mode2, 0x01, :rw)
  defregister(:prescale, 0xFE, :rw)

  @type t :: %__MODULE__{conn: I2CDriver.t()}

  @impl Wafer.Conn
  def acquire(opts) when is_list(opts) do
    bus = Keyword.fetch!(opts, :bus)
    address = Keyword.get(opts, :address, 0x40)

    with {:ok, conn} <- I2CDriver.acquire(bus_name: bus, address: address, force: true) do
      {:ok, %__MODULE__{conn: conn}}
    end
  end

  @doc """
  Initialise the PCA9685 device and set all outputs to off.
  """
  @spec initialize(t(), frequency :: pos_integer(), oscillator_freq :: pos_integer()) ::
          {:ok, t()} | {:error, term()}
  def initialize(%__MODULE__{} = chip, freq_hz, oscillator_freq \\ 25_000_000)
      when is_valid_pwm_frequency(freq_hz) do
    with {:ok, chip} <- set_all_pwm(chip, 0, 0),
         {:ok, chip} <- write_mode2(chip, <<@outdrv>>),
         {:ok, chip} <- write_mode1(chip, <<@ai ||| @allcall>>),
         :ok <- :timer.sleep(5),
         {:ok, <<mode1>>} <- read_mode1(chip),
         {:ok, chip} <- write_mode1(chip, <<mode1 &&& Bitwise.bnot(@sleep)>>),
         :ok <- :timer.sleep(5) do
      set_pwm_frequency(chip, freq_hz, oscillator_freq)
    end
  end

  @doc """
  Set the PWM frequency in Hz.
  """
  @spec set_pwm_frequency(t(), pos_integer(), oscillator_freq :: pos_integer()) ::
          {:ok, t()} | {:error, term()}
  def set_pwm_frequency(chip, freq_hz, oscillator_freq \\ 25_000_000)

  def set_pwm_frequency(%__MODULE__{} = chip, freq_hz, oscillator_freq)
      when is_valid_pwm_frequency(freq_hz) do
    prescale = calculate_prescale(freq_hz, oscillator_freq)

    Logger.debug("Setting PWM frequency to #{freq_hz}hz")
    Logger.debug("Final pre-scale: #{prescale}")

    with {:ok, <<old_mode>>} <- read_mode1(chip),
         new_mode = (old_mode &&& 0x7F) ||| 0x10,
         {:ok, chip} <- write_mode1(chip, <<new_mode>>),
         {:ok, chip} <- write_prescale(chip, <<prescale>>),
         {:ok, chip} <- write_mode1(chip, <<old_mode>>),
         :ok <- :timer.sleep(5) do
      write_mode1(chip, <<old_mode ||| 0x80>>)
    end
  end

  def set_pwm_frequency(_chip, hz, _oscillator_freq),
    do: {:error, "#{hz}hz is outside available range."}

  @doc """
  Set a specific channel's PWM duty cycle.
  """
  @spec set_channel_pwm(t(), channel :: 0..15, on :: 0..4095, off :: 0..4095) ::
          {:ok, t()} | {:error, term()}
  def set_channel_pwm(%__MODULE__{} = chip, channel, on, off)
      when is_valid_channel(channel) and is_valid_duty_cycle(on) and is_valid_duty_cycle(off) do
    base_addr = @led0_on_l_addr + 4 * channel
    write_led_registers(chip, base_addr, on, off)
  end

  def set_channel_pwm(_chip, _channel, _on, _off),
    do: {:error, "Invalid channel or duty cycle."}

  @doc """
  Read a specific channel's PWM duty cycle.
  """
  @spec get_channel_pwm(t(), channel :: 0..15) ::
          {:ok, {on :: 0..4095, off :: 0..4095}} | {:error, term()}
  def get_channel_pwm(%__MODULE__{} = chip, channel) when is_valid_channel(channel) do
    base_addr = @led0_on_l_addr + 4 * channel
    read_led_registers(chip, base_addr)
  end

  def get_channel_pwm(_chip, _channel),
    do: {:error, "Invalid channel."}

  @doc """
  Set all channels to the same PWM duty cycle.
  """
  @spec set_all_pwm(t(), on :: 0..4095, off :: 0..4095) :: {:ok, t()} | {:error, term()}
  def set_all_pwm(%__MODULE__{} = chip, on, off)
      when is_valid_duty_cycle(on) and is_valid_duty_cycle(off) do
    write_led_registers(chip, @all_led_on_l_addr, on, off)
  end

  def set_all_pwm(_chip, _on, _off), do: {:error, "Invalid PWM values."}

  @doc """
  Read all channels' PWM duty cycles.
  """
  @spec get_all_pwm(t()) :: {:ok, list({on :: 0..4095, off :: 0..4095})} | {:error, term()}
  def get_all_pwm(%__MODULE__{} = chip) do
    results =
      Enum.reduce_while(0..15, [], fn channel, acc ->
        case get_channel_pwm(chip, channel) do
          {:ok, values} -> {:cont, [values | acc]}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case results do
      {:error, _} = error -> error
      channels -> {:ok, Enum.reverse(channels)}
    end
  end

  defp write_led_registers(%__MODULE__{} = chip, base_addr, on, off) do
    data = <<on &&& 0xFF, on >>> 8, off &&& 0xFF, off >>> 8>>
    Chip.write_register(chip, base_addr, data)
  end

  defp read_led_registers(%__MODULE__{} = chip, base_addr) do
    with {:ok, <<on_l, on_h, off_l, off_h>>} <- Chip.read_register(chip, base_addr, 4) do
      on = on_l ||| on_h <<< 8
      off = off_l ||| off_h <<< 8
      {:ok, {on, off}}
    end
  end

  defp calculate_prescale(freq_hz, oscillator_freq) do
    prescale = oscillator_freq / 4096.0 / freq_hz - 1
    round(prescale + 0.5)
  end
end
