defmodule Sms.SmsDispatcher do
  require Logger

  # Sms.SmsDispatcher.dispatch(%{mobile: "260978921730", id: 1, message: "testing Zamtel", sender: "Probase"})

  def dispatch(sms_log) do
    # Log the dispatch request
    Logger.info("Dispatching SMS to #{sms_log.mobile}")
    case Sms.SmppConfigLoader.get_matching_config(sms_log.mobile) do
      nil ->
        Logger.warn("No matching SMPP config for #{sms_log.mobile}")
        {:error, :no_matching_config}

      config ->
        case Registry.lookup(Sms.SmppRegistry, config.id) do
          [{pid, _}] ->
            GenServer.call(pid, {:send_sms, sms_log})

          [] ->
            Logger.error("SMPP server for config #{config.id} not found")
            {:error, :server_not_found}
        end
    end
  end
end
