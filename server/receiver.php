<?php

declare(strict_types=1);

/**
 * receiver.php — minimal self-hosted receiver for the AWACS endpoint contract.
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
 *   POST file=tmp/wifi.tmp&data=<cell>  overwrite atomically (temp file + rename)
 *   POST without a `file` field         400 "Error: no operation" — the device uses this
 *                                       exact reply as its "site reachable" check and as
 *                                       the target of its upload-speed probe (a raw body)
 *   POST file=<anything else>           403 "Error: forbidden file"
 *   GET                                 400 "Error: no operation"
 *
 * NO AUTHENTICATION: anyone who can reach this URL can append to the log and overwrite
 * the WiFi cell. Put it behind a firewall, a VPN or a proxy that adds auth (SECURITY.md).
 */

const LOG_CAP_BYTES  = 262144;  // 256 KB
const MAX_DATA_BYTES = 65536;   // one log line or one WiFi cell
const ALLOWED_FILES  = ['log/log.txt' => 'append', 'tmp/wifi.tmp' => 'overwrite'];

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
    if (!is_scalar($_POST['file']) || !is_scalar($_POST['data'] ?? '')) {
        reply(400, "Error: bad request\n");
    }
    $file = (string) $_POST['file'];
    $data = (string) ($_POST['data'] ?? '');
    if (strlen($data) > MAX_DATA_BYTES) {
        reply(400, "Error: too large\n");
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
function writeAtomic(string $path, string $data): bool
{
    if (!ensureDir(dirname($path))) {
        return false;
    }
    $tmp = $path . '.tmp.' . getmypid() . '.' . mt_rand();
    if (@file_put_contents($tmp, $data, LOCK_EX) !== strlen($data)) {
        @unlink($tmp);
        return false;
    }
    if (!@rename($tmp, $path)) {
        @unlink($tmp);
        return false;
    }
    @chmod($path, 0644);
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
