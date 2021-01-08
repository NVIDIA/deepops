#!/usr/bin/env bash

CA_CRT_OUTFILE="${CA_CRT_OUTFILE:-/tmp/ca.crt}"
CA_KEY_OUTFILE="${CA_KEY_OUTFILE:-/tmp/ca.key}"

echo "Generating CA key"
openssl genrsa -des3 -passout pass:foobar -out ${CA_KEY_OUTFILE} 4096

echo "Generating CA certificate"
openssl req -new -x509 -days 1300 -sha256 -key ${CA_KEY_OUTFILE} -out ${CA_CRT_OUTFILE} -passin pass:foobar -subj "/C=US/ST=California/L=Santa Clara/O=DeepOps/OU=HPC/CN=DeepOps" -extensions IA -config <(
cat <<-EOF
[req]
distinguished_name = dn
[dn]
[IA]
basicConstraints = critical,CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
subjectKeyIdentifier = hash
EOF
)

echo "CA key written out to: ${CA_KEY_OUTFILE}"
echo "CA crt written out to: ${CA_CRT_OUTFILE}"
