defmodule Exparic.Worker do
  use GenServer

  require Logger

  alias __MODULE__
  alias Exparic.{Coordinator, Coordinator.Step, Transform}

  @default_opts %{
    for_limit: false
  }

  defstruct [
    coordinator_pid: nil,
    config: %{}, step: nil, worker_num: nil, is_part: false,
    opts: %{}
  ]

  def start_link([coordinator_pid, config, worker_num, opts]) do
    GenServer.start_link(__MODULE__, {coordinator_pid, config, worker_num, opts})
  end

  def init({coordinator_pid, config, worker_num, opts}) do
    Logger.metadata(worker: worker_num)
    Logger.debug("Started")

    {:ok, %Worker{coordinator_pid: coordinator_pid,
                  config: config, worker_num: worker_num,
                  opts: Map.merge(@default_opts, opts)}, 0}
  end

  def handle_info(:timeout, %{step: nil} = state) do
    step = Coordinator.get_task_sync(state.coordinator_pid)
    Logger.debug("Got new task, #{inspect step}")

    if step do
      {:noreply, %{state| step: step}, 0}
    else
      Logger.debug("no more work")
      {:noreply, state}
    end
  end

  def handle_info(:timeout, %{step: step, coordinator_pid: coordinator_pid} = state) do
    Logger.metadata(step: step.name)

    {value, is_partial_step} = start_parsing(state)
    if is_partial_step do
      Coordinator.task_done(coordinator_pid)
    else
      :thanks = Coordinator.call(coordinator_pid, {:task_done, value})
    end

    Logger.metadata(step: nil)
    {:noreply, %{state| step: nil}, 0}
  end

  def start_parsing(state) do
    step_config = get_step_config(state)

    result =
      fetch_html(state)
      |> extract_step_fields(step_config, state)

    Logger.debug("Result: #{inspect(result)}")

    result
  end

  def fetch_html(%{step: step, config: config}) do
    url =
      if String.starts_with?(step.url, "/") do
        %{"parser" => %{"init" => %{"url" => base_url}}} = config
        URI.merge(base_url, step.url) |> URI.to_string
      else
        step.url
      end

    Logger.debug("fetching url: #{url}")

    headers = [Accept: "text/html",
               "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10)"]
    options = [follow_redirect: true]

    {:ok, %HTTPoison.Response{body: body, status_code: 200}} =
      HTTPoison.get(url, headers, options)
    body
  end

  def get_step_config(%{config: config, step: %{name: step_name}}) do
    config["parser"]["steps"]
    |> Enum.filter(& &1["name"] == step_name)
    |> hd
    |> Map.get("fields")
  end

  @spec extract_step_fields(String.t, map(), Worker) :: {any(), boolean()}
  def extract_step_fields(html, step_fields, state) do
    {result, {opts, is_partial}} =
      Enum.map_reduce(step_fields, {%{}, false}, fn (field, {opts, partial_acc}) ->
        field_name = Map.keys(field) |> hd
        params = field[field_name]
        {result, is_partial} = extract_field(html, params, state)

        new_opts =
          if Map.has_key?(params, "add_to_queue") do
            Map.put(opts, field_name, %{"add_to_queue" => params["add_to_queue"]})
          else
            opts
          end

        {{field_name, result}, {new_opts, partial_acc or is_partial}}
      end)

    result =
      Enum.into(result, %{})
      |> Map.merge(state.step.result || %{})

    if opts do
      enque_task(result, opts, state)
    end

    {result, is_partial}
  end

  @spec extract_field(String.t, map(), Worker) :: {any(), boolean()}
  def extract_field(html, %{"for" => params},
    %{opts: %{for_limit: for_limit}} = state)
  do
    %{"init" => %{"value" => selector},
                  "cycle" => %{"fields" => fields}} = params

    parts = Floki.find(html, selector)
    parts = if for_limit, do: Enum.slice(parts, 0, for_limit), else: parts

    {values, is_partial} =
      Enum.map_reduce(parts, false, fn (html_part, acc_is_partial) ->
        {value, is_partial} = extract_step_fields(html_part, fields, state)
        {value, acc_is_partial or is_partial}
      end)

    {Enum.reverse(values), is_partial}
  end

  @spec extract_field(String.t, map(), Worker) :: {any(), boolean()}
  def extract_field(html, rules, _state) do
    {selector_value, attr} = parse_selector_value(rules["value"])
    filters = Map.get(rules, "filters", [])
    keep_raw = "row" in Map.get(rules, "options", [])
    attr = Map.get(rules, "value_attr", attr)

    result =
      Floki.find(html, selector_value)
      |> extract_attr(attr, keep_raw)
      |> Transform.apply_rules(filters)

    is_partial_step =
      if Map.has_key?(rules, "add_to_queue") do
        Map.get(rules["add_to_queue"], "nested")
      else
        false
      end

    {result, is_partial_step}
  end

  def enque_task(step_result, step_opts, state) do
    Map.keys(step_opts)
    |> Enum.each(fn k ->
      opts = step_opts[k]
      %{"add_to_queue" => %{"step" => step_name}} = opts
      target = state.config["parser"]["name"]

      step = %Step{url: step_result[k], name: step_name, target: target}
      step =
        if Map.get(opts["add_to_queue"], "nested", false) do
          %{step| result: step_result}
        else
          step
        end

      Coordinator.call(state.coordinator_pid, {:add_task, step})
    end)
  end

  def parse_selector_value(v) do
    if String.ends_with?(v, ["::text", "::html"]) do
      String.split(v, "::", parts: 2) |> List.to_tuple
    else
      {v, ""}
    end
  end

  def extract_attr([], _, _), do: nil
  def extract_attr(v, attr, _) when attr in ["href", "src", "content"] do
    Floki.attribute(v, attr) |> hd
  end
  def extract_attr(v, "html", _), do: Floki.raw_html(v, encode: true)
  def extract_attr(v, attr, keep) when attr in ["", "text"] do
    case v do
      [{_, _, _}] ->
        if keep do
          Floki.text(v)
        else
          text_first(v)
        end

      {_, _, _} ->
        if keep do
          Floki.text(v)
        else
          text_first(v)
        end

      [_|_] ->
          Enum.map(v, &Floki.text/1)
    end
  end

  def text_first([{_tag, _attrs, [v|_rest]}]), do: v
end
