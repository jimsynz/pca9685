# PCA9685

Driver for PCA9685 based 16 channel, 12 bit PWM driver connected over I2C.

## Usage

Add your device to your config like so:

```elixir
config :pca9685,
  devices: [%{bus: "i2c-1", address: 0x40}]
```

The properties `bus` and `address` are mandatory.  You can optionally provide
`pwm_freq` which is the output frequency you'd like to set (in Hz) and
`oe_pin` which is the GPIO pin that you want to use for the output-enable
function.  Remember that the OE pin is expecting to be driven high to +5V, so
won't work on a Raspberry Pi without a level shifter of some kind.

Your devices will be reset and you will be able to drive the outputs with your
specified output frequency and duty cycle.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pca9685` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pca9685, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/pca9685](https://hexdocs.pm/pca9685).

