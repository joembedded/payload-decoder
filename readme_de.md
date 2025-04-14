# Chirpstack LTX Payload Decoder

## Überblick
[English Version](./readme.md) 🇬🇧 

Payload-Decoder gelten oft als kompliziert – und das nicht ohne Grund. In der Welt von LoRaWAN zählt jedes Byte, denn der Energieverbrauch steigt mit der Länge der übertragenen Daten. Ziel ist es daher, mit minimalem Speicheraufwand möglichst viele Informationen zu transportieren. Doch die Vielzahl an Umrechnungsverfahren und das Fehlen standardisierter Fehlermeldungen machen die Dekodierung oft unübersichtlich und fehleranfällig.  

Ein Beispiel: Eine Temperatur lässt sich effizient als 16-Bit-Integer mit Skalierung übertragen. Dasselbe Format könnte auch für eine Batteriespannung genutzt werden – doch hier wäre eine völlig andere Skalierung erforderlich. Einheitliche Fehlercodes lassen sich in solchen festen Formaten kaum umsetzen.  

In der Praxis genügt für viele Messwerte – etwa Temperaturen, Feuchtigkeiten oder Distanzen – eine Genauigkeit von 0,05 %. Die LTX-Logger setzen daher auf 16-Bit-Gleitkommazahlen, um eine einheitliche Darstellung zu gewährleisten. Ein zusätzlicher Vorteil: Fehlercodes lassen sich verlustfrei integrieren, indem der reservierte "NaN"-Bereich von Gleitkommazahlen genutzt wird.  

Nur dort, wo eine höhere Auflösung explizit erforderlich ist, kommen 32-Bit-Gleitkommazahlen zum Einsatz. So bleibt die Datenübertragung effizient, ohne auf Präzision zu verzichten.  

> Kleines Beispiel: In Europa können per LoRa 51 Bytes Payload sicher übertragen werden. Dies könnten mit dem LTX Payload Decoder
> also sämtliche Messwerte einer 20-kanaligen, hochgenauen Temperaturmesskette ("Thermistor-String") mit einer Auflösung von 5/1000 Grad (im 
> Bereich +/- 10°C) inklusive von bis zu 4 Housekeeping-Kanäle (HK) (z.B. Batteriespannung, Energieverbrauch, Geräte-Innentemperatur 
> und -Innenfeuchte) sein.

## Highlights des LTX Payload Decoders

- **Messwerte als Fließkommazahlen** (wahlweise **16-Bit oder 32-Bit** je nach Genauigkeitsanforderung).
- **Strukturierte Messwerte als Array**, erleichtert die automatisierte Verarbeitung.
- **Werte mit Einheiten**, die Einheiten der Sensoren werden ggf. übertragen
- **Klartext-Fehlermeldungen**, z. B. bei Sensorausfällen.
- **Trennung von Messwerten und Systemdaten** (*Housekeeping-Werte (HK)* wie z.B. Batteriespannung).
- **Minimaler Speicherbedarf**, optimiert für LoRaWAN oder Satelliten-Kommunikation 

---

## Installation und Test

Der Decoder (`payload_ltx.js`) enthält eine integrierte **Testroutine**, die im Browser oder in der Konsole ausgeführt werden kann. Für den Einsatz in Chirpstack oder TTN muss der **Testbereich entfernt** werden (bis `--- TEST-CONSOLE ---`).

Dann einfach diesen oberen Teil als **CODEC** im Chirpstack (oder auch TTN) abspeichern.

- **Fehlermeldungen:** Chirpstack generiert automatisch `ERROR`-Events bei Laufzeitfehlern.

---

## Decodierte Datenstruktur

Bei LoRaWAN werden existiert ein Feld `fPort` (1 - 223) in den übertragenen Daten.
So liefert z.B. SDI-12 selbst zwar keine Information zu Einheiten der Kanäle, aber für LTX Gateways
kann dies einfach eingestellt werden und beim Upload bestimmt `fPort` dann den Typ des Sensors,
Z.B. definiert der `Typ 11` einen Sensor mit nur einem, oder auch beliebig vielen Temperatur-/Feuchte-Werten.

Das erste Byte enthält **Flags und Reason Codes**:
- **Flags:** Signalisiert Reset, Alarmstatus oder Dummy-Daten.
- **Reason Code:** Gibt den Übertragungsgrund an (z. B. automatisch oder manuell ausgelöst).

**Datenfelder:**
- `chans`: Enthält die Mess- und Housekeeping-Kanäle (HK).
- **Messkanäle (0 - 89):** Sensordaten.
- **Housekeeping-Kanäle (90 - 99):** Systemdaten (Batteriestatus, etc.).

### Beispiel einer decodierten Payload:
```javascript
{
    "flags": "(Alarm)(Measure)",       // flags: B7:(Reset) B6:(Alarm) B5:(oldAlarm) B4:(Measure)
    "reason": "(Auto)",                // reados: B0-B3, only used 1:(Auto) and 5:(Manual)
    "chans": [
      {
        "channel": 0,                  // Kanäel 0 - 89 sind Messkanäle
        "value": 20.5625,              // Hier sind 3 Messkanäle vorhanden
        "prec": "F16",                 // Typ des Kanals, aktuell "F16" oder "F32"
        "unit": "°C"                   // Bei definierten Sensoren ist/sind Einheit(en) bekannt
      },
      {
        "channel": 2,
        "value": 18.57,
        "prec": "F32",
        "unit": "°C"
      },
      {
        "channel": 15,
        "msg": "NoReply"               // Entweder ist "value" oder, wie hier, "msg" vorhanden
        "unit": "m/sec"
      },
      {
        "channel": 93,                 // Kanäle ab 90 sind HK-Kanäle      
        "unit": "mAh (HK_usedEnergy)",  // da deren Zuordnung fix ist: Beschreibung mit Einheit
        "value": 0.334717,             // Bei Fehlern "msg" anstelle von "value", wie oben
        "prec": "F16"                  // Typ für HK ist immer "F16"
      }
    ]
}
```
Kompakte Darstellung:
> - Der Gerätetyp (Einheiten) ist implizit in 'fPort' enthalten
>
> - Erstes Byte: 
>   Obere 4 Bits: Flags: 
>    128: Geräte-Reset (wird einmalig übertragen)
>     64: Alarm in aktueller Messung (sofern Gerät Alarmgrenzen hat)
>     32: Alarm in früherer Messung (wie oben, falls Übertrgaungen zuvor gescheitert sind)
>     16: Messwerte anbei
>
>   Untere 4 Bits als Zahl: Grund der Übertragung
>      2: Automatische Übertragung
>      3: Übertragung wurde manuell ausgelöst
>      andere: reserviert
>
> - Restliche Bytes (die Variable 'cursor' enthält den aktuellen Kanal (0-89, >= 90, startet bei 0)). 
>   Messwerte sind die Kanäle 0-89, >= 90-9 sind HK-Kanäle:
>   
>   Blöcke aus 1 Byte Steuercode und 1 - xxxxxx Werte mal das Format Float16 oder Float32 oder cursor (1 Byte)
>    Steuercode (binär): 0Fxxxxxx 6 Bits Anzahl  F:0:Float32, F:1:Float16 xxxxxx: Anzahl Werte (0,1-31) folgend, bei 0: cursor folgt
>    Die Floats werden als "Big Endian" (IEEE 754) im übertragen und können alternativ auch einen Fehlercode darstellen
>    
>    Steuercode (binär): 1xxxxxxxx 7 Bits Maske leitet HK-Kanäle ein. HK beginnt immer bei 90, ggfs. wird der cursor hochgesetzt
>    Jedes Maksenbit steht für einen Kanal 1: enthalten, 0: überspringen. Die HK-Kanäle werden immer als Float16 übertragen.

---

## Weiterführende Informationen

Der **LTX Payload Decoder** ist kompatibel mit gängigen LoRaWAN-Stacks und kann direkt in der **Browser-Debugger-Konsole** getestet werden.

- **Chirpstack:** Nutzt intern *QuickJS* für die Decodierung.
- **QuickJS:** Leichtgewichtiger JavaScript-Interpreter, lauffähig unter Windows, Linux & macOS.
- **Testen mit QuickJS:**
  ```bash
  ./qjs payload_ltx.js
  ```

Mehr Infos zu QuickJS:
- [QuickJS Website](https://bellard.org/quickjs/)
- [QuickJS GitHub](https://github.com/bellard/quickjs)

---

## QuickJS unter Windows nutzen

1. QuickJS-*Cosmo*-Binaries von der [QuickJS Website](https://bellard.org/quickjs/) herunterladen.
2. Entpacken und `qjs` in `qjs.exe` umbenennen.
3. Zusätzliche Dateien löschen.
4. Fertig! QuickJS ist einsatzbereit.

---

## Installation und Test - Elixir

Der Decoder ist in der selben Version auch in Elixir enthalten (`payload_ltx.exs`). Er wurde haupsächlich entwickelt für die ELEMENT IoT.Plattform.


## Testen des Decoders

- **Im Chrome-Debugger:** Datei `index.html` öffnen.
- **Lokal in der Konsole:**
  ```bash
  ./qjs payload_ltx.js
  ```
- **Hinweis:** Testbereich (bis `--- TEST-CONSOLE ---`) vor dem Einsatz in Chirpstack (oder auch TTN) entfernen.

---

## Sponsoren

### Unterstützt von

![TERRA_TRANSFER](./docu/sponsors/TerraTransfer.jpg "TERRA_TRANSFER")

[TerraTransfer GmbH, Bochum, Germany](https://www.terratransfer.org)
