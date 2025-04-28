# LTX Payload Decoder (Uplink) in Elixir auf ELEMENT IoT
# V1.16 (C) JoEmbedded.de
# https://github.com/joembedded/payload-decoder

# Aktionen vor Speichern fuer ELEMENT IoT
# - 'use Platform.Parsing.Behaviour' einkommentieren
# - Block zwischen ...TEST_START und ...TEST_END entfetneen
# - Letzte Zeile 'Parser.main()' auskommentieren
#
# ELEMENT IoT verweigert das Speichern des Parsers ohne irgendwelche Angaben,
# sofern IO. etc. vorhanden ist. Auch verweidgert ELEMENT viele
# Sprachkonstrikte, z.B. divese map-Operationen... Die Liste ist lang...

defmodule Parser do
  # use Platform.Parsing.Behaviour
  import Bitwise

  # ---PARSE---
  def parse(<<flags, rest::binary>>, meta) do
    %{meta: %{frame_port: fPort}} = meta

    # Grund für die Übertragung
    reason =
      (flags &&& 0x0F)
      |> case do
        2 -> "(Auto)"
        3 -> "(Manual)"
        r -> "(Reason:#{r}?)"
      end

    # Flags extrahieren
    flag_str =
      [
        if((flags &&& 0x80) > 0, do: "(Reset)"),
        if((flags &&& 0x40) > 0, do: "(Alarm)"),
        if((flags &&& 0x20) > 0, do: "(old Alarm)"),
        if((flags &&& 0x10) > 0, do: "(Measure)")
      ]
      |> Enum.filter(& &1)
      |> Enum.join()

    # Rest ist Channel Payload
    decpay = decode_channels(rest, fPort)

    # Ergebnis zurückgeben, port nur informativ
    %{
      port: fPort,
      reason: reason,
      flags: flag_str,
      chans: decpay
    }
  end

  # Channel Payload
  def decode_channels(pbytes, port) do
    decode_channels(pbytes, 0, [], port)
  end

  def decode_channels(<<>>, _ichan, result, _port) do
    result
  end

  # Kanal folgt
  def decode_channels(<<itok, rest::binary>>, _ichan, result, port) when itok == 0 do
    # Neuer Kanal folgt
    <<new_ichan, rest::binary>> = rest
    decode_channels(rest, new_ichan, result, port)
  end

  # 1-63 F32 folgen
  def decode_channels(<<itok, rest::binary>>, ichan, result, port) when itok < 64 do
    # Float32-Daten
    anzf32 = itok
    decode_f32(anzf32, rest, ichan, result, port)
  end

  # 0-63 F16 folgen
  def decode_channels(<<itok, rest::binary>>, ichan, result, port) when itok < 128 do
    # Float16-Daten
    anzf16 = itok &&& 63
    decode_f16(anzf16, rest, ichan, result, port)
  end

  # 0-7 HK folgen
  def decode_channels(<<itok, rest::binary>>, ichan, result, port) do
    # HK als Float16-Daten
    hk16bits = itok
    ichan = if ichan < 90, do: 90, else: ichan
    decode_hk(hk16bits, 7, rest, ichan, result, port)
  end

  # n * F32 entnehmen
  def decode_f32(0, rest, ichan, result, port) do
    decode_channels(rest, ichan, result, port)
  end

  def decode_f32(anzf32, <<0x1FF::size(9), errno::size(23), rest::binary>>, ichan, result, port)
      when anzf32 > 0 do
    errmsg = ltx_error(errno)
    unit = ltx_units(port, length(result))
    cv = %{channel: ichan, msg: errmsg, unit: unit, prec: "F32"}

    result = result ++ [cv]
    decode_f32(anzf32 - 1, rest, ichan + 1, result, port)
  end

  def decode_f32(anzf32, <<f::32-float, rest::binary>>, ichan, result, port) when anzf32 > 0 do
    val = Float.round(f, 8)
    unit = ltx_units(port, length(result))
    cv =  %{channel: ichan, value: val, unit: unit, prec: "F32"}

    result = result ++ [cv]
    decode_f32(anzf32 - 1, rest, ichan + 1, result, port)
  end

  # n * F16 entnehmen
  def decode_f16(0, rest, ichan, result, port) do
    decode_channels(rest, ichan, result, port)
  end

  def decode_f16(anzf16, <<0x3F::size(6), errno::size(10), rest::binary>>, ichan, result, port)
      when anzf16 > 0 do
    errmsg = ltx_error(errno)
    unit = ltx_units(port, length(result))
    cv =  %{channel: ichan, msg: errmsg, unit: unit, prec: "F16"}

    result = result ++ [cv]
    decode_f16(anzf16 - 1, rest, ichan + 1, result, port)
  end

  def decode_f16(anzf16, <<u16::size(16), rest::binary>>, ichan, result, port) when anzf16 > 0 do
    val = decode_float16(u16)
    unit = ltx_units(port, length(result))
    cv =   %{channel: ichan, value: val, unit: unit, prec: "F16"}

    result = result ++ [cv]
    decode_f16(anzf16 - 1, rest, ichan + 1, result, port)
  end

  # Bitweise HK entnehmen, skip HK wenn Bit 0
  def decode_hk(_, 0, rest, ichan, result, port) do
    decode_channels(rest, ichan, result, port)
  end

  def decode_hk(hk16bits, hcnt, rest, ichan, result, port)
      when hcnt > 0 and (hk16bits &&& 1) == 0 do
    decode_hk(hk16bits >>> 1, hcnt - 1, rest, ichan + 1, result, port)
  end

  def decode_hk(hk16bits, hcnt, <<u16::size(16), rest::binary>>, ichan, result, port)
      when hcnt > 0 do
    val = decode_float16(u16)
    unit = hk_unit(ichan)
    cv = %{channel: ichan, value: val, unit: unit, prec: "F16"}
    result = result ++ [cv]
    decode_hk(hk16bits >>> 1, hcnt - 1, rest, ichan + 1, result, port)
  end

  # --Hilfsfunktionen--
  # Fehlermeldungen im Klartext in FLoat16/32
  def ltx_error(errno) do
    case errno do
      1 -> "NoValue"
      2 -> "NoReply"
      3 -> "OldValue"
      6 -> "ErrorCRC"
      7 -> "DataError"
      8 -> "NoCachedValue"
      _ -> "Err#{errno}"
    end
  end

  # Einheiten fuer Port und Index (repeating)
  def ltx_units(port, idx) do
    units =
      case port do
        10 -> ["°C"]
        11 -> ["%rH", "°C"]
        12 -> ["Bar", "°C"]
        13 -> ["m", "°C"]
        14 -> ["m", "dBm"]
        15 -> ["°C", "uS/cm"]
        _ -> ["(nn)"]  # not known
      end

    anz = length(units)
    uidx = if anz > 1, do: rem(idx, anz), else: 0
    Enum.at(units, uidx)
  end

  # Einheit / Beschreibung HK-Kanaele
  def hk_unit(channel) do
    case channel do
      90 -> "V (HK_Bat)"
      91 -> "°C (HK_intTemp)"
      92 -> "%rH (HK_intHum.)"
      93 -> "mAh (HK_usedEnergy)"
      94 -> "mBar (HK_Baro)"
      _ -> "HK_unknown"
    end
  end

  # Dekodierung eines 16-Bit-Werts in einen Float
  def decode_float16(raw) do
    sign = if((raw &&& 0x8000) != 0, do: -1, else: 1)
    exponent = raw >>> 10 &&& 0x1F
    fraction = raw &&& 0x03FF

    cond do
      exponent == 0 ->
        Float.round(sign * :math.pow(2, -14) * (fraction / :math.pow(2, 10)), 6)

      exponent == 0x1F ->
        :infinity

      true ->
        Float.round(sign * :math.pow(2, exponent - 15) * (1 + fraction / :math.pow(2, 10)), 6)
    end
  end

  ## ----------------- TEST-CONSOLE START (entfernen fuer ELEMENTS) -----------------
  def test_decoder(hexstring, meta) do
    hexstring
    |> String.replace(~r/\s+/, "")
    |> String.codepoints()
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [a, b] -> String.to_integer(a <> b, 16)
      _ -> 0
    end)
    |> :binary.list_to_bin()
    |> parse(meta)
  end

  # Hauptfunktion für Tests - Keine IO.puts() im Parser, sonst wirf ELEMENTS einen raus
  def main do
    [
      # "13 01 41A4E148  9F 42A3 4DA8 5172 2B3F 63E8",
      #"130141A4E1489F42A34DA851722B3F63E8",
      #"12 42 4D24 4CE4 01 41948F5C 88 355B",
      "72 00 11 42 FC02 FC02 01FF800002884479"
    ]
    |> Enum.each(fn msg ->
      # Testport
      testport = 1
      IO.puts("Test Payload: #{msg} Port: #{testport}")

      msg
      |> test_decoder(%{meta: %{frame_port: testport}})
      |> IO.inspect(label: "Decoded Result")
    end)
  end

  ## ----------------- TEST-CONSOLE ENDE (entfernen fuer ELEMENTS) -----------------
end

## --- (entfernen fuer ELEMENTS):
Parser.main()
