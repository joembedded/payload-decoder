# Elixir Script -  LTX Chirpstack Payload Decoder - V1.12 (C) JoEmbedded.de
# --- ungetestet ---

defmodule LTX.Parser do
  require Logger
  import Bitwise

  @deftypes %{
    10 => ["°C"],
    11 => ["%rH", "°C"],
    12 => ["Bar", "°C"],
    13 => ["m", "°C"],
    14 => ["m", "dBm"]
  }

  @ltx_errors %{
    1 => "NoValue",
    2 => "NoReply",
    3 => "OldValue",
    6 => "ErrorCRC",
    7 => "DataError",
    8 => "NoCachedValue"
  }

  @hk_units %{
    90 => "V (HK_Bat)",
    91 => "°C (HK_intTemp)",
    92 => "%rH (HK_intHum.)",
    93 => "mAh (HK_usedEnergy)",
    94 => "mBar (HK_Baro)"
  }

  def parse(<<flags, rest::binary>>, %{fPort: port}) when port > 0 and port < 200 do
    with {:ok, decoded} <- parse_ltx(rest, port, flags) do
      decoded
    else
      {:error, msg} -> %{error: msg}
    end
  end

  def parse(_, %{fPort: port}), do: %{error: "LTX: fPort:#{port} unknown"}

  defp parse_ltx(payload, port, flags) do
    reason =
      case flags &&& 0x0F do
        2 -> "(Auto)"
        3 -> "(Manual)"
        r -> "(Reason:#{r}?)"
      end

    flag_str =
      [
        if((flags &&& 0x80) > 0, do: "(Reset)", else: nil),
        if((flags &&& 0x40) > 0, do: "(Alarm)", else: nil),
        if((flags &&& 0x20) > 0, do: "(old Alarm)", else: nil),
        if((flags &&& 0x10) > 0, do: "(Measure)", else: nil)
      ]
      |> Enum.filter(& &1)
      |> Enum.join(" ")

    type_units = Map.get(@deftypes, port, [])
    parse_channels(payload, type_units, 0, 0, [], reason, flag_str)
  end

  defp parse_channels(<<>>, _units, _ichan, _dtidx, acc, reason, flags),
    do: {:ok, %{reason: reason, flags: flags, chans: Enum.reverse(acc)}}

  defp parse_channels(<<itok, rest::binary>>, units, ichan, dtidx, acc, reason, flags)
       when itok < 128 do
    cmanz = itok &&& 0x3F

    cond do
      cmanz == 0 ->
        case rest do
          <<new_chan, tail::binary>> ->
            parse_channels(tail, units, new_chan, dtidx, acc, reason, flags)

          _ ->
            {:error, "LTX: Format(1) invalid"}
        end

      (itok &&& 0x40) == 0 ->
        parse_floats32(rest, cmanz, units, ichan, dtidx, acc, reason, flags)

      true ->
        parse_floats16(rest, cmanz, units, ichan, dtidx, acc, reason, flags)
    end
  end

  defp parse_channels(<<itok, rest::binary>>, units, ichan, dtidx, acc, reason, flags)
       when itok >= 128 do
    ichan = max(ichan, 90)
    cbits = itok &&& 0x3F

    parse_hk(rest, cbits, ichan, acc, reason, flags)
  end

  defp parse_floats32(bin, 0, _units, ichan, dtidx, acc, reason, flags),
    do: parse_channels(bin, [], ichan, dtidx, acc, reason, flags)

  defp parse_floats32(<<f::32-float, rest::binary>>, n, units, ichan, dtidx, acc, reason, flags) do
    unit = Enum.at(units, rem(dtidx, length(units)))
    new = %{channel: ichan, value: Float.round(f, 6), unit: unit, prec: "F32"}
    parse_floats32(rest, n - 1, units, ichan + 1, dtidx + 1, [new | acc], reason, flags)
  end

  defp parse_floats32(_, _, _, _, _, _, _, _), do: {:error, "LTX: Format(2) invalid"}

  defp parse_floats16(bin, 0, _units, ichan, dtidx, acc, reason, flags),
    do: parse_channels(bin, [], ichan, dtidx, acc, reason, flags)

  defp parse_floats16(<<u16::16, rest::binary>>, n, units, ichan, dtidx, acc, reason, flags) do
    unit = Enum.at(units, rem(dtidx, length(units)))
    val = decode_float16(u16)

    new =
      case @ltx_errors[u16 &&& 0x03FF] do
        err when u16 >>> 10 == 0x3F -> %{channel: ichan, msg: err, unit: unit, prec: "F16"}
        _ -> %{channel: ichan, value: val, unit: unit, prec: "F16"}
      end

    parse_floats16(rest, n - 1, units, ichan + 1, dtidx + 1, [new | acc], reason, flags)
  end

  defp parse_floats16(_, _, _, _, _, _, _, _), do: {:error, "LTX: Format(3) invalid"}

  defp parse_hk(bin, 0, ichan, acc, reason, flags),
    do: parse_channels(bin, [], ichan, 0, acc, reason, flags)

  defp parse_hk(<<u16::16, rest::binary>>, cbits, ichan, acc, reason, flags)
       when (cbits &&& 1) == 1 do
    unit = Map.get(@hk_units, ichan, "HK_unknown")
    val = decode_float16(u16)

    new =
      case @ltx_errors[u16 &&& 0x03FF] do
        err when u16 >>> 10 == 0x3F -> %{channel: ichan, msg: err, unit: unit, prec: "F16"}
        _ -> %{channel: ichan, value: val, unit: unit, prec: "F16"}
      end

    parse_hk(rest, cbits >>> 1, ichan + 1, [new | acc], reason, flags)
  end

  defp parse_hk(rest, cbits, ichan, acc, reason, flags),
    do: parse_hk(rest, cbits >>> 1, ichan + 1, acc, reason, flags)

  defp parse_hk(_, _, _, _, _, _), do: {:error, "LTX: Format(4) invalid"}

  defp decode_float16(raw) do
    sign = if(raw &&& 0x8000 != 0, do: -1, else: 1)
    exponent = raw >>> 10 &&& 0x1F
    fraction = raw &&& 0x03FF

    cond do
      exponent == 0 -> sign * :math.pow(2, -14) * (fraction / :math.pow(2, 10))
      exponent == 0x1F -> :infinity
      true -> sign * :math.pow(2, exponent - 15) * (1 + fraction / :math.pow(2, 10))
    end
  end

  # ------------------------- TESTING -----------------------------
  def test_decoder(hexstring, port \\ 11) do
    bytes =
      hexstring
      |> String.replace(~r/\s/, "")
      |> String.downcase()
      |> String.codepoints()
      |> Enum.chunk_every(2)
      |> Enum.map(fn [a, b] -> String.to_integer(a <> b, 16) end)

    payload = :binary.list_to_bin(bytes)
    parse(payload, %{fPort: port})
  end

  def main do
    IO.puts("---TEST-DECODER---")

    testmsgs = [
      "13 01 41A4E148  9F 42A3 4DA8 5172 2B3F 63E8",
      "12 42 4D24 4CE4 01 41948F5C 88 355B",
      "7242FC02FC0201FF800002884479"
    ]

    for msg <- testmsgs do
      IO.puts("----Test-Payload:-----")
      IO.puts(msg)
      IO.puts("----Decoded Result:-----")
      result = test_decoder(msg)
      IO.inspect(result, label: "Result", pretty: true)
    end
  end
end

# if function_exported?(LTX.Parser, :main, 0), do: LTX.Parser.main()
