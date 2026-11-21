#!/bin/zsh
# Makes this Mac look like Takes was never installed, so onboarding can be walked again from the start.
# Everything is backed up first and comes back with --restore.
#
# Usage:
#   scripts/reset-to-new-install.sh             back up and clear Takes' files and preferences, and reset its
#                                               Accessibility, Microphone and Speech Recognition access
#   scripts/reset-to-new-install.sh --keychain  also delete Takes' keychain items (API keys, ChatGPT sign-in).
#                                               These are NOT backed up: you'll paste the key or sign in again.
#   scripts/reset-to-new-install.sh --restore   put back the latest backup (access must be allowed again by hand)
#
# What it leaves alone: Claude Code itself and its sign-in, Ollama and LM Studio, the logs in
# ~/Library/Logs/Takes, and the login item (remove it in System Settings › General › Login Items if you turned it
# on). To test a Mac without Claude Code, use a new macOS user account or a VM instead.
set -euo pipefail

BUNDLE_ID=com.baramir.takes
SUPPORT="$HOME/Library/Application Support/Takes"
BACKUPS="$HOME/Library/Application Support/Takes-reset-backups"

quit_takes() {
  if pgrep -xq Takes; then
    echo "› Quitting Takes"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..50}; do pgrep -xq Takes || break; sleep 0.1; done
    if pgrep -xq Takes; then
      echo "Takes didn't quit. Quit it from its menu and run this again." >&2
      exit 1
    fi
  fi
}

reset() {
  local keychain=$1
  quit_takes
  local stamp=$(date +%Y-%m-%d-%H%M%S)
  local backup="$BACKUPS/$stamp"
  mkdir -p "$backup"

  echo "› Backing up to $backup"
  if [[ -d "$SUPPORT" ]]; then
    mv "$SUPPORT" "$backup/Takes"
  fi
  # Preferences hold the remembered Claude Code path, window places, the menu-bar icon's place and Sparkle's choice.
  if defaults export "$BUNDLE_ID" "$backup/defaults.plist" 2>/dev/null; then
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
  fi

  echo "› Resetting Accessibility, Microphone and Speech Recognition access"
  for service in Accessibility Microphone SpeechRecognition; do
    tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
  done

  if [[ "$keychain" == yes ]]; then
    echo "› Deleting Takes' keychain items"
    local removed=0
    while security delete-generic-password -s "$BUNDLE_ID" >/dev/null 2>&1; do
      removed=$((removed + 1))
      (( removed < 50 )) || break
    done
    echo "  $removed removed"
  fi

  echo
  echo "Done. Open Takes and it starts like a new install."
  echo "To undo: scripts/reset-to-new-install.sh --restore"
}

restore() {
  quit_takes
  local latest
  # Backups already put back end in -restored and aren't picked again.
  latest=$(ls -1 "$BACKUPS" 2>/dev/null | grep -v -- '-restored$' | sort | tail -n 1 || true)
  if [[ -z "$latest" ]]; then
    echo "No backup in $BACKUPS." >&2
    exit 1
  fi
  local backup="$BACKUPS/$latest"
  echo "› Restoring $backup"
  # What the test run made is kept beside the backup, not deleted.
  if [[ -d "$SUPPORT" ]]; then
    mv "$SUPPORT" "$backup/Takes.from-test-$(date +%H%M%S)"
  fi
  if [[ -d "$backup/Takes" ]]; then
    mv "$backup/Takes" "$SUPPORT"
  fi
  if [[ -f "$backup/defaults.plist" ]]; then
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    defaults import "$BUNDLE_ID" "$backup/defaults.plist"
  fi
  echo
  echo "Restored. Allow Accessibility access again when Takes asks (System Settings › Privacy & Security › Accessibility)."
  mv "$backup" "$backup-restored"
  echo "The backup folder is kept as $backup-restored"
}

case "${1:-}" in
  "") reset no ;;
  --keychain) reset yes ;;
  --restore) restore ;;
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac
