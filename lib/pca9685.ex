defmodule PCA9685 do
  @moduledoc """
  Driver for PCA9685 based 16 channel, 12 bit PWM driver connected over I2C.


  ## Usage

  Add your device to your config like so:

      config :pca9685,
        devices: [%{bus: "i2c-1", address: 0x40}]

  The properties `bus` and `address` are mandatory.  You can optionally provide
  `pwm_freq` which is the output frequency you'd like to set (in Hz) and
  `oe_pin` which is the GPIO pin that you want to use for the output-enable
  function.  Remember that the OE pin is expecting to be driven high to +5V, so
  won't work on a Raspberry Pi without a level shifter of some kind.

  Your devices will be reset and you will be able to drive the outputs with your
  specified output frequency and duty cycle.
  """

  @doc """
  Connect to a PCA9685 device.
  """
  def connect(config),
    do: Supervisor.start_child(PCA9685.Supervisor, {PCA9685.Device, config})

  @doc """
  Disconnect a PCA9685 device.
  """
  def disconnect(device_name) do
    case Supervisor.terminate_child(PCA9685.Supervisor, {PCA9685.Device, device_name}) do
      :ok -> Supervisor.delete_child(PCA9685.Supervisor, {PCA9685.Device, device_name})
      {:error, reason} -> {:error, reason}
    end
  end
end
