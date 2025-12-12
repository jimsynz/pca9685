defmodule PCA9685 do
  @moduledoc """
  Driver for PCA9685 based 16 channel, 12 bit PWM driver connected over I2C.

  ## Usage

      # Start a device
      {:ok, pid} = PCA9685.acquire(bus: "i2c-1", address: 0x40)

      # With optional PWM frequency and output enable pin
      {:ok, pid} = PCA9685.acquire(bus: "i2c-1", address: 0x40, pwm_freq: 100, oe_pin: 17)

      # With a name for supervision
      {:ok, pid} = PCA9685.acquire(bus: "i2c-1", address: 0x40, name: MyPWM)

      # Control channels
      PCA9685.Device.channel(pid, 0, 0, 2048)
      PCA9685.Device.all(pid, 0, 4095)

      # Release when done
      PCA9685.release(pid)

  ## Supervision

  Add the device to your supervision tree:

      children = [
        {PCA9685.Device, bus: "i2c-1", address: 0x40, name: MyPWM}
      ]

  Then use the registered name:

      PCA9685.Device.channel(MyPWM, 0, 0, 2048)
  """

  @doc """
  Acquire a connection to a PCA9685 device.

  ## Options

    * `:bus` - (required) the I2C bus name, e.g. `"i2c-1"`
    * `:address` - (required) the I2C address, e.g. `0x40`
    * `:pwm_freq` - PWM frequency in Hz (default: 50, range: 24-1526)
    * `:oe_pin` - GPIO pin for output enable (optional)
    * `:name` - GenServer name for registration (optional)

  ## Examples

      {:ok, pid} = PCA9685.acquire(bus: "i2c-1", address: 0x40)
      {:ok, pid} = PCA9685.acquire(bus: "i2c-1", address: 0x40, name: MyPWM)
  """
  @spec acquire(keyword()) :: GenServer.on_start()
  def acquire(opts) when is_list(opts) do
    PCA9685.Device.start_link(opts)
  end

  @doc """
  Release a PCA9685 device connection.

  ## Examples

      :ok = PCA9685.release(pid)
      :ok = PCA9685.release(MyPWM)
  """
  @spec release(GenServer.server()) :: :ok
  def release(server) do
    GenServer.stop(server)
  end
end
