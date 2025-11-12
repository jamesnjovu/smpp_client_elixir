defmodule Sms.SmppConfigLoader do
  use GenServer
  require Logger

  @refresh_interval 600_000 # 10 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
     # Start the DynamicSupervisor if it doesn't exist yet
    case Process.whereis(Sms.SmppDynamicSupervisor) do
      nil ->
        DynamicSupervisor.start_link(name: Sms.SmppDynamicSupervisor, strategy: :one_for_one)
      _ -> :ok
    end

    Process.send_after(self(), :refresh_configs, 0)
    {:ok, %{configs: []}}
  end

  def handle_info(:refresh_configs, _state) do
    configs = load_smpp_config()

    # Convert regex strings to actual regex patterns
    configs = Enum.map(configs, fn config ->
      regex_string = config.mobile_regex || ".*"

      # Safely compile regex
      regex = case Regex.compile(regex_string) do
        {:ok, regex} -> regex
        {:error, _} ->
          Logger.error("Invalid regex pattern: #{regex_string}")
          ~r/.*/ # Default match-all regex
      end

      # Add default values for max_single_length and max_multipart_length if not present
      config
      |> Map.put(:mobile_regex, regex)
      |> Map.put_new(:max_single_length, 160)
      |> Map.put_new(:max_multipart_length, 153)
    end)

    # Update or start new servers
    Enum.each(configs, fn config ->
      case Registry.lookup(Sms.SmppRegistry, config.id) do
        [] ->
          start_smpp_server(config)

        [{pid, _}] ->
          GenServer.cast(pid, {:update_config, config})
      end
    end)

    Process.send_after(self(), :refresh_configs, @refresh_interval)
    {:noreply, %{configs: configs}}
  end

  def handle_call({:get_matching_config, mobile_number}, _from, state) do
    matching_config = Enum.find(state.configs, fn config ->

      # Check if mobile_regex is already a Regex
      regex = case config.mobile_regex do
        %Regex{} ->
          config.mobile_regex

        regex_string when is_binary(regex_string) ->
          # Convert string to regex if needed
          case Regex.compile(regex_string) do
            {:ok, regex} -> regex
            {:error, _} -> ~r/.*/
          end

        _ ->
          # Default regex
          ~r/.*/
      end

      Regex.match?(regex, mobile_number)
    end)

    {:reply, matching_config, state}
  end

  defp start_smpp_server(config) do
    Logger.info("Starting SMPP server for #{config.id}")
    case DynamicSupervisor.start_child(
      Sms.SmppDynamicSupervisor,
      {Sms.SmppServer, config}
    ) do
      {:ok, pid} ->
        Logger.info("Started SMPP server #{config.id}: #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start SMPP server for #{config.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_matching_config(mobile_number) do
    GenServer.call(__MODULE__, {:get_matching_config, mobile_number})
  end

  defp load_smpp_config do
    [
      %{
        id: 2,
        host: "messaging.airtel.co.zm",
        mobile_regex: "^(26097|26077|26096|26076|26075|26095)",
        password: "pr0b4s3",
        port: 9001,
        service_name: "AIRTEL",
        system_id: "probase",
        status: "A",
        inserted_at: ~N[2025-03-07 12:10:13],
        updated_at: ~N[2025-03-07 12:10:13]
      },
    ]
  end

end
