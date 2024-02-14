# PCA9685

[![Build Status](https://drone.harton.dev/api/badges/james/pca9685/status.svg)](https://drone.harton.dev/james/pca9685)
[![Hex.pm](https://img.shields.io/hexpm/v/pca9685.svg)](https://hex.pm/packages/pca9685)
[![Hippocratic License HL3-FULL](https://img.shields.io/static/v1?label=Hippocratic%20License&message=HL3-FULL&labelColor=5e2751&color=bc8c3d)](https://firstdonoharm.dev/version/3/0/full.html)

Driver for PCA9685 based 16 channel, 12 bit PWM driver connected over I2C.

## Usage

Add your device to your config like so:

```elixir
config :pca9685,
  devices: [%{bus: "i2c-1", address: 0x40}]
```

The properties `bus` and `address` are mandatory. You can optionally provide
`pwm_freq` which is the output frequency you'd like to set (in Hz) and
`oe_pin` which is the GPIO pin that you want to use for the output-enable
function. Remember that the OE pin is expecting to be driven high to +5V, so
won't work on a Raspberry Pi without a level shifter of some kind.

Your devices will be reset and you will be able to drive the outputs with your
specified output frequency and duty cycle.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pca9685` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pca9685, "~> 1.0.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/pca9685](https://hexdocs.pm/pca9685).

## Github Mirror

This repository is mirrored [on Github](https://github.com/jimsynz/pca9685)
from it's primary location [on my Forejo instance](https://harton.dev/james/pca9685).
Feel free to raise issues and open PRs on Github.

## License

This software is licensed under the terms of the
[HL3-FULL](https://firstdonoharm.dev), see the `LICENSE.md` file included with
this package for the terms.

This license actively proscribes this software being used by and for some
industries, countries and activities. If your usage of this software doesn't
comply with the terms of this license, then [contact me](mailto:james@harton.nz)
with the details of your use-case to organise the purchase of a license - the
cost of which may include a donation to a suitable charity or NGO.
