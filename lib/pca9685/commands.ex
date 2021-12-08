defmodule PCA9685.Commands do
  alias ElixirALE.I2C
  import PCA9685.Guards
  use Bitwise
  require Logger

  @moduledoc """
  Low-level functions for interacting directly with the PCA9685 device over I2C.
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

  # The I2C bus name
  @type bus :: String.t()
  # The I2C device address
  @type address :: 0..127
  # Allowed PWM update frequencies
  @type frequency :: 25..1526
  # Allowed 12-bit duty cycle value
  @type duty_cycle :: 0..4095
  # Allowed channel number
  @type channel :: 0..15

  @doc """
  Start a connection to the PCA9685 device over I2C.
  """
  @spec start_link(bus, address) :: {:ok, pid} | {:error, term}
  def start_link(bus, address), do: I2C.start_link(bus, address)

  @doc """
  Initialize the device and set all channels to off.
  """
  @spec initialize!(pid, frequency) :: :ok | {:error, term}
  def initialize!(pid, freq_hz) when is_valid_pwm_frequency(freq_hz) do
    with :ok <- set_all_pwm(pid, 0, 0),
         :ok <- I2C.write(pid, <<@mode2, @outdrv>>),
         :ok <- I2C.write(pid, <<@mode1, @allcall>>),
         :ok <- :timer.sleep(5),
         <<mode1>> <- I2C.write_read(pid, <<@mode1>>, 1),
         :ok <- I2C.write(pid, <<@mode1, mode1 &&& ~~~@sleep>>),
         :ok <- :timer.sleep(5),
         do: set_pwm_frequency(pid, freq_hz)
  end

  @doc false
  @spec release(pid) :: :ok
  def release(pid), do: I2C.release(pid)

  @doc """
  Set's the device's PWM update frequency to the provided number of Hz.

  Calculates it with a hard coded prescale value.
  """
  @spec set_pwm_frequency(pid, frequency) :: :ok | {:error, term}
  def set_pwm_frequency(pid, freq_hz) when is_valid_pwm_frequency(freq_hz) do
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

    with :ok <- I2C.write(pid, <<@mode1, new_mode>>),
         :ok <- I2C.write(pid, <<@prescale, prescale>>),
         :ok <- I2C.write(pid, <<@mode1, old_mode>>),
         :ok <- :timer.sleep(5),
         do: I2C.write(pid, <<@mode1, old_mode ||| 0x80>>)
  end

  def set_pwm_frequency(_pid, hz), do: {:error, "#{hz}hz is outside available range."}

  @doc """
  Set all 16 PWM outputs to a the same output value in a single operation.
  """
  @spec set_all_pwm(pid, duty_cycle, duty_cycle) :: :ok | {:error, term}
  def set_all_pwm(pid, on, off) when is_valid_duty_cycle(on) and is_valid_duty_cycle(off) do
    with :ok <- I2C.write(pid, <<@all_led_on_l, on &&& 0xFF>>),
         :ok <- I2C.write(pid, <<@all_led_on_h, on >>> 8>>),
         :ok <- I2C.write(pid, <<@all_led_off_l, off &&& 0xFF>>),
         do: I2C.write(pid, <<@all_led_off_h, off >>> 8>>)
  end

  def set_all_pwm(_pid, _on, _off), do: {:error, "Invalid PWM values."}

  @doc """
  Set a specific PWM output to the provided duty cycle.
  """
  @spec set_one_pwm(pid, channel, duty_cycle, duty_cycle) :: :ok | {:error, term}
  def set_one_pwm(pid, channel, on, off)
      when is_valid_channel(channel) and is_valid_duty_cycle(on) and is_valid_duty_cycle(off) do
    with :ok <- I2C.write(pid, <<@led0_on_l + 4 * channel, on &&& 0xFF>>),
         :ok <- I2C.write(pid, <<@led0_on_h + 4 * channel, on >>> 8>>),
         :ok <- I2C.write(pid, <<@led0_off_l + 4 * channel, off &&& 0xFF>>),
         do: I2C.write(pid, <<@led0_off_h + 4 * channel, off >>> 8>>)
  end

  def set_one_pwm(_pid, _channel, _on, _off), do: {:error, "Invalid channel or duty cycle."}
end
