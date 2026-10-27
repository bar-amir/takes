#!/bin/zsh
# One-time setup: stores the release signing secrets in the GitHub "release" environment.
# Run it yourself in Terminal; it never prints a secret.
#
# You need:
#   1. Your Developer ID certificate exported as a .p12 with a password
#      (Keychain Access › My Certificates › right-click "Developer ID Application: Bar Amir" › Export).
#   2. An App Store Connect API key for notarization: App Store Connect › Users and Access ›
#      Integrations › App Store Connect API › Team Keys › +, role "Developer". Download the .p8
#      (you can only download it once) and note its Key ID and the Issuer ID shown above the list.
#   3. The Sparkle update key, which is read from your keychain (account "takes").
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=bar-amir/takes
ENV=release
put() { gh secret set "$1" --env "$ENV" --repo "$REPO" }

print "Storing secrets in the \"$ENV\" environment of $REPO.\n"

read "P12_PATH?Path to the exported .p12: "
P12_PATH=${~P12_PATH}
[[ -f "$P12_PATH" ]] || { print "No file at $P12_PATH"; exit 1 }
read -s "P12_PASSWORD?Password you set when exporting the .p12: "; print
openssl pkcs12 -in "$P12_PATH" -nokeys -passin "pass:$P12_PASSWORD" -legacy >/dev/null 2>&1 \
  || openssl pkcs12 -in "$P12_PATH" -nokeys -passin "pass:$P12_PASSWORD" >/dev/null 2>&1 \
  || { print "That password doesn't open the .p12."; exit 1 }
base64 -i "$P12_PATH" | put DEVELOPER_ID_P12_BASE64
print -rn -- "$P12_PASSWORD" | put DEVELOPER_ID_P12_PASSWORD
unset P12_PASSWORD

read "P8_PATH?Path to the App Store Connect API key (.p8): "
P8_PATH=${~P8_PATH}
[[ -f "$P8_PATH" ]] || { print "No file at $P8_PATH"; exit 1 }
read "KEY_ID?Key ID: "
read "ISSUER_ID?Issuer ID: "
print "Checking the API key with Apple…"
xcrun notarytool history --key "$P8_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID" >/dev/null \
  || { print "Apple didn't accept that API key."; exit 1 }
base64 -i "$P8_PATH" | put NOTARY_API_KEY_BASE64
print -rn -- "$KEY_ID" | put NOTARY_API_KEY_ID
print -rn -- "$ISSUER_ID" | put NOTARY_API_ISSUER_ID

print "Reading the Sparkle update key from your keychain…"
SPARKLE_EXPORT=$(mktemp)
chmod 600 "$SPARKLE_EXPORT"
rm -f "$SPARKLE_EXPORT"
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account takes -x "$SPARKLE_EXPORT" >/dev/null
put SPARKLE_PRIVATE_KEY < "$SPARKLE_EXPORT"
rm -f "$SPARKLE_EXPORT"

print "\nDone. Secrets in the \"$ENV\" environment:"
gh secret list --env "$ENV" --repo "$REPO"
print "\nKeep a backup of the Sparkle key in 1Password: without it, installed copies can never be updated."
print "  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account takes -x ~/Desktop/takes-sparkle-key.txt"
print "Then store that file's contents in 1Password and delete the file."
