import Config

# config :pca9685,
#   devices: [
#     %{bus: "i2c-1", address: 0x42}
#   ]

config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://harton.dev/james/pca9685",
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  version_tag_prefix: "v"
