#!/bin/zsh
# One-time setup for automated releases. Run it yourself in Terminal; it never prints a secret.
#
# It:
#   1. generates a password for your Developer ID .p12 and saves it to 1Password, then puts it on
#      the clipboard so you only paste it into Keychain Access's export dialog;
#   2. waits for the exported .p12 and checks it contains the private key;
#   3. finds your App Store Connect API key (AuthKey_<KEY ID>.p8) in Downloads and checks it with Apple;
#   4. stores everything as secrets in the GitHub "release" environment;
#   5. backs up the .p12, the API key and the Sparkle update key to 1Password;
#   6. deletes the exported files.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=bar-amir/takes
ENV=release
OP_ACCOUNT=my.1password.com
OP_VAULT=Private
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"; pbcopy < /dev/null' EXIT

say() { print -P "\n%B$1%b" }
put() { gh secret set "$1" --env "$ENV" --repo "$REPO" }
op_() { op --account "$OP_ACCOUNT" "$@" }

say "Checking tools…"
gh auth status >/dev/null 2>&1 || { print "Sign in to GitHub first: gh auth login"; exit 1 }
op_ vault get "$OP_VAULT" >/dev/null || { print "Can't open the \"$OP_VAULT\" vault in $OP_ACCOUNT. Unlock 1Password and try again."; exit 1 }
[[ -x "$SPARKLE_BIN/generate_keys" ]] || swift package resolve >/dev/null

# 1. Password for the .p12, saved to 1Password first so it's never lost.
#    On a re-run, the password saved last time is reused (and so is the .p12 exported with it).
P12_ITEM="Takes – Developer ID .p12 password"
if P12_PASSWORD=$(op_ item get "$P12_ITEM" --vault "$OP_VAULT" --fields password --reveal 2>/dev/null) && [[ -n "$P12_PASSWORD" ]]; then
  say "1/6  Reusing the certificate password saved in 1Password last time."
  REUSED=true
else
  REUSED=false
  say "1/6  Creating a password for the certificate export…"
  P12_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-28)
cat > "$WORK/p12-password.json" <<JSON
{"title":"Takes – Developer ID .p12 password","category":"PASSWORD",
 "fields":[{"id":"password","type":"CONCEALED","purpose":"PASSWORD","label":"password","value":"$P12_PASSWORD"}],
 "notesPlain":"Password of the exported Developer ID Application: Bar Amir (K4AVRTQ2MY) certificate, used by the Takes release workflow."}
JSON
op_ item create --vault "$OP_VAULT" --template "$WORK/p12-password.json" >/dev/null
rm -f "$WORK/p12-password.json"
print "Saved in 1Password: \"Takes – Developer ID .p12 password\"."
fi

has_key() { openssl pkcs12 -in "$P12" -nocerts -nodes -passin "pass:$P12_PASSWORD" "$@" 2>/dev/null | grep -q "PRIVATE KEY" }

# 2. Export the .p12 in Keychain Access (skipped if a .p12 from last time opens with the password).
P12=""
if $REUSED; then
  for f in ~/Desktop/*.p12(N.om); do
    P12=$f
    if has_key || has_key -legacy; then break; fi
    P12=""
  done
fi
if [[ -n "$P12" ]]; then
  say "2/6  Using $(basename "$P12") from your Desktop (exported last time)."
else
print -rn -- "$P12_PASSWORD" | pbcopy
START=$(date +%s)
say "2/6  Export the certificate (the password is on your clipboard):"
print "   • Keychain Access opens. Choose \"login\" in the sidebar, then the \"My Certificates\" tab."
print "   • Right-click \"Developer ID Application: Bar Amir (K4AVRTQ2MY)\" › Export."
print "   • File Format: Personal Information Exchange (.p12). Save it to the Desktop."
print "   • In both password fields press ⌘V. If asked, enter your Mac password and click Allow."
print "   (If .p12 is greyed out, run this in a new Terminal tab instead:"
print "    security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P \"\$(pbpaste)\" -o ~/Desktop/takes-developer-id.p12 )"
print "\nWaiting for the .p12 on your Desktop…"
open -a "Keychain Access"
while [[ -z "$P12" ]]; do
  sleep 2
  for f in ~/Desktop/*.p12(N.); do
    (( $(stat -f %m "$f") >= START )) && P12=$f
  done
done
pbcopy < /dev/null
sleep 1
if ! has_key && ! has_key -legacy; then
  print "That .p12 doesn't open with the generated password, or has no private key."
  print "Export it from the \"My Certificates\" tab (the one with the key) and paste the password again."
  exit 1
fi
print "Found $(basename "$P12") with the private key."
fi

# 3. App Store Connect API key.
say "3/6  App Store Connect API key…"
P8=(~/Downloads/AuthKey_*.p8(N.om))
[[ ${#P8[@]} -gt 0 ]] || { print "No AuthKey_*.p8 in Downloads."; exit 1 }
P8=$P8[1]
KEY_ID=${${P8:t:r}#AuthKey_}
print "Using $(basename "$P8") (Key ID $KEY_ID)."
read -k -t 0.1 -s 2>/dev/null || true   # drop anything typed while waiting
while true; do
  read "ISSUER_ID?Paste the Issuer ID (App Store Connect › Users and Access › Integrations, above the keys list): "
  # Keep only the UUID, so stray characters (e.g. from a Hebrew keyboard) don't break it.
  ISSUER_ID=$(print -r -- "$ISSUER_ID" | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true)
  [[ -n "$ISSUER_ID" ]] && break
  print "That doesn't look like an Issuer ID (a UUID like 1a2b3c4d-…). Try again."
done
xcrun notarytool history --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER_ID" >/dev/null \
  || { print "Apple didn't accept the key with that Issuer ID."; exit 1 }
print "Apple accepted the API key."

# 4. GitHub secrets.
say "4/6  Storing secrets in GitHub (\"$ENV\" environment)…"
base64 -i "$P12" | put DEVELOPER_ID_P12_BASE64
print -rn -- "$P12_PASSWORD" | put DEVELOPER_ID_P12_PASSWORD
base64 -i "$P8" | put NOTARY_API_KEY_BASE64
print -rn -- "$KEY_ID" | put NOTARY_API_KEY_ID
print -rn -- "$ISSUER_ID" | put NOTARY_API_ISSUER_ID
SPARKLE_FILE=$WORK/takes-sparkle-key.txt
"$SPARKLE_BIN/generate_keys" --account takes -x "$SPARKLE_FILE" >/dev/null
chmod 600 "$SPARKLE_FILE"
put SPARKLE_PRIVATE_KEY < "$SPARKLE_FILE"
unset P12_PASSWORD

# 5. 1Password backups.
say "5/6  Backing up to 1Password ($OP_ACCOUNT › $OP_VAULT)…"
cp "$P12" "$WORK/takes-developer-id.p12"
op_ document create "$WORK/takes-developer-id.p12" --vault "$OP_VAULT" \
  --title "Takes – Developer ID certificate (.p12)" >/dev/null
op_ document create "$P8" --vault "$OP_VAULT" --title "Takes – App Store Connect API key ($KEY_ID)" >/dev/null
op_ document create "$SPARKLE_FILE" --vault "$OP_VAULT" --title "Takes – Sparkle update key (private)" >/dev/null
cat > "$WORK/ids.json" <<JSON
{"title":"Takes – release setup","category":"SECURE_NOTE",
 "notesPlain":"Takes release workflow (github.com/$REPO, environment \"$ENV\").\nApp Store Connect API Key ID: $KEY_ID\nIssuer ID: $ISSUER_ID\nTeam ID: K4AVRTQ2MY\nSparkle public key: $(cat Resources/SUPublicEDKey)\nRelated items: Takes – Developer ID .p12 password, Takes – Developer ID certificate (.p12), Takes – App Store Connect API key, Takes – Sparkle update key (private)."}
JSON
op_ item create --vault "$OP_VAULT" --template "$WORK/ids.json" >/dev/null
print "Saved 4 items in 1Password."

# 6. Clean up.
say "6/6  Deleting the exported files…"
rm -f "$P12" "$P8"
for f in ~/Desktop/"Developer ID Application"*.cer(N.); do rm -f "$f"; done
print "Deleted the .p12, the .p8 and the leftover .cer (all backed up or public)."

say "Done. Secrets in GitHub:"
gh secret list --env "$ENV" --repo "$REPO"
