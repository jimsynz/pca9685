defmodule PCA9685.OutputEnable do
  alias ElixirALE.GPIO

  @moduledoc """
  Handles twiddling the output-enable pin via GPIO.
  """

  @doc """
  Connect to a specific GPIO pin as an output.
  """
  @spec start_link(non_neg_integer) :: :ok | {:error, term}
  def start_link(pin), do: GPIO.start_link(pin, :output)

  @doc false
  def release(pid), do: GPIO.release(pid)

  @doc """
  Set the output enable pin low.
  """
  @spec enable(pid) :: :ok | {:error, term}
  def enable(pid), do: GPIO.write(pid, 0)

  @doc """
  Set the output enable pin high.
  """
  @spec disable(pid) :: :ok | {:error, term}
  def disable(pid), do: GPIO.write(pid, 1)
end
