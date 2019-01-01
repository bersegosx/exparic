use Mix.Config

config :logger, :console,
  metadata: [:worker, :coordinator, :step],
  format: "\n##### $time [$level] $metadata$message\n"
