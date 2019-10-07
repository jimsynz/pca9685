import Config

config :pca9685,
  devices: [
    %{bus: "i2c-1", address: 0x42}
  ]
