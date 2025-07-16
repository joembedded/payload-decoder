// ---Auto made (./makec.bat)---
/* LTX  Payload Decoder (Uplink)
* V1.17 (C) JoEmbedded.de 
* https://github.com/joembedded/payload-decoder
* LTX uses a flexible, compressed format, see LTX-Documentation
* using FLoat32 and Float16 on fPort 1-199 (fPort sets the 'units')
*/

// ChirpStack V4
function decodeUplink(input) { // assume input is valid
    if ((input.fPort > 0) && (input.fPort < 200)) {
        // fPort 1-199: LTX Standard-Uplink, Port defines 'known types'
        return { data: Decoder(input.bytes, input.fPort) }
    } else {
        return { data: { errors: [`LTX: fPort:${input.fPort} unknown`] } };
    }
}

// TTN / Chirpstack
function Decoder(bytes, port) {
    const decoded = {};
    // Byte 0: Hello-Flags for FLAGS and REASON
    let ianz = bytes.length;
    if (ianz < 1) return { errors: ["LTX: Payload len < 1"] };
    if (port < 1 || port > 199) return { errors: [`LTX: fPort:${port} unknown`] };

    // Transfer input bytes to BinaryArray
    const view = new DataView(new ArrayBuffer(ianz));
    let cursor = 0;
    bytes.forEach((b, i) => view.setUint8(i, b));
    const flags = view.getUint8(cursor++);
    ianz--;
    decoded.flags = "";
    if (flags & 128) decoded.flags += "(Reset)";
    if (flags & 64) decoded.flags += "(Alarm)";
    else if (flags & 32) decoded.flags += "(old Alarm)";
    if (flags & 16) decoded.flags += "(Measure)";

    const reason = flags & 15;
    if (reason === 2) decoded.reason = "(Auto)";
    else if (reason === 3) decoded.reason = "(Manual)";
    else decoded.reason = `(Reason:${reason}?)`;

    // Channels:0..89, HK:90..99(max 127) - Decoder V1.x does not care extended itoks >= 128!
    let ichan = 0;
    const typeunits = deftypes[port];
    let dtidx = 0;  // Index in deftypes
    decoded.chans = [];
    while (ianz-- > 0 && ichan < 128) {
        const itok = view.getUint8(cursor++);
        if (!(itok & 128)) {
            let cmanz = itok & 63; // Channels: number of consecutive values
            if (!cmanz) {   // cmanz=0: New channel following
                if (ianz < 1) return { errors: ["LTX: Format(1) invalid"] };
                ichan = view.getUint8(cursor++); // AutoEnd for ichan >= 128
                ianz--;
                break;
            }
            const f16 = itok & 64;
            while (cmanz-- > 0) {
                const puob = { channel: ichan };
                if (typeunits && typeunits.length && typeunits.length > 0) { // Known Type with units
                    puob.unit = typeunits[dtidx % (typeunits.length)];
                }
                if (!f16) { // Following cmanz Float32
                    if (ianz < 4) return { errors: ["LTX: Format(2) invalid"] };
                    puob.prec = "F32";
                    const u32 = view.getUint32(cursor, false); // Get Float32-Bits
                    if ((u32 >>> 23) == 0x1FF) puob.msg = getLTXError(u32 & 0x7FFFFF);
                    else puob.value = parseFloat(view.getFloat32(cursor, false).toPrecision(8));
                    cursor += 4;
                    ianz -= 4;
                } else { // Following cmanz Float16
                    if (ianz < 2) return { errors: ["LTX: Format(3) invalid"] };
                    puob.prec = "F16";
                    const u16 = view.getUint16(cursor, false); // Get Float16-Bits
                    if ((u16 >>> 10) == 0x3F) puob.msg = getLTXError(u16 & 1023);
                    else  puob.value = parseFloat(view.getFloat16(cursor, false));
                    cursor += 2;
                    ianz -= 2;
                }
                if (('value' in puob) && !Number.isFinite(puob.value)) {
                    delete puob.value;
                    puob.msg = getLTXError(0);
                }
                decoded.chans.push(puob);
                dtidx++;
                ichan++;
            }
        } else { // HK, channels 90.. 
            if (ichan < 90) ichan = 90;
            let cbits = itok & 127; // HK: 7-bit mask of consecutive values
            for(let i=0;i<7;i++){
                if (cbits & 1) {
                    if (ianz < 2) return { errors: ["LTX: Format(4) invalid Data"] };
                    const puob = { channel: ichan, prec: "F16", unit: unitDescrHK(ichan) };
                    const u16 = view.getUint16(cursor, false); // Get Float16-Bits
                    if ((u16 >>> 10) == 0x3F) puob.msg = getLTXError(u16 & 1023);
                    else {
                        puob.value = parseFloat(view.getFloat16(cursor, false));
                        if(!Number.isFinite(puob.value)) {
                            delete puob.value;
                            puob.msg = getLTXError(0);
                        }
                    }
                    decoded.chans.push(puob);
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
// List of 'known types' with (opt. repeated) units - LTX-Sensors
const deftypes = {
    // 1-9 free or for  custom sensors
    10: ['°C'], // 10: All channels are Temperatures
    11: ['%rH', '°C'], // 11: rH/T-Sensor
    12: ['Bar', '°C'], // 12: Pressure/Level Sensor Bar
    13: ['m', '°C'], // 13: Level Sensor m
    14: ['m', 'dBm'], // 14: Distance(s) Sensor (Radar)
    15: ['°C', 'uS/cm'], // 15: Water Conductivity (ES-2)
};

// descHK - Unit and Description of HK-Channels
function unitDescrHK(ichan) {
    switch (ichan) {
        case 90: return "V(HK_Bat)";
        case 91: return "°C(HK_intTemp)";
        case 92: return "%rH(HK_intHum.)";
        case 93: return "mAh(HK_usedEnergy)";
        case 94: return "mBar(HK_Baro)";
        default: return "HK_unknown";
    }
}
// LTX Standard Error Codes, included in F16 or F32
function getLTXError(errno) {
    switch (errno) {
        case 0: return "NumberOverflow"; // CodecError
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
    }
}

