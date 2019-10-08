defmodule PCA9685.Guards do
  @moduledoc false

  defguard is_valid_channel(channel) when is_integer(channel) and channel >= 0 and channel < 16

  defguard is_valid_duty_cycle(duty_cycle)
           when is_integer(duty_cycle) and duty_cycle >= 0 and duty_cycle < 4096

  defguard is_valid_pwm_frequency(pwm_frequency)
           when is_integer(pwm_frequency) and pwm_frequency >= 24 and pwm_frequency <= 1526
end
