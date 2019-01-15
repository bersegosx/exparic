defmodule Exparic do
  @moduledoc """
  Parser for html
  """

  def parse(path, worker_config \\ %{}) do
    start_parser(path, :gather, worker_config)
  end

  def parse_single(path, pid, worker_config \\ %{}) do
    start_parser(path, :single, worker_config, pid)
  end

  defp start_parser(path, mode, worker_config, pid \\ nil) do
    if File.exists?(path) do
      config = load(path)
      {:ok, parser_pid} = Exparic.Coordinator.start_link(config, mode, worker_config, pid)
      result = Exparic.Coordinator.get_result_sync(parser_pid)
      :ok = GenServer.stop(parser_pid)

      result
    else
      {:error, "File doesn't exist"}
    end
  end

  def load(path) do
    {:ok, parser_config} = YamlElixir.read_from_file(path)
    parser_config
  end
end
