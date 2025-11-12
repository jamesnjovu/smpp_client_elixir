defmodule Sms.SmsDispatcher do
  require Logger

  # Increase timeout for SMS sending operations
  @call_timeout 60_000

  def dispatch(sms_log) do
    # Log the dispatch request
    Logger.info("Dispatching SMS to #{sms_log.mobile}")
    case Sms.SmppConfigLoader.get_matching_config(sms_log.mobile) do
      nil ->
        Logger.warning("No matching SMPP config for #{sms_log.mobile}")
        {:error, :no_matching_config}

      config ->
        case Registry.lookup(Sms.SmppRegistry, config.id) do
          [{pid, _}] ->
            # Use longer timeout for GenServer call
            GenServer.call(pid, {:send_sms, sms_log}, @call_timeout)

          [] ->
            Logger.error("SMPP server for config #{config.id} not found")
            {:error, :server_not_found}
        end
    end
  end

  # Simple test with short message
  def test() do
    dispatch(%{
      mobile: "260978921730",
      count: 1,
      id: 1,
      message: "Test message from SMPP server",
      sender: "Probase"
    })
  end

  # Test with long message that needs splitting
  def test_long() do
    long_message = """
    FINAL DEMAND FOR PAYMENT Dear Client: THIS IS OUR FINAL ATTEMPT AND NOTICE DEMANDING PAYMENT FOR YOUR ARREARS.
    WE ARE ATTEMPTING TO RESOLVE THIS OUT OF COURT, BUT IF WE CONTINUE NOT TO COME TO AN AGREEMENT TO PAY OFF THE ARREARS WITHIN 7 WORKING DAYS,
    WE INTEND TO TAKE LEGAL ACTION. CALL US NOW ON 0967300274 TO PAY OFF YOUR INDEBTEDNESS
    """

    dispatch(%{
      mobile: "260978921730",
      count: 3, # Indicate this might be split into multiple parts
      id: 2,
      message: String.trim(long_message),
      sender: "Probase"
    })
  end

  # Test multiple different mobile numbers
  def test_multiple() do
    test_numbers = [
      # "260969326050",  # Should match the regex ^(26075|26095|26097|26096)
      "260978921730",
      "260950763820"
    ]

    Enum.each(test_numbers, fn mobile ->
      Logger.info("Testing SMS to #{mobile}")
      result = dispatch(%{
        mobile: mobile,
        count: 1,
        id: System.unique_integer([:positive]),
        message: "Hello from SMPP test - #{mobile}",
        sender: "Probase"
      })

      Logger.info("Result for #{mobile}: #{inspect(result)}")
      # Add small delay between sends
      Process.sleep(1000)
    end)
  end
end
