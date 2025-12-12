defmodule PCA9685.DeviceTest do
  use ExUnit.Case, async: false
  use Mimic

  alias PCA9685.{Chip, Device}

  setup :set_mimic_global
  setup :verify_on_exit!

  describe "pulse_width/3" do
    setup do
      chip = %Chip{conn: %Wafer.Driver.Fake{}}

      Chip
      |> stub(:acquire, fn _opts -> {:ok, chip} end)
      |> stub(:initialize, fn chip, _freq, _osc -> {:ok, chip} end)

      {:ok, chip: chip}
    end

    test "converts microseconds to PWM ticks at 50Hz", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 50)

      Chip
      |> expect(:set_channel_pwm, fn ^chip, 0, 0, ticks ->
        # At 50Hz with 25MHz oscillator:
        # prescale = round(25_000_000 / 4096 / 50 - 1 + 0.5) = 122
        # pulselength_us = 1_000_000 * 123 / 25_000_000 = 4.92µs per tick
        # 1500µs / 4.92 = 304.878... rounds to 305
        assert ticks == 305
        {:ok, chip}
      end)

      assert :ok = Device.pulse_width(pid, 0, 1500)

      # Give the cast time to process
      :sys.get_state(pid)
    end

    test "converts 1000µs (servo min) correctly", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 50)

      Chip
      |> expect(:set_channel_pwm, fn ^chip, 0, 0, ticks ->
        # 1000µs / 4.92 = 203.25... rounds to 203
        assert ticks == 203
        {:ok, chip}
      end)

      assert :ok = Device.pulse_width(pid, 0, 1000)
      :sys.get_state(pid)
    end

    test "converts 2000µs (servo max) correctly", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 50)

      Chip
      |> expect(:set_channel_pwm, fn ^chip, 0, 0, ticks ->
        # 2000µs / 4.92 = 406.50... rounds to 407
        assert ticks == 407
        {:ok, chip}
      end)

      assert :ok = Device.pulse_width(pid, 0, 2000)
      :sys.get_state(pid)
    end

    test "respects custom oscillator frequency", %{chip: chip} do
      # Using a 26MHz oscillator instead of 25MHz
      {:ok, pid} =
        Device.start_link(
          bus: "i2c-1",
          address: 0x40,
          pwm_freq: 50,
          oscillator_freq: 26_000_000
        )

      Chip
      |> expect(:set_channel_pwm, fn ^chip, 0, 0, ticks ->
        # prescale = round(26_000_000 / 4096 / 50 - 1 + 0.5) = 126
        # pulselength_us = 1_000_000 * 127 / 26_000_000 = 4.8846µs per tick
        # 1500µs / 4.8846 = 307.08... rounds to 307
        assert ticks == 307
        {:ok, chip}
      end)

      assert :ok = Device.pulse_width(pid, 0, 1500)
      :sys.get_state(pid)
    end

    test "works with different PWM frequencies", %{chip: chip} do
      # 60Hz is common for some servo applications
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 60)

      Chip
      |> expect(:set_channel_pwm, fn ^chip, 0, 0, ticks ->
        # prescale = round(25_000_000 / 4096 / 60 - 1 + 0.5) = 101
        # pulselength_us = 1_000_000 * 102 / 25_000_000 = 4.08µs per tick
        # 1500µs / 4.08 = 367.6... rounds to 368
        assert ticks == 368
        {:ok, chip}
      end)

      assert :ok = Device.pulse_width(pid, 0, 1500)
      :sys.get_state(pid)
    end

    test "clamps ticks to maximum of 4095", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 50)

      Chip
      |> expect(:set_channel_pwm, fn ^chip, 0, 0, ticks ->
        # Very large pulse width should be clamped to 4095
        assert ticks == 4095
        {:ok, chip}
      end)

      # 100,000µs would be way more than 4095 ticks
      assert :ok = Device.pulse_width(pid, 0, 100_000)
      :sys.get_state(pid)
    end

    test "works on all channels 0-15", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 50)

      for channel <- 0..15 do
        Chip
        |> expect(:set_channel_pwm, fn ^chip, ^channel, 0, _ticks ->
          {:ok, chip}
        end)

        assert :ok = Device.pulse_width(pid, channel, 1500)
        :sys.get_state(pid)
      end
    end

    test "returns error for invalid channel" do
      assert {:error, _} = Device.pulse_width(self(), 16, 1500)
      assert {:error, _} = Device.pulse_width(self(), -1, 1500)
    end

    test "returns error for invalid pulse width" do
      assert {:error, _} = Device.pulse_width(self(), 0, 0)
      assert {:error, _} = Device.pulse_width(self(), 0, -100)
    end
  end

  describe "get_channel/2" do
    setup do
      chip = %Chip{conn: %Wafer.Driver.Fake{}}

      Chip
      |> stub(:acquire, fn _opts -> {:ok, chip} end)
      |> stub(:initialize, fn chip, _freq, _osc -> {:ok, chip} end)

      {:ok, chip: chip}
    end

    test "reads channel PWM values", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40)

      Chip
      |> expect(:get_channel_pwm, fn ^chip, 0 -> {:ok, {0, 305}} end)

      assert {:ok, {0, 305}} = Device.get_channel(pid, 0)
    end

    test "returns error for invalid channel" do
      assert {:error, _} = Device.get_channel(self(), 16)
      assert {:error, _} = Device.get_channel(self(), -1)
    end
  end

  describe "get_all/1" do
    setup do
      chip = %Chip{conn: %Wafer.Driver.Fake{}}

      Chip
      |> stub(:acquire, fn _opts -> {:ok, chip} end)
      |> stub(:initialize, fn chip, _freq, _osc -> {:ok, chip} end)

      {:ok, chip: chip}
    end

    test "reads all channel PWM values", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40)

      expected = for _ <- 0..15, do: {0, 305}

      Chip
      |> expect(:get_all_pwm, fn ^chip -> {:ok, expected} end)

      assert {:ok, ^expected} = Device.get_all(pid)
    end
  end

  describe "get_pulse_width/2" do
    setup do
      chip = %Chip{conn: %Wafer.Driver.Fake{}}

      Chip
      |> stub(:acquire, fn _opts -> {:ok, chip} end)
      |> stub(:initialize, fn chip, _freq, _osc -> {:ok, chip} end)

      {:ok, chip: chip}
    end

    test "converts ticks back to microseconds", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 50)

      Chip
      |> expect(:get_channel_pwm, fn ^chip, 0 -> {:ok, {0, 305}} end)

      # 305 ticks * 4.92µs/tick = 1500.6µs, rounds to 1501
      assert {:ok, microseconds} = Device.get_pulse_width(pid, 0)
      assert microseconds in 1499..1501
    end

    test "round-trips with pulse_width/3", %{chip: chip} do
      {:ok, pid} = Device.start_link(bus: "i2c-1", address: 0x40, pwm_freq: 50)

      # Set 1500µs, which becomes 305 ticks
      Chip
      |> expect(:set_channel_pwm, fn ^chip, 0, 0, 305 -> {:ok, chip} end)

      Device.pulse_width(pid, 0, 1500)
      :sys.get_state(pid)

      # Read back should give approximately 1500µs
      Chip
      |> expect(:get_channel_pwm, fn ^chip, 0 -> {:ok, {0, 305}} end)

      assert {:ok, microseconds} = Device.get_pulse_width(pid, 0)
      assert microseconds in 1499..1501
    end

    test "returns error for invalid channel" do
      assert {:error, _} = Device.get_pulse_width(self(), 16)
      assert {:error, _} = Device.get_pulse_width(self(), -1)
    end
  end

  describe "oscillator_freq configuration" do
    test "defaults to 25MHz" do
      chip = %Chip{conn: %Wafer.Driver.Fake{}}

      Chip
      |> stub(:acquire, fn _opts -> {:ok, chip} end)

      Chip
      |> expect(:initialize, fn ^chip, 50, 25_000_000 ->
        {:ok, chip}
      end)

      {:ok, _pid} = Device.start_link(bus: "i2c-1", address: 0x40)
    end

    test "can be configured" do
      chip = %Chip{conn: %Wafer.Driver.Fake{}}

      Chip
      |> stub(:acquire, fn _opts -> {:ok, chip} end)

      Chip
      |> expect(:initialize, fn ^chip, 50, 27_000_000 ->
        {:ok, chip}
      end)

      {:ok, _pid} =
        Device.start_link(
          bus: "i2c-1",
          address: 0x40,
          oscillator_freq: 27_000_000
        )
    end
  end
end
