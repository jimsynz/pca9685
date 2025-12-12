Application.ensure_all_started(:mimic)

Mimic.copy(PCA9685.Chip)
Mimic.copy(Wafer.Driver.Circuits.GPIO)

ExUnit.start()
