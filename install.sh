#!/usr/bin/env bash
# install.sh — install the coding harness into a Hermes profile.
#
# Copies the distribution SOUL.md + the whole coding-harness-protocol skill dir
# from this repo into the user's Hermes profile, with timestamped backups of
# anything it would overwrite. Pure shell. ZERO LLM tokens — installing the
# harness never touches a metered/billed path.
#
# Usage:
#   ./install.sh                 # install into ~/.hermes (or $HERMES_HOME)
#   HERMES_HOME=~/.hermes/profiles/work ./install.sh
#   ./install.sh --dry-run       # show what would happen, change nothing
#   ./install.sh --force         # skip the confirmation prompt
#
# Exit: 0 = installed (or dry-run ok) · 1 = aborted/error · 2 = bad input
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SOUL="$SCRIPT_DIR/hermes/SOUL.md"
SRC_SKILL_DIR="$SCRIPT_DIR/hermes/skills/coding-harness-protocol"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
DRY_RUN=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help)
      grep -E '^#( |$)' -- "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "install: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$1"; }
step() { printf '  • %s\n' "$1"; }

# Verify the source payload exists before touching anything.
[ -f "$SRC_SOUL" ]               || { echo "install: missing $SRC_SOUL (run from a clone of harness-kit)" >&2; exit 2; }
[ -d "$SRC_SKILL_DIR" ]          || { echo "install: missing $SRC_SKILL_DIR" >&2; exit 2; }
[ -f "$SRC_SKILL_DIR/SKILL.md" ] || { echo "install: missing $SRC_SKILL_DIR/SKILL.md" >&2; exit 2; }

DEST_SOUL="$HERMES_HOME/SOUL.md"
DEST_SKILL_PARENT="$HERMES_HOME/skills/software-development"
DEST_SKILL_DIR="$DEST_SKILL_PARENT/coding-harness-protocol"
# unique, sortable backup suffix; PID guards against same-second collisions
STAMP="$(date +%Y%m%d-%H%M%S)-$$"

say "== harness-kit installer =="
step "source : $SCRIPT_DIR"
step "target : $HERMES_HOME"
[ "$DRY_RUN" -eq 1 ] && step "mode   : DRY RUN (no changes)"

if [ ! -d "$HERMES_HOME" ]; then
  say ""
  say "⚠️  Hermes home not found: $HERMES_HOME"
  say "   This does not look like an initialized Hermes profile."
  say "   Set HERMES_HOME to your profile dir, or run 'hermes setup' first."
  exit 1                       # fail in dry-run too: a real run could not proceed here
fi

# Preflight ALL destination parents up front (fail before any partial write).
# Each must be absent or a real directory; reject symlinks anywhere on the path.
for d in "$HERMES_HOME" "$HERMES_HOME/skills" "$DEST_SKILL_PARENT"; do
  [ ! -L "$d" ] || { echo "install: refusing symlinked path: $d" >&2; exit 1; }
  [ ! -e "$d" ] || [ -d "$d" ] || { echo "install: not a directory: $d" >&2; exit 1; }
done
# Destinations themselves must not be symlinks (don't write through a link).
[ ! -L "$DEST_SOUL" ]      || { echo "install: refusing symlink dest: $DEST_SOUL" >&2; exit 1; }
[ ! -L "$DEST_SKILL_DIR" ] || { echo "install: refusing symlink dest: $DEST_SKILL_DIR" >&2; exit 1; }

# Confirm before writing (unless --force / --dry-run).
if [ "$DRY_RUN" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
  say ""
  say "This will install into $HERMES_HOME:"
  say "  - SOUL.md            (AI coding harness orchestrator identity + forced trigger)"
  say "  - skills/software-development/coding-harness-protocol/  (whole skill dir)"
  say "Existing files/dirs are backed up to <name>.bak.$STAMP before overwrite."
  printf 'Proceed? [y/N] '
  if ! read -r reply; then say "Aborted (no input)."; exit 1; fi
  case "$reply" in
    y|Y|yes|YES) ;;
    *) say "Aborted."; exit 1 ;;
  esac
fi

backup() {   # backup PATH → copies (file or dir) to PATH.bak.STAMP if it exists
  local p="$1" bak
  if [ -e "$p" ] || [ -L "$p" ]; then
    bak="$p.bak.$STAMP"
    if [ "$DRY_RUN" -eq 1 ]; then step "would back up: $p → $bak"; return; fi
    [ ! -e "$bak" ] || { echo "install: backup target already exists: $bak" >&2; exit 1; }
    cp -a -- "$p" "$bak"; step "backed up: $p → $bak"
  fi
}

# Back up BOTH destinations before installing EITHER, so a backup-collision/exit
# can't leave a half-installed state (minimizes the partial-install window).
say ""
say "Backing up existing files (if any) ..."
backup "$DEST_SOUL"
backup "$DEST_SKILL_DIR"

say ""
say "Installing SOUL.md ..."
if [ "$DRY_RUN" -eq 1 ]; then
  step "would install: $DEST_SOUL"
else
  mkdir -p -- "$HERMES_HOME"
  cp -a -- "$SRC_SOUL" "$DEST_SOUL"; step "installed: $DEST_SOUL"
fi

say ""
say "Installing coding-harness-protocol skill ..."
if [ "$DRY_RUN" -eq 1 ]; then
  step "would install: $DEST_SKILL_DIR/ (whole dir)"
else
  mkdir -p -- "$DEST_SKILL_PARENT"
  rm -rf -- "$DEST_SKILL_DIR"               # replace cleanly (old copy is already backed up)
  cp -a -- "$SRC_SKILL_DIR" "$DEST_SKILL_DIR"; step "installed: $DEST_SKILL_DIR/"
fi

say ""
if [ "$DRY_RUN" -eq 1 ]; then
  say "✅ DRY RUN complete — no changes made."
else
  say "✅ Installed. Next steps:"
  step "1. run preflight:  $SCRIPT_DIR/bin/preflight.sh"
  step "2. wire the gate:  call $SCRIPT_DIR/bin/gate.sh <project> from a stop-hook/CI"
  step "3. send any coding request — Hermes will load the protocol automatically."
fi
