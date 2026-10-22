<?php
/**
 * Generates the local self-signed certificate used by runtime/proxy.js.
 *
 * The certificate is generated on first launch and is never committed, so
 * every installation has its own key pair.  The launchers call this script
 * automatically when runtime/tls/cert.pem or key.pem is missing.
 *
 * Usage: php runtime/tls/generate.php [host]
 */

$host = $argv[1] ?? 'ninjasage.test';
$dir = __DIR__;

$config = [
    'private_key_bits' => 2048,
    'private_key_type' => OPENSSL_KEYTYPE_RSA,
    'digest_alg' => 'sha256',
];

$key = openssl_pkey_new($config);
if ($key === false) {
    fwrite(STDERR, "No se pudo crear la clave privada: " . openssl_error_string() . PHP_EOL);
    exit(1);
}

$csr = openssl_csr_new(['commonName' => $host], $key, $config);
if ($csr === false) {
    fwrite(STDERR, "No se pudo crear el CSR: " . openssl_error_string() . PHP_EOL);
    exit(1);
}

$cert = openssl_csr_sign($csr, null, $key, 825, $config, random_int(1, PHP_INT_MAX));
if ($cert === false) {
    fwrite(STDERR, "No se pudo firmar el certificado: " . openssl_error_string() . PHP_EOL);
    exit(1);
}

if (!openssl_x509_export($cert, $certPem) || !openssl_pkey_export($key, $keyPem)) {
    fwrite(STDERR, "No se pudo exportar el certificado: " . openssl_error_string() . PHP_EOL);
    exit(1);
}

file_put_contents($dir . '/cert.pem', $certPem);
file_put_contents($dir . '/key.pem', $keyPem);
@chmod($dir . '/key.pem', 0600);

fwrite(STDOUT, "Certificado generado para {$host}" . PHP_EOL);
