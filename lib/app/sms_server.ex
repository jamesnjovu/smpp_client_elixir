defmodule Sms.SmppServer do
  use GenServer
  require Logger
  alias SMPPEX.Pdu
  alias SMPPEX.Pdu.Factory, as: PduFactory
  alias SMPPEX.ESME.Sync

  @timeout 30_000 # 30 seconds connection timeout

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.id))
  end

  defp via_tuple(config_id) do
    {:via, Registry, {Sms.SmppRegistry, config_id}}
  end

  def init(config) do
    Process.send_after(self(), :connect, 0)
    {:ok, %{config: config, mc: nil, queue: :queue.new(), connection_error: false}}
  end

  def handle_info(:connect, state) do
    case connect_and_bind(state.config) do
      {:ok, mc} ->
        Logger.info("Successfully connected and bound to SMPP server: #{state.config.id}")
        {:noreply, %{state | mc: mc, connection_error: false}}

      {:error, reason} ->
        Logger.error("Failed to connect to SMPP server #{state.config.id}: #{inspect(reason)}")
        Process.send_after(self(), :try_reconnect, 30_000)
        {:noreply, %{state | mc: nil, connection_error: true}}

      reason ->
        Logger.error("Failed to connect to SMPP server #{state.config.id}: #{inspect(reason)}")
        Process.send_after(self(), :try_reconnect, 30_000)
        {:noreply, %{state | mc: nil, connection_error: true}}
    end
  end

  def handle_cast({:update_config, new_config}, state) do
    if config_requires_reconnect?(state.config, new_config) do
      # Safely stop MC if it exists
      if state.mc, do: SMPPEX.ESME.Sync.stop(state.mc)

      # Schedule a reconnect with the new config
      Process.send_after(self(), :connect, 1000)
      {:noreply, %{state | config: new_config, mc: nil}}
    else
      {:noreply, %{state | config: new_config}}
    end
  end

  def handle_call({:send_sms, sms_log}, _from, %{mc: nil} = state) do
    # Cannot send if not connected
    update_sms_status(sms_log, {:failed, :not_connected})
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send_sms, sms_log}, _from, state) do
    split_messages =
      HtmlEntities.decode(sms_log.message)
      |> split_long_message(state.config)

    results = Enum.map(split_messages, fn part ->
      send_message(part, sms_log, state)
    end)

    case Enum.all?(results, &match?({:ok, _}, &1)) do
      true ->
        update_sms_status(sms_log, :sent)
        {:reply, :ok, state}
      false ->
        failed_parts = Enum.filter(results, &match?({:error, _}, &1))
        update_sms_status(sms_log, {:failed, failed_parts})
        {:reply, {:error, :sending_failed}, state}
    end
  end

  # Add periodic reconnection attempt
  def handle_info(:try_reconnect, %{connection_error: true} = state) do
    Logger.info("Attempting to reconnect to SMPP server: #{state.config.id}")
    case connect_and_bind(state.config) do
      {:ok, mc} ->
        Logger.info("Successfully reconnected to SMPP server: #{state.config.id}")
        {:noreply, %{state | mc: mc, connection_error: false}}
      {:error, _reason} ->
        # Schedule another reconnection attempt
        Process.send_after(self(), :try_reconnect, 60_000)
        {:noreply, state}
    end
  end

  def handle_info(:try_reconnect, state), do: {:noreply, state}

  # SMPP event handlers
  def handle_info({:smppex_esme, _, {:bound, _}}, state) do
    Logger.info("SMPP connection bound: #{state.config.id}")
    {:noreply, state}
  end

  def handle_info({:smppex_esme, _, :closed}, state) do
    Logger.warn("SMPP connection closed: #{state.config.id}")
    Process.send_after(self(), :try_reconnect, 5_000)
    {:noreply, %{state | mc: nil, connection_error: true}}
  end

  def handle_info({:smppex_esme, _, {:pdu, pdu}}, state) do
    handle_smpp_pdu(pdu, state)
    {:noreply, state}
  end

  # Catch-all for other SMPP events
  def handle_info({:smppex_esme, _, event}, state) do
    Logger.debug("SMPP event for #{state.config.id}: #{inspect(event)}")
    {:noreply, state}
  end

  # Handle delivery receipts and other PDUs
  defp handle_smpp_pdu(pdu, _state) do
    case Pdu.command_name(pdu) do
      :deliver_sm ->
        # This could be a delivery receipt
        Logger.info("Received delivery receipt: #{inspect(pdu)}")
        # Process delivery receipt here

      :enquire_link ->
        # Automatically handled by the library
        :ok

      cmd_name ->
        Logger.debug("Received SMPP PDU: #{inspect(cmd_name)}")
    end
  end

  defp connect_and_bind(config) do
    Logger.debug("Connecting to SMPP server #{config.host}:#{config.port} as #{config.system_id}")

    # Connection options
    transport_opts = [
      timeout: @timeout,
    ]

    case Sync.start_link(config.host, config.port, transport_opts) do
      {:ok, esme} ->
        Logger.debug("SMPP connection established, binding...")

        # Build bind_transceiver PDU
        bind_pdu = PduFactory.bind_transceiver(config.system_id, config.password)

        # Send bind request
        case Sync.request(esme, bind_pdu, @timeout) do
          :stop ->
            Logger.error("SMPP bind request received stop signal")
            Sync.stop(esme)
            {:error, :binding_stopped}

          {:ok, resp_pdu} ->
            case Pdu.command_status(resp_pdu) do
              0 -> # ESME_ROK - success
                Logger.info("SMPP bind successful for #{config.system_id}")
                {:ok, esme}

              5 -> # ESME_ROK - success
                Logger.info("SMPP bind successful for #{config.system_id}")
                {:ok, esme}

              status ->
                Logger.error("SMPP bind failed with status: #{status}")
                Sync.stop(esme)
                {:error, {:bind_failed, status}}
            end

          {:error, reason} ->
            Logger.error("SMPP bind request failed: #{inspect(reason)}")
            Sync.stop(esme)
            {:error, {:bind_request_failed, reason}}
        end

      {:error, reason} ->
        Logger.error("SMPP connection failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}

      reason ->
        Logger.error("SMPP connection failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  defp config_requires_reconnect?(old_config, new_config) do
    old_config.host != new_config.host ||
    old_config.port != new_config.port ||
    old_config.system_id != new_config.system_id ||
    old_config.password != new_config.password
  end

  defp split_long_message(message, config) do
    max_single = config.max_single_length || 160
    max_multipart = config.max_multipart_length || 153

    with(
      true <- recipient.count > 1,
      {:ok, "gsm_7bit"} <- SmsPartCounter.detect_encoding(message),
      ref = :rand.uniform(255),
      gsm_message = GSM.to_gsm(message),
      {:ok, :split, msgs} <- SMPPEX.Pdu.Multipart.split_message(ref, gsm_message, 0, max_multipart)
    ) do
      msgs
    else
      _ ->
        List.wrap(message)
    end
  end

  defp send_message(part, sms_log, state, count \\ 1) do
    pdu = PduFactory.submit_sm(
      {sms_log.sender, 5, 1},
      {sms_log.mobile, 1, 1},
      {0, part},
      1 # Request delivery receipt
    ) |> (fn submit_sm ->
      if(count > 1,
          do: Pdu.set_mandatory_field(submit_sm, :esm_class, 64),
          else: submit_sm)
    end).()

    case Sync.request(state.mc, pdu, @timeout) do
      {:ok, resp_pdu} ->
        case Pdu.command_status(resp_pdu) do
          0 -> # ESME_ROK - success
            message_id =
              Pdu.field(resp_pdu, :message_id)
              |> parse_message_id()
            Logger.info("Message sent successfully, message_id: #{message_id}")
            {:ok, %{part: part, message_id: message_id}}

          status ->
            Logger.error("Message sending failed with status: #{status}")
            {:error, {part, {:submit_failed, status}}}
        end

      {:error, reason} ->
        Logger.error("Failed to send message: #{inspect(reason)}")
        {:error, {part, reason}}
    end
  end

  defp update_sms_status(sms_log, status) do
    # Call your update function here
    # If you haven't implemented this yet, log the status change
    Logger.info("SMS status update: #{sms_log.id} -> #{inspect(status)}")
    # Uncomment when implemented:
    # SmsLogs.update_status(sms_log.id, status)
  end

  defp parse_message_id(msg_id) do
    case String.match?(msg_id, ~r/^[[:digit:]]+$/) do
      true ->
        msg_id

      false ->
        case Integer.parse(msg_id, 16) do
          {msg_id, _} ->
            to_string(msg_id)

          _ ->
            for(<<c <- msg_id>>, c in 0..127, into: "", do: <<c>>)
        end
    end
  end
end
