# LTX Payload Decoder (for ChirpStack, TTN et al.)

## Overview
-> Jump to: [German Version](./readme_de.md) 

Payload decoders are often considered complex. And this for good reason. In the world of LoRaWAN, every byte counts, as energy consumption increases with the length of transmitted data. The goal is to transport as much information as possible with minimal storage overhead. However, the variety of conversion methods and the lack of standardized error messages often make decoding confusing and error-prone.

For example, a temperature value can be efficiently transmitted as a 16-bit integer with scaling. The same format could also be used for battery voltage—but here, a completely different scaling would be required. Implementing uniform error codes in such fixed formats is nearly impossible.

In practice, an accuracy of 0.05% is sufficient for many measured values—such as temperatures, humidity, or distances. Therefore, LTX loggers use 16-bit floating point numbers to ensure a consistent representation. An additional advantage: error codes can be integrated without loss by utilizing the reserved "NaN" range of floating point numbers.

Only where higher resolution is explicitly required 32-bit floating point numbers are used. This keeps data transmission efficient without sacrificing precision.

> Example: In Europe, LoRa can securely transmit 51 bytes of payload. With the LTX Payload Decoder, this could include all measurement values of a 20-channel high-precision temperature measurement chain ("thermistor string") with a resolution of 5/1000 degrees (in the range of +/- 10°C), along with up to 4 housekeeping (HK) channels (e.g., battery voltage, energy consumption, device internal temperature, and internal humidity).

## Highlights of the LTX Payload Decoder

- **Measurement values as floating point numbers** (either **16-bit or 32-bit**, depending on accuracy requirements).
- **Structured measurement values as an array**, making automated processing easier.
- **Values with units**, as sensor units are transmitted if applicable.
- **Plain-text error messages**, e.g. for sensor errors.
- **Separation of measurement values and system data** (*housekeeping values (HK)* such as battery voltage).
- **Minimal storage requirement**, optimized for LoRaWAN or satellite communication.
- **Upload and Download** possible. Download e.g. for remote commands and configuration.

---

## Installation and Testing - JavaScript

The decoder (`payload_ltx.js`) includes an integrated **test routine**, which can be executed in the browser or in the console. For use in ChirpStack or TTN, the **test section must be removed** (up to `--- TEST-CONSOLE ---`).

Then, simply save this upper part as a **CODEC** in ChirpStack (or TTN).

- **Error Messages:** ChirpStack automatically generates `ERROR` events for runtime errors.

---

## Decoded Data Structure

LoRaWAN data includes a field called `fPort` (1 - 223).
For example, SDI-12 itself does not provide information about channel units, but for LTX Gateways, this can be configured, and upon upload, `fPort` determines the sensor type.
For example, `Type 11` defines a sensor with either a single or multiple temperature/humidity values.

The first byte contains **Flags and Reason Codes**:
- **Flags:** Signals reset, alarm status, or dummy data.
- **Reason Code:** Indicates the reason for transmission (e.g., automatic or manually triggered).

**Data Fields:**
- `chans`: Contains measurement and housekeeping channels (HK).
- **Measurement Channels (0 - 89):** Sensor data.
- **Housekeeping Channels (90 - 99):** System data (battery status, etc.).

### Example of a Decoded Payload:
```javascript
{
    "flags": "(Alarm)(Measure)",       // flags: B7:(Reset) B6:(Alarm) B5:(oldAlarm) B4:(Measure)
    "reason": "(Auto)",                // reasons: B0-B3, only used 1:(Auto) and 5:(Manual)
    "chans": [
      {
        "channel": 0,                  // Channels 0 - 89 are measurement channels
        "value": 20.5625,              // Three measurement channels are present here
        "prec": "F16",                 // Channel type, currently "F16" or "F32"
        "unit": "°C"                   // Defined sensors have known unit(s)
      },
      {
        "channel": 2,
        "value": 18.57,
        "prec": "F32",
        "unit": "°C"
      },
      {
        "channel": 15,
        "msg": "NoReply",               // Either "value" or "msg" is present
        "unit": "m/sec"
      },
      {
        "channel": 93,                 // Channels from 90 onwards are HK channels      
        "unit": "mAh (HK_usedEnergy)",  // Fixed assignment: description with unit
        "value": 0.334717,             // In case of errors, "msg" instead of "value"
        "prec": "F16"                  // HK type is always "F16"
      }
    ]
}
```
Compact representation:
> - The device type (units) is implicitly contained in 'fPort'.
>
> - First byte:
>   Upper 4 bits: Flags:
>    128: Device reset (transmitted once)
>     64: Alarm in current measurement (if the device has alarm thresholds)
>     32: Alarm in previous measurement (if previous transmissions failed)
>     16: Measurement values included
>
>   Lower 4 bits as a number: Transmission reason
>      2: Automatic transmission
>      3: Manually triggered transmission
>      Others: Reserved
>
> - Remaining bytes (the variable 'cursor' holds the current channel (0-89, >= 90, starting at 0)).
>   Measurement values are channels 0-89; 90-99 are HK channels:
>   
>   Blocks consist of 1-byte control code and 1 - xxxxxx values in Float16 or Float32 format.
>    Control code (binary): 0Fxxxxxx 6-bit count  F:0:Float32, F:1:Float16 xxxxxx: number of values (0,1-31) following; if 0: cursor follows.
>    Floats are transmitted in "Big Endian" (IEEE 754) and can alternatively represent an error code.
>    
>    Control code (binary): 1xxxxxxxx 7-bit mask introduces HK channels. HK always starts at 90, cursor may be incremented.
>    Each mask bit represents a channel: 1: included, 0: skipped. HK channels are always transmitted as Float16.

---

## Installation and Testing - Elixir

The decoder (`payload_ltx.exs`) is the Elixir version (mainly developed for ELEMENT IoT platform).


## Further Information

The **LTX Payload Decoder** is compatible with common LoRaWAN stacks and can be tested directly in the **browser debugger console**.

- **ChirpStack:** Uses *QuickJS* internally for decoding.
- **QuickJS:** Lightweight JavaScript interpreter, runs on Windows, Linux & macOS.
- **Testing with QuickJS:**
  ```bash
  ./qjs payload_ltx.js
  ```
  - **Info:** Remove block after `--- TEST-CONSOLE ---` before copying into ChirpStack (or TTN).

More information about QuickJS:
- [QuickJS Website](https://bellard.org/quickjs/)
- [QuickJS GitHub](https://github.com/bellard/quickjs)

---

## Sponsors

### Supported by

![TERRA_TRANSFER](./docu/sponsors/TerraTransfer.jpg "TERRA_TRANSFER")

[TerraTransfer GmbH, Bochum, Germany](https://www.terratransfer.org)
