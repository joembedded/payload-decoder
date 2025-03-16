### Chirpstack Payload Decoder

Für LoRaWAN (speziell Chirpstack) einen Payload-Decoder in JS zu bauen, geht am einfachsten
mit dem Chrom-Debugger. 

Chirpstack verwendet QuickJS zum ausführen des Decoders. Da Chirpstack bereits im Portal (bei den Metriken)
ein paar Info-Grafiken zeigen kann, lohnt sich das doppelt: Die decodierten Daten ("data") werden als "object" mit aufgenommen.
Die automatische Metrik bietet alle darin enthaltenen Variablen zur Anzeige an. Tiefen-Level, werden dabei via '_'
dargestellt, bsp.: aus 

```
{
  "data": {
    "chan_0": {
      "value": 18.15998077392578
    }
  }
}
```

würde dann 'chan_0_value'.

# QuickJS - Entwickeln des Decoders
QuickJS: https://bellard.org/quickjs/ und https://github.com/bellard/quickjs

Total abgefahren ist, dass man die Cosmo-QuickJS-Binaries auf allen Plattformen 
laufen lassen kann (Auf Windows dazu einfach qjs in "EXE" umbenennen und voila: Interpreter fertig!, 
die anderen Files können gelöscht werden)
(Das Ganze, dank Cosmoolitan: https://github.com/jart/cosmopolitan )

Genial! 

- Testen dann ganze einfach mit Chrome,
- Lokal ausfuehren mit: './qjs paysdi.js'
- Den unteren Teil ('TESTBEREICH') entfernen un bei Chirpstack speichern.
- Bei Laufzeit-Fehlern generiert CHirpstack einen ERROR-Event

# Das ist der Template-Vorschlag von ChirpStack:

```javascript
// Decode uplink function.
//
// Input is an object with the following fields:
// - bytes = Byte array containing the uplink payload, e.g. [255, 230, 255, 0]
// - fPort = Uplink fPort.
// - variables = Object containing the configured device variables.
//
// Output must be an object with the following fields:
// - data = Object representing the decoded payload.
function decodeUplink(input) {
    return {
        data: {
            temp: 22.5
        }
    };
}

// Encode downlink function.
//
// Input is an object with the following fields:
// - data = Object representing the payload that must be encoded.
// - variables = Object containing the configured device variables.
//
// Output must be an object with the following fields:
// - bytes = Byte array containing the downlink payload.
function encodeDownlink(input) {
    return {
        bytes: [225, 230, 255, 0]
    };
}
```

