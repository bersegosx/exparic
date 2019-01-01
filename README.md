# Exparic

[![Version][shield-version]][hexpm]
[![License][shield-license]][hexpm]

> Web parser with yaml and css rules

## Installation

The package can be installed by adding `exparic` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exparic, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
# run parser and wait for a result
iex(1)> r = Exparic.parse(Path.expand("./site_config.yaml"))

# or every parsed result will be sent via message
iex(1)> Exparic.parse_single(Path.expand("./site_config.yaml"), self())
```

[shield-version]:   https://img.shields.io/hexpm/v/exparic.svg
[shield-license]:   https://img.shields.io/hexpm/l/exparic.svg
[hexpm]:            https://hex.pm/packages/exparic
