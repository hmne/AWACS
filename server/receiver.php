<?php

declare(strict_types=1);

/**
 * receiver.php - minimal self-hosted receiver for the AWACS endpoint contract.
 *
 * PHP 7.4 or newer. One file, no dependencies, no database.
 *
 * Two ways to host it:
 *
 *   1. Behind Apache or nginx: copy it as  <docroot>/<DEVICE_ID>/receiver.php  (or the name you set in SITE_API).
 *      Data lands BESIDE the file:  <DEVICE_ID>/log/log.txt  and  <DEVICE_ID>/tmp/wifi.tmp .
 *      SITE_URL on the device is then the docroot URL.
 *
 *   2. PHP's built-in server, one process for every device id:
 *        php -S 0.0.0.0:8080 receiver.php
 *      The script acts as the router: it answers  /<DEVICE_ID>/receiver.php  for any
 *      id and keeps the data in  data/<DEVICE_ID>/...  beside this file.
 *
 * The contract (what awacs.sh sends):
 *   POST file=log/log.txt&data=<line>   append <line> + newline; the file is kept under
 *                                       256 KB (the oldest lines are dropped)
 *   POST file=tmp/wifi_scan.tmp&data=<list> overwrite atomically (the networks the radio heard)
 *   POST file=tmp/wifi.tmp&data=<cell>  overwrite atomically (temp file + rename)
 *   POST file=tmp/wifi_state.tmp&data=<answer> overwrite atomically (the device's answer to
 *                                       a site command: scan, switch or join)
 *   POST file=wifi_key&data=<64 hex>    register the device key that opens a password typed
 *        [&proof=<hex>]                 on a site. Not a file under the data tree: it lands in
 *                                       private/wifi.key (0600, denied to browsers). The first
 *                                       key is taken; the same key again answers 200; a
 *                                       different key needs proof = HMAC-SHA256(old key bytes,
 *                                       new key hex) or gets 403 "Error: proof required";
 *                                       anything but 64 lowercase hex is 400 "Error: bad key"
 *   POST without a `file` field         400 "Error: no operation" - the device uses this
 *                                       exact reply as its "site reachable" check and as
 *                                       the target of its upload-speed probe (a raw body)
 *   POST file=<anything else>           403 "Error: forbidden file"
 *   GET                                 400 "Error: no operation"
 *
 * NO AUTHENTICATION: anyone who can reach this URL can append to the log, overwrite the
 * WiFi cell and, before the device does, register a key. Put it behind a firewall, a VPN
 * or a proxy that adds auth (SECURITY.md).
 */

const LOG_CAP_BYTES  = 262144;  // 256 KB
const MAX_DATA_BYTES = 65536;   // one log line or one WiFi cell
const ALLOWED_FILES  = [
    'log/log.txt'        => 'append',
    'tmp/wifi.tmp'       => 'overwrite',
    'tmp/wifi_scan.tmp'  => 'overwrite',
    'tmp/wifi_state.tmp' => 'overwrite',
];
const KEY_FILE       = 'private/wifi.key';   // the device key: never a name the device can write as a file

// Headless endpoint: an error must never render into the reply the device parses.
ini_set('display_errors', '0');
ini_set('log_errors', '1');

main();

/** Route one request to one whitelisted file operation, or to a contract error. */
function main(): void
{
    header('Content-Type: text/plain; charset=UTF-8');
    header('X-Content-Type-Options: nosniff');

    $dataDir = resolveDataDir();
    if ($dataDir === null) {
        reply(404, "Error: not found\n");
    }
    if (!isset($_POST['file'])) {
        reply(400, "Error: no operation\n");
    }
    // Reject array file[]/data[] before the (string) cast: no warning spam, no literal "Array".
    if (!is_scalar($_POST['file']) || !is_scalar($_POST['data'] ?? '') || !is_scalar($_POST['proof'] ?? '')) {
        reply(400, "Error: bad request\n");
    }
    $file = (string) $_POST['file'];
    $data = (string) ($_POST['data'] ?? '');
    if (strlen($data) > MAX_DATA_BYTES) {
        reply(400, "Error: too large\n");
    }
    // The key registration is not a file write: it is handled before the whitelist and never
    // lands under a path the device could also name in `file=`.
    if ($file === 'wifi_key') {
        registerKey($dataDir, $data, (string) ($_POST['proof'] ?? ''));
    }
    // Exact-path whitelist: traversal is moot, every other name is forbidden.
    if (!isset(ALLOWED_FILES[$file])) {
        reply(403, "Error: forbidden file\n");
    }

    $full = $dataDir . '/' . $file;
    $ok   = ALLOWED_FILES[$file] === 'append'
        ? appendLine($full, $data . "\n")
        : writeAtomic($full, $data);
    if (!$ok) {
        reply(500, "Error: write failed\n");
    }
    reply(200, "OK\n");
}

/**
 * Register the device key (64 lowercase hex). The first key is taken; the same key again is
 * a 200 with no write; a different key must carry proof = HMAC-SHA256(old key raw bytes,
 * new key hex as ASCII) or it is refused, so an unauthenticated POST cannot swap the key
 * and read the next password typed on a site. The value is never echoed or logged.
 */
function registerKey(string $dataDir, string $key, string $proof): void
{
    if (!preg_match('/^[0-9a-f]{64}$/', $key)) {
        reply(400, "Error: bad key\n");
    }
    $path = $dataDir . '/' . KEY_FILE;
    $old  = is_file($path) ? trim((string) @file_get_contents($path)) : '';
    if ($old !== '') {
        if (hash_equals($old, $key)) {
            reply(200, "OK\n");
        }
        $want = hash_hmac('sha256', $key, (string) hex2bin($old));
        if (!preg_match('/^[0-9a-fA-F]{64}$/', $proof) || !hash_equals($want, strtolower($proof))) {
            error_log('receiver: key registration refused (proof missing or wrong)');
            reply(403, "Error: proof required\n");
        }
    }
    if (!ensureDir(dirname($path)) || !denyBrowsers(dirname($path)) || !writeAtomic($path, $key . "\n", 0600)) {
        reply(500, "Error: write failed\n");
    }
    reply(200, "OK\n");
}

/**
 * Under Apache the data lands beside this script inside the docroot, so the key's directory
 * gets a .htaccess that denies every request (Apache 2.4 syntax). nginx ignores that file:
 * there, deny the private/ location yourself (server/README.md). Written once.
 */
function denyBrowsers(string $dir): bool
{
    $file = $dir . '/.htaccess';
    if (is_file($file)) {
        return true;
    }
    return @file_put_contents($file, "Require all denied\n", LOCK_EX) !== false;
}

/** Send the status and body, then stop. */
function reply(int $code, string $body): void
{
    http_response_code($code);
    echo $body;
    exit;
}

/**
 * Where this device's files live: beside the script when a web server (or PHP's
 * built-in server with a document root) serves it as a plain file, or data/<id>/
 * when the script is the router of PHP's built-in server. Null = not a device path
 * (only possible in router mode).
 */
function resolveDataDir(): ?string
{
    if (PHP_SAPI !== 'cli-server') {
        return __DIR__;
    }
    $path = parse_url((string) ($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH);
    if (!is_string($path)) {
        return null;
    }
    // php -S HOST:PORT -t DIR: the request names this very file under the document root.
    $docRoot = (string) ($_SERVER['DOCUMENT_ROOT'] ?? '');
    if ($docRoot !== '' && realpath($docRoot . $path) === __FILE__) {
        return __DIR__;
    }
    // php -S HOST:PORT receiver.php: this file answers every path; keep each device apart.
    if (!preg_match('#^/([A-Za-z0-9_-]{1,32})/receiver\.php$#', $path, $m)) {
        return null;
    }
    return __DIR__ . '/data/' . $m[1];
}

function ensureDir(string $dir): bool
{
    return is_dir($dir) || @mkdir($dir, 0755, true) || is_dir($dir);
}

/** Overwrite through a temp file in the same directory, then rename: never a half-written cell. */
function writeAtomic(string $path, string $data, int $mode = 0644): bool
{
    if (!ensureDir(dirname($path))) {
        return false;
    }
    $tmp = $path . '.tmp.' . getmypid() . '.' . mt_rand();
    if ($mode !== 0644) {   // the key must not sit world-readable even before the rename
        @touch($tmp);
        @chmod($tmp, $mode);
    }
    if (@file_put_contents($tmp, $data, LOCK_EX) !== strlen($data)) {
        @unlink($tmp);
        return false;
    }
    if (!@rename($tmp, $path)) {
        @unlink($tmp);
        return false;
    }
    @chmod($path, $mode);
    return true;
}

/** Append one line under an exclusive lock, then keep the file under the cap. */
function appendLine(string $path, string $line): bool
{
    if (!ensureDir(dirname($path))) {
        return false;
    }
    $handle = @fopen($path, 'c+');
    if ($handle === false) {
        return false;
    }
    if (!flock($handle, LOCK_EX)) {
        fclose($handle);
        return false;
    }
    fseek($handle, 0, SEEK_END);
    $ok = fwrite($handle, $line) === strlen($line) && fflush($handle);
    if ($ok) {
        capLog($handle);
    }
    flock($handle, LOCK_UN);
    fclose($handle);
    return $ok;
}

/**
 * Keep the log bounded: once it passes twice the cap, keep the newest LOG_CAP_BYTES,
 * drop the partial first line, and rewrite in place (the lock is still held).
 *
 * @param resource $handle open read/write handle, locked by the caller
 */
function capLog($handle): void
{
    $stat = fstat($handle);
    if ($stat === false || $stat['size'] <= LOG_CAP_BYTES * 2) {
        return;
    }
    fseek($handle, -LOG_CAP_BYTES, SEEK_END);
    $tail = (string) fread($handle, LOG_CAP_BYTES);
    $nl   = strpos($tail, "\n");
    if ($nl !== false) {
        $tail = substr($tail, $nl + 1);
    }
    ftruncate($handle, 0);
    rewind($handle);
    fwrite($handle, $tail);
    fflush($handle);
}
