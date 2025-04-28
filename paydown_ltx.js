/* LTX  Payload Decoder (Downlink)
* V1.16 (C) JoEmbedded.de 
* https://github.com/joembedded/payload-decoder
* Downlink 'cmd' as string, sent on fPort 10
* 
* INFO: 
* - TTN V4 supports 'errors/warnings:[]', Chirpstack V4 currently not
* - ChirpStack V4 only requires 'encodeDownlink()', but not 'decodeDownlink()'
* - ChirpStack holds Uplink/Downlink in one file, TTN requires 2 separate files for Uplink/Downlink
*
* Installation:
* - ChirpStack: copy 'encodeDownlink()' into the common payload decoder
* - TTN: copy this cruft as downlink payload decoder
*/

// TTN V4 / ChirpStack - Downlink Human to Bytes
function encodeDownlink(input) {
    const cmd = input.data.cmd;

    const encodedRes = {};
    if (!input.data || typeof input.data.cmd !== 'string') {
        encodedRes.errors = ["LTX: Missing or invalid 'cmd' field"]; // Errors brechen Downlink ab
    } else {
        let cbytes = [];
        if(input.fPort !== undefined && input.fPort != 10) encodedRes.warnings = [`LTX: fPort:${input.fPort} set to 10`];
        encodedRes.fPort = 10;	// LTX General CMD Port: 10
        let cl = cmd.length;
        if (cl < 1) encodedRes.warnings = ["LTX: Zero-length 'cmd'"];
        else if (cl > 51) {     // LTX max. CMD Len: 51 Bytes
            encodedRes.warnings = [`LTX: 'cmd' (length ${cl}) truncated to size 51`];
            cl = 51;
        }
        for (let i = 0; i < cl; i++) {
            cbytes.push(cmd.charCodeAt(i));
        }
        encodedRes.bytes = cbytes;
    }
    return encodedRes;
}

// TTN V4 - Downlink (back) Bytes to Human (only informative, for displaying it in the console)
function decodeDownlink(input) {
    const decodedRes = {};
    if(input.fPort !== 10) decodedRes.errors = [`LTX: fPort:${input.fPort} unknown`];  // LTX General CMD Port: 10
    else decodedRes.data = { cmd: String.fromCharCode(...input.bytes) };
    return decodedRes;
}

// Test: `{ "cmd": "p 300" }` should output `70 20 33 30 30`