<?php
// PHP built-in server (php -S 127.0.0.1:PORT index.php): one process, one request at a time.
// default_charset is cleared so the Content-Type is exactly the contract's "text/plain"
// (PHP otherwise appends ";charset=utf-8" to a text/* header it sends).
ini_set('default_charset', '');
header('Content-Type: text/plain');
header('Content-Length: 13');
echo "hello, world\n";
