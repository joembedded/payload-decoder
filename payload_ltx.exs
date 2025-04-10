# LTX Payload Decoder in Elixir auf ELEMENT IoT
# V1.12 (C) JoEmbedded.de

# *** ACHTUNG *** 08.04.2024: Parser läuft lokal exakt und wurde
# auf minimalen Sprachstandard reduziert.
# Auf Zielsystem (ELEMENT IoT) allerdings noch nicht lauffähig!
# Speichern des Parsers lediglich mit Meldung "Speichern nicht möglich" kommentiert???
# Aktionen vor Speichern:
# - 'use Platform.Parsing.Behaviour' einkommentieren
# - Letzte Zeile 'Parser.main()' auskommentieren
# - Problem wohl Zugriff auf geschachtelte Strukturen: https://docs.element-iot.com/parsers/tutorial-de/#lokale-entwicklung
#   nur via get/3 des Platform.io moeglich. ***todo**

#
# Info:
# - ELEMENT IoT erwartet 'use Platform.Parsing.Behaviour'
# - ELEMENT IoT sagt "Kann Parser nicht speichern"...

defmodule Parser do
  ## --- ENABLE fuer ELEMENTS IoT:
  # use Platform.Parsing.Behaviour
  import Bitwise

  # Gibt die Einheiten für den angegebenen Port zurück.
  def deftypes(port) do
    case port do
      10 -> ["°C"]
      11 -> ["%rH", "°C"]
      12 -> ["Bar", "°C"]
      13 -> ["m", "°C"]
      14 -> ["m", "dBm"]
      _ -> []
    end
  end

  # Gibt die Fehlermeldung für den angegebenen Fehlercode zurück.
  def ltx_error(errno) do
    case errno do
      1 -> "NoValue"
      2 -> "NoReply"
      3 -> "OldValue"
      6 -> "ErrorCRC"
      7 -> "DataError"
      8 -> "NoCachedValue"
      _ -> "Unknown error"
    end
  end

  # Gibt die Einheit und Beschreibung für den angegebenen HK-Kanal zurück.
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

  # Dekodiert einen Payload (als Binärdaten) anhand des angegebenen Ports.
  def parse(<<flags, rest::binary>> = _payload, meta) do
    %{meta: %{frame_port: fPort}} = meta

    # Grund für die Übertragung bestimmen
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
      |> Enum.join(" ")

    # Einheiten für den Port abrufen
    units = deftypes(fPort)
    state = %{fPort: fPort, units: units, chan: 0, dtidx: 0, acc: []}
    {final_state, _rest} = decode_channels(rest, state)

    # Ergebnis zurückgeben
    %{
      reason: reason,
      flags: flag_str,
      chans: Enum.reverse(final_state.acc)
    }
  end

  # Allgemeine Kanaldetektion
  defp decode_channels(<<>>, state), do: {state, <<>>}

  # Token < 128: Normale Daten oder Kanalwechsel
  defp decode_channels(<<token, rest::binary>>, state) when token < 128 do
    cmanz = token &&& 0x3F

    cond do
      cmanz == 0 ->
        # Neuer Kanal wird aus dem nächsten Byte gesetzt
        case rest do
          <<new_chan, tail::binary>> ->
            decode_channels(tail, %{state | chan: new_chan})

          _ ->
            {state, <<>>}
        end

      (token &&& 0x40) == 0 ->
        # 32-Bit-Float-Daten (F32)
        decode_floats32(rest, cmanz, state)

      true ->
        # 16-Bit-Float-Daten (F16)
        decode_floats16(rest, cmanz, state)
    end
  end

  # Token ≥ 128: Housekeeping (HK)-Daten; Kanal mindestens 90
  defp decode_channels(<<token, rest::binary>>, state) when token >= 128 do
    new_state = %{state | chan: max(state.chan, 90)}
    cbits = token &&& 0x3F
    decode_hk(rest, cbits, new_state)
  end

  # Dekodierung von 32-Bit (F32)-Werten
  defp decode_floats32(bin, 0, state), do: decode_channels(bin, state)

  defp decode_floats32(<<f::32-float, rest::binary>>, n, state) when n > 0 do
    unit = Enum.at(state.units, rem(state.dtidx, max(length(state.units), 1)))

    entry = %{
      channel: state.chan,
      value: Float.round(f, 6),
      unit: unit,
      prec: "F32"
    }

    new_state =
      %{state | chan: state.chan + 1, dtidx: state.dtidx + 1, acc: [entry | state.acc]}

    decode_floats32(rest, n - 1, new_state)
  end

  defp decode_floats32(bin, _n, state), do: {state, bin}

  # Dekodierung von 16-Bit (F16)-Werten
  defp decode_floats16(bin, 0, state), do: decode_channels(bin, state)

  defp decode_floats16(<<u16::16, rest::binary>>, n, state) when n > 0 do
    unit = Enum.at(state.units, rem(state.dtidx, max(length(state.units), 1)))
    val = decode_float16(u16)

    entry =
      if u16 >>> 10 == 0x3F do
        %{
          channel: state.chan,
          msg: ltx_error(u16 &&& 0x03FF),
          unit: unit,
          prec: "F16"
        }
      else
        %{
          channel: state.chan,
          value: val,
          unit: unit,
          prec: "F16"
        }
      end

    new_state =
      %{state | chan: state.chan + 1, dtidx: state.dtidx + 1, acc: [entry | state.acc]}

    decode_floats16(rest, n - 1, new_state)
  end

  defp decode_floats16(bin, _n, state), do: {state, bin}

  # Dekodierung von Housekeeping (HK)-Daten
  defp decode_hk(bin, 0, state), do: decode_channels(bin, state)

  defp decode_hk(<<u16::16, rest::binary>>, cbits, state) when (cbits &&& 1) == 1 do
    unit = hk_unit(state.chan)
    val = decode_float16(u16)

    entry =
      if u16 >>> 10 == 0x3F do
        %{
          channel: state.chan,
          msg: ltx_error(u16 &&& 0x03FF),
          unit: unit,
          prec: "F16"
        }
      else
        %{
          channel: state.chan,
          value: val,
          unit: unit,
          prec: "F16"
        }
      end

    new_state = %{state | chan: state.chan + 1, acc: [entry | state.acc]}
    decode_hk(rest, cbits >>> 1, new_state)
  end

  defp decode_hk(rest, cbits, state) do
    decode_hk(rest, cbits >>> 1, %{state | chan: state.chan + 1})
  end

  # Hilfsfunktion: Dekodierung eines 16-Bit-Werts in einen Float
  defp decode_float16(raw) do
    sign = if((raw &&& 0x8000) != 0, do: -1, else: 1)
    exponent = raw >>> 10 &&& 0x1F
    fraction = raw &&& 0x03FF

    cond do
      exponent == 0 ->
        sign * :math.pow(2, -14) * (fraction / :math.pow(2, 10))

      exponent == 0x1F ->
        :infinity

      true ->
        sign * :math.pow(2, exponent - 15) * (1 + fraction / :math.pow(2, 10))
    end
  end

  ## ----------------- TEST-CONSOLE -----------------
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

  # Hauptfunktion für Tests
  def main do
    [
      "130141A4E1489F42A34DA851722B3F63E8",
      "13 01 41A4E148  9F 42A3 4DA8 5172 2B3F 63E8",
      "12424D244CE40141948F5C88355B",
      "7242FC02FC0201FF800002884479"
    ]
    |> Enum.each(fn msg ->
      testport = 11
      IO.puts("Test Payload: #{msg} Port: #{testport}")

      msg
      |> test_decoder(%{meta: %{frame_port: testport}})
      |> IO.inspect(label: "Decoded Result")
    end)
  end
end

## --- DISABLE fuer ELEMENTS IoT:
Parser.main()
