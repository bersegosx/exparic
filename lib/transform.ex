defmodule Exparic.Transform do
  @moduledoc """
  Transformation functions for data cleanup
  """

  def apply_rules(nil, _), do: nil
  def apply_rules(v, nil), do: v
  def apply_rules(v, filters) do
    Enum.reduce(filters, v, fn (fl, acc) ->
      transform(fl, acc)
    end)
  end

  def transform("strip", v) when is_list(v), do: Enum.map(v, & transform("strip", &1))
  def transform("strip", v), do: String.trim(v)
  def transform("int", v) do
    {intVal, _} = Integer.parse(v)
    intVal
  end
  def transform("replace::" <> attrs, v) do
    [patterns, replacement] = String.split(attrs, ",", parts: 2)
    String.replace(v, String.graphemes(patterns), replacement)
  end
  def transform("split::" <> idx, v) do
    parts = String.split(v, " ")
    if length(parts) > 1 do
      Enum.at(parts, transform("int", idx))
    else
      hd(parts)
    end
  end
  def transform("index::" <> attrs, v) do
    [st_idx, end_idx] =
      String.split(attrs, ",", parts: 2)
      |> Enum.map(& transform("int", &1))

    range = st_idx..end_idx
    if is_binary(v) do
      String.slice(v, range)
    else
      Enum.slice(v, range)
    end
  end
  def transform(_, v), do: v
end
