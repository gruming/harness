#!/usr/bin/env bash
# harness installer — copies the harness skill into a host agent's skills directory.
#
# harness is a pure-markdown skill (no build step), so installation is a copy.
# Claude Code can also use the plugin marketplace; Kiro CLI has no plugin system,
# so copying into ~/.kiro/skills/ is the supported path.
set -euo pipefail

HOST=""
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./install.sh --host <kiro|claude> [--force]

Install the harness meta-skill into a host agent's skills directory.

Options:
  --host <kiro|claude>   Target host (required; auto-detected when unambiguous)
                           kiro   -> ~/.kiro/skills/harness
                           claude -> ~/.claude/skills/harness
  --force                Overwrite an existing installation without prompting
  -h, --help             Show this help

Examples:
  ./install.sh --host kiro
  ./install.sh --host claude --force
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --host=*) HOST="${1#--host=}"; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Resolve host. If unset, auto-detect only when exactly one host dir exists.
if [ -z "$HOST" ]; then
  if [ -d "$HOME/.kiro" ] && [ ! -d "$HOME/.claude" ]; then
    HOST="kiro"
  elif [ -d "$HOME/.claude" ] && [ ! -d "$HOME/.kiro" ]; then
    HOST="claude"
  else
    echo "Error: --host is required (kiro or claude); could not auto-detect." >&2
    usage
    exit 1
  fi
  echo "Auto-detected host: $HOST"
fi

case "$HOST" in
  kiro)   DEST="$HOME/.kiro/skills/harness" ;;
  claude) DEST="$HOME/.claude/skills/harness" ;;
  *) echo "Error: unknown host '$HOST' (expected 'kiro' or 'claude')." >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/skills/harness"
if [ ! -d "$SRC" ]; then
  echo "Error: source skill not found at $SRC" >&2
  exit 1
fi

if [ -e "$DEST" ]; then
  if [ "$FORCE" -eq 1 ]; then
    rm -rf "$DEST"
  else
    printf "Destination already exists: %s\nOverwrite? [y/N] " "$DEST"
    if read -r ans </dev/tty 2>/dev/null; then :; else ans="n"; fi
    case "$ans" in
      [yY]*) rm -rf "$DEST" ;;
      *) echo "Aborted (use --force to overwrite non-interactively)."; exit 0 ;;
    esac
  fi
fi

mkdir -p "$(dirname "$DEST")"
cp -R "$SRC" "$DEST"

echo "OK installed harness -> $DEST"
case "$HOST" in
  kiro)
    echo "  Start a new kiro-cli session and say: \"하네스 구성해줘\" / \"build a harness\""
    echo "  Kiro runtime adapter: skills/harness/references/kiro-runtime.md"
    ;;
  claude)
    echo "  In Claude Code, say: \"build a harness for this project\""
    echo "  Requires: export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
    ;;
esac
