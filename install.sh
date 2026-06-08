#!/usr/bin/env bash
# harness installer / uninstaller — copy the harness skill into a host agent's
# skills directory, or remove it.
#
# harness is a pure-markdown skill (no build step), so installation is a copy.
# Claude Code can also use the plugin marketplace; Kiro CLI has no plugin system,
# so copying into the skills directory is the supported path. Both hosts support
# a user (global) scope and a project (workspace) scope.
set -euo pipefail

HOST=""
SCOPE="user"
FORCE=0
UNINSTALL=0

usage() {
  cat <<'EOF'
Usage:
  ./install.sh --host <kiro|claude> [--scope <user|project>] [--force]
  ./install.sh --host <kiro|claude> [--scope <user|project>] --uninstall [--force]

Install (default) or uninstall the harness meta-skill for a host agent.

Options:
  --host <kiro|claude>     Target host (required; auto-detected when unambiguous)
  --scope <user|project>   Location (default: user)
                             user    -> $HOME  (e.g. ~/.kiro/skills/harness)
                             project -> $PWD   (e.g. ./.kiro/skills/harness)
  --uninstall              Remove the installed harness skill instead of installing
  --force                  Skip confirmation prompts
  -h, --help               Show this help

Host directories:
  kiro    -> .kiro/skills/harness
  claude  -> .claude/skills/harness

Examples:
  ./install.sh --host kiro                            # ~/.kiro/skills/harness
  ./install.sh --host kiro --scope project            # ./.kiro/skills/harness
  ./install.sh --host kiro --uninstall                # remove ~/.kiro/skills/harness
  ./install.sh --host claude --scope project --uninstall --force
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --host=*) HOST="${1#--host=}"; shift ;;
    --scope) SCOPE="${2:-}"; shift 2 ;;
    --scope=*) SCOPE="${1#--scope=}"; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
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
  kiro)   HOST_SUBDIR=".kiro" ;;
  claude) HOST_SUBDIR=".claude" ;;
  *) echo "Error: unknown host '$HOST' (expected 'kiro' or 'claude')." >&2; exit 1 ;;
esac

case "$SCOPE" in
  user)    BASE="$HOME" ;;
  project) BASE="$PWD" ;;
  *) echo "Error: unknown scope '$SCOPE' (expected 'user' or 'project')." >&2; exit 1 ;;
esac

DEST="$BASE/$HOST_SUBDIR/skills/harness"

# ─── Uninstall ────────────────────────────────────────────────
if [ "$UNINSTALL" -eq 1 ]; then
  if [ ! -e "$DEST" ]; then
    echo "Nothing to uninstall: $DEST does not exist."
    exit 0
  fi
  # Safety: only remove a directory that actually looks like the harness skill,
  # so a mistyped path can never trigger a destructive rm.
  if [ ! -f "$DEST/SKILL.md" ]; then
    echo "Refusing to remove $DEST (no SKILL.md found; not a harness skill dir)." >&2
    exit 1
  fi
  if [ "$FORCE" -ne 1 ]; then
    printf "Remove harness skill at: %s ? [y/N] " "$DEST"
    if read -r ans </dev/tty 2>/dev/null; then :; else ans="n"; fi
    case "$ans" in [yY]*) : ;; *) echo "Aborted."; exit 0 ;; esac
  fi
  rm -rf "$DEST"
  echo "OK removed harness <- $DEST  (host=$HOST, scope=$SCOPE)"
  exit 0
fi

# ─── Install ──────────────────────────────────────────────────
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

echo "OK installed harness -> $DEST  (host=$HOST, scope=$SCOPE)"
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
