# Chirpstack LTX Payload Decoder

## Überblick

Payload-Decoder gelten oft als kompliziert – und das nicht ohne Grund. In der Welt von LoRaWAN zählt jedes Byte, denn der Energieverbrauch steigt mit der Länge der übertragenen Daten. Ziel ist es daher, mit minimalem Speicheraufwand möglichst viele Informationen zu transportieren. Doch die Vielzahl an Umrechnungsverfahren und das Fehlen standardisierter Fehlermeldungen machen die Dekodierung oft unübersichtlich und fehleranfällig.  

Ein Beispiel: Eine Temperatur lässt sich effizient als 16-Bit-Integer mit Skalierung übertragen. Dasselbe Format könnte auch für eine Batteriespannung genutzt werden – doch hier wäre eine völlig andere Skalierung erforderlich. Einheitliche Fehlercodes lassen sich in solchen festen Formaten kaum umsetzen.  

In der Praxis genügt für viele Messwerte – etwa Temperaturen, Feuchtigkeiten oder Distanzen – eine Genauigkeit von 0,05 %. Die LTX-Logger setzen daher auf 16-Bit-Gleitkommazahlen, um eine einheitliche Darstellung zu gewährleisten. Ein zusätzlicher Vorteil: Fehlercodes lassen sich verlustfrei integrieren, indem der reservierte "NaN"-Bereich von Gleitkommazahlen genutzt wird.  

Nur dort, wo eine höhere Auflösung explizit erforderlich ist, kommen 32-Bit-Gleitkommazahlen zum Einsatz. So bleibt die Datenübertragung effizient, ohne auf Präzision zu verzichten.  

## Highlights des LTX Payload Decoders

- **Messwerte als Fließkommazahlen** (wahlweise **16-Bit oder 32-Bit** je nach Genauigkeitsanforderung).
- **Strukturierte Messwerte als Array**, erleichtert die automatisierte Verarbeitung.
- **Klartext-Fehlermeldungen**, z. B. bei Sensorausfällen.
- **Trennung von Messwerten und Systemdaten** (*Housekeeping-Werte* wie z.B. Batteriespannung).
- **Minimaler Speicherbedarf**, optimiert für LoRaWAN oder Satelliten-Kommunikation 

---

## Installation und Test

Der Decoder (`payload_ltx.js`) enthält eine integrierte **Testroutine**, die im Browser oder in der Konsole ausgeführt werden kann. Für den Einsatz in Chirpstack oder TTN muss der **Testbereich entfernt** werden (bis `--- TEST-CONSOLE ---`).

Dann einfach diesen oberen Teil als **CODEC** im Chirpstack (oder auch TTN) abspeichern.

- **Fehlermeldungen:** Chirpstack generiert automatisch `ERROR`-Events bei Laufzeitfehlern.

---

## Decodierte Datenstruktur

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
        "prec": "F16"                  // Typ des Kanals, aktuell "F16" oder "F32"
      },
      {
        "channel": 2,
        "value": 18.57,
        "prec": "F32"
      },
      {
        "channel": 15,
        "msg": "NoReply"               // Entweder ist "value" oder, wie hier, "msg" vorhanden
      },
      {
        "channel": 93,                 // Kanäle ab 90 sind HK-Kanäle      
        "desc": "HK_usedEnergy(mAh)",  // da deren Zuordnung fix ist: Beschreibung mit Einheit
        "value": 0.334717,             // Bei Fehlern "msg" anstelle von "value", wie oben
        "prec": "F16"                  // Typ für HK ist immer "F16"
      }
    ]
}
```

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

## Testen des Decoders

- **Im Chrome-Debugger:** Datei `index.html` öffnen.
- **Lokal in der Konsole:**
  ```bash
  ./qjs payload_ltx.js
  ```
- **Hinweis:** Testbereich vor dem Einsatz in Chirpstack entfernen.

---

## Sponsoren

### Unterstützt von

![TERRA_TRANSFER](./docu/sponsors/TerraTransfer.jpg "TERRA_TRANSFER")

[TerraTransfer GmbH, Bochum, Germany](https://www.terratransfer.org)

