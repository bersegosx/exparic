defmodule Exparic.Coordinator do
  use GenServer

  require Logger

  alias __MODULE__

  defmodule Step do
    defstruct [url: nil, name: nil, target: nil, result: nil]
  end

  defstruct [
    config: %{}, queue: nil, result: [], ack_count: 0,
    start_time: nil, end_time: nil,
    task_waiters: [],
    result_waiter: nil,
    mode: :gather, receiver_pid: nil,
    worker_config: %{},
    worker_sup: nil,
    active_tasks: %{},
    workers: %{}
  ]

  @default_worker_config %{
    number: System.schedulers(),
    for_limit: false
  }

  def start_link(config, mode \\ :gather, worker_config \\ %{}, receiver_pid \\ nil) do
    GenServer.start_link(__MODULE__, [config, mode, worker_config, receiver_pid])
  end

  def call(pid, what) do
    GenServer.call(pid, what)
  end

  def get_task_sync(pid) do
    GenServer.call(pid, :get_task, :infinity)
  end

  def task_done(pid) do
    GenServer.cast(pid, :task_done)
  end

  def get_result_sync(pid) do
    GenServer.call(pid, :get_result, :infinity)
  end

  def init([config, mode, worker_config, receiver_pid]) do
    Logger.metadata(coordinator: config["parser"]["name"])
    queue = init_queue(config)
    queue_lenth = :queue.len(queue)

    Logger.debug("Queue inited, tasks: #{queue_lenth}")
    {:ok, %Coordinator{config: config, queue: queue, ack_count: queue_lenth,
                       worker_config: Map.merge(@default_worker_config, worker_config),
                       start_time: System.monotonic_time(:millisecond),
                       mode: mode, receiver_pid: receiver_pid}, 0}
  end

  def handle_info(:timeout, %{worker_config: %{number: workers_num}} = state) do
    Logger.debug("Mode: #{inspect state.mode}")
    Logger.debug("Spawns new workes: #{workers_num}")

    {:ok, worker_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)
    Logger.debug("Worker supervisor started: #{inspect worker_sup}")

    workers =
      Enum.map(1..workers_num, fn idx ->
        {:ok, child} = DynamicSupervisor.start_child(worker_sup,
          {Exparic.Worker, [self(), state.config, idx, state.worker_config]}
        )
        child
      end)

    Logger.debug("Workers were spawned: #{inspect workers}")
    {:noreply, %{state| worker_sup: worker_sup}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :shutdown}, state) do
    {:noreply, state}
  end

  def handle_info(
    {:DOWN, ref, :process, pid, reason},
    %{workers: workers, active_tasks: active_tasks} = state) do

    Logger.warn("worker down, reason: #{inspect reason}, #{inspect workers}, #{inspect active_tasks}")
    {_, workers} = Map.pop(workers, pid)
    {task, active_tasks} = Map.pop(active_tasks, ref)

    GenServer.cast(self(), {:add_task, task})

    {:noreply, %{state| workers: workers, active_tasks: active_tasks}}
  end

  def handle_call(:get_task, client, state) do
     case :queue.out(state.queue) do
       {:empty, _} ->
         {:noreply, %{state| task_waiters: [client|state.task_waiters]}}

       {{:value, v}, q} ->
         {client_pid, _} = client
         {new_workers, active_tasks} = give_task(client_pid, v, state)
         {:reply, v, %{state| queue: q, workers: new_workers, active_tasks: active_tasks}}
     end
  end

  def handle_call({:task_done, value}, _from,
    %{result: result, ack_count: ack_count, mode: :gather} = state) do
    if ack_count == 1 do
      GenServer.cast(self(), :work_done)
    end
    {:reply, :thanks, %{state| result: [value|result], ack_count: ack_count - 1}}
  end

  def handle_call({:task_done, value}, _from,
    %{ack_count: ack_count, mode: :single, receiver_pid: pid} = state) do
    send(pid, value)

    if ack_count == 1 do
      GenServer.cast(self(), :work_done)
    end
    {:reply, :thanks, %{state| ack_count: ack_count - 1}}
  end

  def handle_call(:get_result, client, state) do
    {:noreply, %{state| result_waiter: client}}
  end

  def handle_cast({:add_task, value}, %{task_waiters: tw} = state) when length(tw) > 0 do
    Logger.debug(":add_task waiters, #{inspect {value, tw}}")

    {{client_pid, _} = client, task_waiters} = List.pop_at(tw, -1)
    {new_workers, active_tasks} = give_task(client_pid, value, state)

    GenServer.reply(client, value)
    {:noreply, %{state| task_waiters: task_waiters, ack_count: state.ack_count + 1,
                        workers: new_workers, active_tasks: active_tasks}}
  end

  def handle_cast({:add_task, value}, state) do
    Logger.debug(":add_task no_waitets, #{inspect value}")
    new_q = :queue.in_r(value, state.queue)
    {:noreply, %{state| queue: new_q, ack_count: state.ack_count + 1}}
  end

  def handle_cast(:task_done, state) do
    if state.ack_count == 1 do
      GenServer.cast(self(), :work_done)
    end
    {:noreply, %{state| ack_count: state.ack_count - 1}}
  end

  def handle_cast(:work_done, state) do
    spawn(fn ->
      Enum.each(state.task_waiters, fn w ->
        GenServer.reply(w, :nil)
      end)
    end)
    :ok = Supervisor.stop(state.worker_sup)

    end_time = System.monotonic_time(:millisecond)
    Logger.debug("Work has done\n#{inspect state.result, pretty: true}")
    Logger.debug("Total time: #{end_time - state.start_time}")
    Logger.debug("Total records: #{length(state.result)}")

    if state.result_waiter do
      GenServer.reply(state.result_waiter, state.result)
    end

    {:noreply, %{state| end_time: end_time}}
  end

  defp give_task(worker_pid, task, %{workers: workers, active_tasks: active_tasks}) do
    {ref, new_workers} =
      if Map.has_key?(workers, worker_pid) do
        {workers[worker_pid], workers}
      else
        ref = Process.monitor(worker_pid)
        {ref, Map.put(workers, worker_pid, ref)}
      end

    {new_workers, Map.put(active_tasks, ref, task)}
  end

  @spec init_queue(map()) :: tuple()
  defp init_queue(config) do
    %{"parser" => %{"name" => target,
                    "init" => init_data}} = config
    steps =
      if Map.has_key?(init_data, "urls") do
        for url <- init_data["urls"] do
          %Step{url: url, name: init_data["step"], target: target}
        end
      else
        [%Step{url: init_data["url"], name: init_data["step"], target: target}]
      end

    Enum.reduce(steps, :queue.new(), fn (s, q) ->
      :queue.in_r(s, q)
    end)
  end
end
