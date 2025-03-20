/* LTX Chirpstack Payload Decoder 
* V1.0 (C) JoEmbedded.de 
* LTX uses a flexible, compressed format, see LTX-Documentation
* using FLoat32 and Float16 on fPort 1 */

function decodeUplink(input) { // assume inpu is valid
    switch (input.fPort) {
        case 1:        // fPort 1: LTX Standard-Uplink
            return { data: ltxDecode(input.bytes) }
        default:
            return { data: { error: `LTX: fPort:${input.fPort} unknown` } };
    }
}

function ltxDecode(indata) {
    const decoded = {};
    // Byte 0: Hello-Flags for FLAGS and REASON
    let ianz = indata.length;
    if (ianz < 1) return { error: "LTX: Payload len < 1" };
    // Transfer input bytes to BinaryArray
    const view = new DataView(new ArrayBuffer(ianz));
    let cursor = 0;
    indata.forEach((b, i) => view.setUint8(i, b));
    const flags = view.getUint8(cursor++);
    ianz--;
    decoded.flags = "";
    if (flags & 128) decoded.flags += "(Reset)";
    if (flags & 64) decoded.flags += "(Alarm)";
    else if (flags & 32) decoded.flags += "(old Alarm)";
    if (flags & 16) decoded.flags += "(Measure)";

    if ((flags & 15) == 1) decoded.reason = "(Auto)";
    else if ((flags & 15) == 5) decoded.reason = "(Manual)";
    else decoded.reason = `(REASON:${flags & 15})`;

    // Channels:0..89, HK:90..99(max 127) - Decodes V1.0 does not care extended itoks >= 128!
    let ichan = 0;
    decoded.chans = [];

    while (ianz-- > 0 && ichan < 127) {
        const itok = view.getUint8(cursor++);
        if (!(itok & 128)) {
            let cmanz = itok & 63; // Channels: number of consecutive values
            if (!cmanz) {   // cmanz=0: New channel following
                if (ianz < 1) return { error: "LTX: Format(1) invalid" };
                ichan = view.getUint8(cursor++);
                ianz--;
                break;
            }
            const f16 = itok & 64;
            while (cmanz-- > 0) {
                if (!f16) { // Following cmanz Float32
                    if (ianz < 4) return { error: "LTX: Format(2) invalid" };
                    const u32 = view.getUint32(cursor, false); // Get Float32-Bits
                    if ((u32 >>> 23) == 0x1FF) decoded.chans.push({ channel: ichan, msg: getLTXError(u32 & 0x7FFFFF) });
                    else decoded.chans.push({ channel: ichan, value: parseFloat(view.getFloat32(cursor, false).toPrecision(8)) , prec: "F32" });
                    cursor += 4;
                    ianz -= 4;
                } else { // Following cmanz Float16
                    if (ianz < 2) return { error: "LTX: Format(3) invalid" };
                    const u16 = view.getUint16(cursor, false); // Get Float16-Bits
                    if ((u16 >>> 10) == 0x3F) decoded.chans.push({ channel: ichan, msg: getLTXError(u16 & 1023) });
                    else decoded.chans.push({ channel: ichan, value: parseFloat(view.getFloat16(cursor, false)), prec: "F16" });
                    cursor += 2;
                    ianz -= 2;
                }
                ichan++;
            }
        } else { // HK, channels 90.. 
            if (ichan < 90) ichan = 90;
            let cbits = itok & 63; // HK: bitmask of consecutive values
            if (!cbits) break;   // > V1.0 - extended itoks (>=128) might follow
            while (cbits) {
                if (cbits & 1) {
                    if (ianz < 2) return { error: "LTX: Format(4) invalid Data" };
                    const u16 = view.getUint16(cursor, false); // Get Float16-Bits
                    if ((u16 >>> 10) == 0x3F) decoded.chans.push({ channel: ichan, desc: descriptionHK(ichan), msg: getLTXError(u16 & 1023) });
                    else decoded.chans.push({ channel: ichan, desc: descriptionHK(ichan), value: parseFloat(view.getFloat16(cursor, false)), prec: "F16" });
                    cursor += 2;
                    ianz -= 2;
                }
                ichan++;
                cbits >>>= 1;
            }
        }
    }
    return decoded;
}
// descHK - Description of HK-Channels
function descriptionHK(ichan) {
    switch (ichan) {
        case 90: return "HK_Bat(V)";
        case 91: return "HK_intTemp(°C)";
        case 92: return "HK_intHum.(%rH)";
        case 93: return "HK_usedEnergy(mAh)";
        case 94: return "HK_Baro(mBar)";
        default: return "HK_unknown";
    }
}
// LTX Standard Error Codes, included in F16 or F32
function getLTXError(errno) {
    switch (errno) {
        case 1: return "NoValue";
        case 2: return "NoReply";
        case 3: return "OldValue";
        // 4,5 unused
        case 6: return "ErrorCRC";
        case 7: return "DataError";
        case 8: return "NoCachedValue";
        default: return `Err${errno}`;
    }
}
// Only a few JS engines support Float16
if (!DataView.prototype.getFloat16) {
    DataView.prototype.getFloat16 = function (byteOffset, littleEndian) {
        const uint16 = this.getUint16(byteOffset, littleEndian);
        const sign = (uint16 & 0x8000) ? -1 : 1;
        const exponent = (uint16 >>> 10) & 0x1F;
        const fraction = uint16 & 0x03FF;
        if (exponent === 0) return sign * Math.pow(2, -14) * (fraction / Math.pow(2, 10)); //Subnormal
        else if (exponent === 0x1F) return fraction ? NaN : sign * Infinity; // NaN or Infinity
        return (sign * Math.pow(2, exponent - 15) * (1 + fraction / Math.pow(2, 10))).toPrecision(6);
    };
}

//----------------- TEST-CONSOLE, for Chirpstack remove the following parts: -----------------
// helper to pass test data to/from decoder
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
    console.log("---TEST-DECODER---");

    // Test-Payloads (in HEX), may contain spaces for better readability
    // taken from LTX-INTENT Data Logger (Type 1500) with 1 or 3 SDI-12-Sensors
    const testmsg = [
        "15 01 41A4E148  9F 42A3 4DA8 5172 2B3F 63E8", // Manual, Value: 20.610001, HKs: 3.31836(V), 22.6250(°C), 43.5625(%), 0.0566101(mAh), 1012.00(mBar)
        "11 42 4D24 4CE4 01 41948F5C 88 355B", // Auto 2 Values(F16): 20.5625, 19.5625, Value(F32): 18.570000 , HK: 0.334717(mAh)
        "7142FC02FC0201FF800002884479", // Alarm, Auto, 3 Values: 'No Reply', HK: 4.47266(mAH)
    ];1

    testmsg.forEach(e => {
        console.log("----Test-Payload:-----");
        console.log(e);
        console.log("----JSON Result:-----");
        console.log(testDecoder(e));
    })
}

main();
//---