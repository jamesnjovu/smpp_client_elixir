defmodule Sms.SmsDispatcher do
  require Logger

  # Sms.SmsDispatcher.dispatch(%{mobile: "260975870923", count: 1, id: 1, message: "testing Zamtel", sender: "Probase"})

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
            GenServer.call(pid, {:send_sms, sms_log})

          [] ->
            Logger.error("SMPP server for config #{config.id} not found")
            {:error, :server_not_found}
        end
    end
  end

  # Sms.SmsDispatcher.test
  def test() do
    [
      "AtlasMara", "Cavmont", "FCB", "ZICB", "ZRA", "NRFA", "ProBASE", "eToll", "EvelynHone", "FNB",
      "Stanbic", "Sygenta", "Twangale", "Zanaco", "ALTUS", "Bayport", "FABANK", "IndoZambia",
      "NATSAVE", "VOC", "ZESCO", "NWSC", "Mpelembe", "Shikola", "LCC", "RTSA", "LWSC", "MFZ",
      "LASF", "ZCA", "ZICA", "WFP", "UBA", "Emory", "Seedco", "EHC", "CBU", "NAPSA", "ZamPost",
      "Rusangu", "PABS", "GRZMOF", "eNAPSA", "StanbicEtax", "TaxiZambia", "DGI", "INDOBANK",
      "MLFC", "Mulungushi", "Nkrumah", "Uniturtle", "Tontozo", "NHIMA", "SFL", "MKids", "RAAZ",
      "RMAI", "ImpactYouth", "MLFC_FI", "MLFC_CG", "RhemaZM", "eTumba", "PF2021", "ZRL", "GBL",
      "PACRA", "St.MksOldBys", "St.MksOdBys", "ExStMarks", "Absa", "HouseCube", "Vonse",
      "COVID19ZM", "ATM_ALERT", "Syngenta", "ZIBSIP", "ZamBrew", "Primenet", "Survey",
      "SBZSMARTPay", "Barclays", "DSTV", "GOtv", "Boxoffice", "Online", "Multichoice",
      "HANDYMATE", "CropLife", "Betta1", "ABBANK", "TBZ", "Garden City", "LOLCFinance", "Ulendo",
      "CMC", "MTC", "PayGo", "Bevura", "LSMFEZ", "QRinvite", "eWORKERS", "UlendoWorks",
      "ECL2021", "Maano VFM", "Eden", "MyJuba", "NWASCO", "Holycross", "All1Zed", "BISS1996",
      "SF Property", "ViB Mobile", "Kamono", "Laxmi", "Acumeni", "Investrust", "WePay",
      "ZICBEMT", "SimbaFiber", "fitzsoft", "FALCON", "Swek", "Farmcloud", "Gncl", "GospelEnvoy",
      "dpmyjubazm", "Yellow Card", "E-MALI", "EswMobile", "LpWSC", "LSA Lusaka", "Smarthub",
      "GNC", "AUSTRALIA", "Nyamula", "Nando's", "StartApp", "StartAppErp", "Afropologie",
      "CSKOTP", "eMsika", "Nokamu", "Hematon", "ZamSugar", "SOLACE", "eCDF", "INCOTEC",
      "SwiftTKT", "SwiftOTP", "iNERTCE", "MTN MoMo", "UNO", "Synergy", "SIMPLY ASIA", "ZICB-IT",
      "EIZ", "Panarottis", "Shimzlaw", "AFRI FEST", "PREMIERCRED", "Success Fac", "SMSOTP",
      "DruDruCars", "CSF", "ITNOTP", "Mingling", "Chonry", "BetWinner", "LetsChat", "Yango",
      "WhatsApp", "COLTNET", "WBC", "Tenga", "ITNOTPZM", "Zed Momo", "Zed Mobile", "Vida.Zambia",
      "PRIME FOUR", "One Z Lotto", "OpenHeavens", "MMP", "Access Bank", "Unka Go", "UnkaGo",
      "JabuPay", "RHEMA", "K&ScarHire", "K&S", "K&S_CarHire", "SOJI", "Jabu", "SylvaFood",
      "Sylva_Food", "SFS", "SylvaTech", "MELKAT", "Flame", "Zircon", "Tumingle", "DANGOTE"
    ]

    |> Enum.each(fn sender ->
      dispatch(%{mobile: "260974071573", count: 1, id: 1, message: "testing Zamtel", sender: sender})
    end)
  end
end
