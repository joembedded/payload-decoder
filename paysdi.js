/* LTX Chirpstack Payload Decoder V0.1 - toTest */

function decodeUplink(input) {
    const indata = input.bytes;
    const decoded = {};
    let cursor = 0;

    switch (input.fPort) {
        case 1:        // fPort 1: Standard
            // Byte 0: Hello-Flags
            const flags = indata[cursor++];
            let ftext = "";
            if (flags & 128) ftext += "(RESET)";
            if (flags & 64) ftext += "(ALARM)";
            else if (flags & 32) ftext += "(old ALARM)";
            if (flags & 16) ftext += "(MEASURE)";

            let reatext = "";
            switch (flags & 15) {
                case 1:
                    reatext = "(AUTO)";
                    break;
                case 5:
                    reatext = "(MANUAL)";
                    break;
                default:
                    reatext = `(REASON:${flags & 15})`;
            }
            decoded.flags = ftext;
            decoded.reason = reatext;

            while (cursor < indata.length) {
                // Read channel number (1 byte)
                const channel = indata[cursor++];
                if (channel <= 89) { // #0..89: Std-Channels
                    // Read IEEE 754 float (4 bytes, Big-Endian)
                    const floatBytes = indata.slice(cursor, cursor + 4);
                    const fdata = bytesToLTXFloat(floatBytes);
                    cursor += 4;
                    decoded[`chan_${channel}`] = fdata;
                } else if (channel <= 99) { //#90..99: HK
                    const hkdata = value2HK(channel, indata[cursor] << 8 | indata[cursor + 1]);
                    cursor += 2;
                    decoded[`hk_${channel}`] = hkdata;
                }
            }
            return {
                data: decoded
            };
        default:
            return {
                data: { error: `fPort${input.fPort} unknown` }
            };
    }
}

function value2HK(hkchan, unumber) {
    const inumber = (unumber & 0x8000) ? unumber - 0x10000 : unumber;
    switch (hkchan) {
        case 90:
            return { value: unumber / 1000.0, unit: "V(Bat)" };
        case 91:
            return { value: inumber / 10.0, unit: "°C(int.)" };
        case 92:
            return { value: unumber / 10.0, unit: "%rH(int.)" };
        case 93:
            return { value: unumber / 1.0, unit: "mAh(used)" };
        case 94:
            return { value: unumber / 10.0, unit: "mBar(Baro)" };
        default:
            return { value: unumber, unit: "(???)" };
    }
}

// Helper function to convert 4 bytes (Big-Endian) to IEEE 754 float with LTX Errorcodes
function bytesToLTXFloat(bytes) {
    if (bytes[0] == 0xFD) {
        const errno = bytes[2] << 8 | bytes[2];
        switch (errno) {
            case 1:
                return { msg: "NoValue" };
            case 2:
                return { msg: "NoReply" };
            case 3:
                return { msg: "OldValue" };
            // 4,5 unused
            case 6:
                return { msg: "ErrorCRC" };
            case 7:
                return { msg: "DataError" };
            case 8:
                return { msg: "NoCachedValue" };
            default:
                return { msg: `Err${errno}` };
        }
    }
    const view = new DataView(new ArrayBuffer(4));
    bytes.forEach((b, i) => view.setUint8(i, b));
    const f = view.getFloat32(0, false); // Big-Endian F32
    return { value: f };
}


//----------------- TESTBEREICH, NUR CONSOLE, fuer Chirpstack nachfolgenden Teil entfernen -----------------
function testDecoder(hexString) {

    const msg = hexString.replace(/\s/g, '');
    testBytes = [];
    for (let i = 0; i < msg.length; i += 2) {
        testBytes.push(parseInt(msg.substring(i, i + 2), 16));
    }
    const theObject = decodeUplink({ fPort: 1, bytes: testBytes });
    return JSON.stringify(theObject, null, 2);
}

function main() {
    console.log("---TESTDECODER---");
    
    // Testnachrichten
    const testmsg = [
        "11 00 419147A4",
        "95 00 419028F6  5A0D7B 5B00CD 5C01CF 5D0000 5E26F9"
    ];

    testmsg.forEach(e =>{
        console.log("----Test:-----");
        console.log(e);
        console.log("----Result:-----");
        console.log(testDecoder(e));
    })
}

main();

