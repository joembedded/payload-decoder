/* WRK.JS - Zum schrauben... */

function decodeUplink(input) {
	let chans = [];
	
    chans.push({name:"Temp0(°C)", value:10.3});
    chans.push({name:"Temp1(°C)", value:21.5});
    chans.push({name:"Temp2(°C)", value:12.88});
    chans.push({name:"Battery(V)", value:3.21});
    chans.push({name:"Device(°C)", value:-17.22});
	return {
        data: {
			reason: "(MANUAL)",
			flags: "ALARM",
			chans
        }
    };
};


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

