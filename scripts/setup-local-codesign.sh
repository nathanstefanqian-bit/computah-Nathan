#!/bin/zsh
set -eu

identity="Computah Local Code Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$keychain" |
    awk -F'"' -v name="$identity" '$2 == name { found=1 } END { exit !found }'
then
    print "$identity already exists."
    exit 0
fi

work="$(mktemp -d /tmp/computah-codesign.XXXXXX)"
trap 'rm -rf "$work"' EXIT
password="$(uuidgen)$(uuidgen)"

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -subj "/CN=$identity/O=Computah Local Development" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -passout "pass:$password" \
    -inkey "$work/key.pem" -in "$work/cert.pem" \
    -name "$identity" -out "$work/identity.p12"
security import "$work/identity.p12" -k "$keychain" -P "$password" \
    -T /usr/bin/codesign >/dev/null

print "Created $identity in the login keychain."
print "Run zsh scripts/build.sh, then grant Accessibility to outputs/Computah.app once."
