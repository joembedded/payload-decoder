<?php
// filepath: remove_testblock.php 
// Write clean payload-decode for Chirpstack:
// Copy  'payload_ltx.js' => 'payload_ltx_clean.js', remove "REMOVE"-Blocks
// Call via 'makec'!

$input_file = 'payload_ltx.js';
$output_file = 'payload_ltx_clean.js';

$in = fopen($input_file, 'r');
$out = fopen($output_file, 'w');

$remove = false;
fwrite($out, "// ---Auto made (./makec.bat)---\n");
while (($line = fgets($in)) !== false) {
    if (strpos($line, '//REMOVE-START') !== false) {
        $remove = true;
        continue;
    }
    if (strpos($line, '//REMOVE-END') !== false) {
        $remove = false;
        continue;
    }
    if (!$remove) {
        fwrite($out, $line);
    echo "$line";
    }else{
        echo "(ignored)$line";
    }
}

fclose($in);
fclose($out);
?>