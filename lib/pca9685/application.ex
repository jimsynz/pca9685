defmodule PCA9685.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: PCA9685.Registry}
    ]

    devices =
      :pca9685
      |> Application.get_env(:devices, [])
      |> Enum.map(&{PCA9685.Device, &1})

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PCA9685.Supervisor]
    Supervisor.start_link(children ++ devices, opts)
  end
end
