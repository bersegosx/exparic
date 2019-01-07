# Exparic

[![Version][shield-version]][hexpm]
[![License][shield-license]][hexpm]

> Web parser with yaml and css rules

## Installation

The package can be installed by adding `exparic` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exparic, "~> 0.1.2"}
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

## Examples

### Weather parser (https://pogoda.e1.ru/)

```yaml
parser:
  name: e1_pogoda
  init:
    url: "https://pogoda.e1.ru/"
    step: detail_page

  steps:
    - name: detail_page
      fields:
        - temperature:
            selector: css
            value: "body > div.wrapper > div.content-holder.cols2 > div > div > div.today-panel.js-today-panel > div > div > div.today-panel__info__main > div.today-panel__info__main__item._first > div > span.value > span.value__main::text"
            filters:
              - strip
              - "replace::−,-"
              - int

        - temperature_feeling_as:
            selector: css
            value: "body > div.wrapper > div.content-holder.cols2 > div > div > div.today-panel.js-today-panel > div > div > div.today-panel__info__main > div.today-panel__info__main__item._first > div > span.value-feels_like > span.value-feels_like__number::text"
            filters:
              - strip
              - "index::0,3"
              - "replace::−,-"
              - "replace::°,"
              - int

        - atm_pressure:
            selector: css
            value: "body > div.wrapper > div.content-holder.cols2 > div > div > div.today-panel.js-today-panel > div > div > div.today-panel__info__main > div.today-panel__info__main__item._first > dl:nth-child(3) > dt::text"
            filters:
              - strip

        - humidity:
            selector: css
            value: "body > div.wrapper > div.content-holder.cols2 > div > div > div.today-panel.js-today-panel > div > div > div.today-panel__info__main > div.today-panel__info__main__item._first > dl:nth-child(4) > dt::text"
            filters:
              - strip
```

Will be parsed into:

```elixir
%{
  "atm_pressure" => "735 мм",
  "humidity" => "82%",
  "temperature" => -14,
  "temperature_feeling_as" => -18
}
```

[shield-version]:   https://img.shields.io/hexpm/v/exparic.svg
[shield-license]:   https://img.shields.io/hexpm/l/exparic.svg
[hexpm]:            https://hex.pm/packages/exparic
