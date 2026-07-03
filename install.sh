#!/usr/bin/env bash
# agent-codebase-skills installer
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/install.sh | bash
# Or from a local clone:
#   ./install.sh
#
# Clones the repo to ~/.agent-codebase-skills (override with AGENT_SKILLS_HOME)
# and symlinks each skill into ~/.claude/skills/. Update later by running this
# script again, or `git pull` in the clone — symlinks pick up changes for free.
set -euo pipefail

REPO_URL="${AGENT_SKILLS_REPO:-https://github.com/Zrzzzz/agent-codebase-skills.git}"
CLONE_DIR="${AGENT_SKILLS_HOME:-$HOME/.agent-codebase-skills}"
SKILLS_DIR="$HOME/.claude/skills"
SKILLS=(init-agents-md init-session-notes init-agent-task-md)

# Running from inside a checkout? Link that checkout directly instead of cloning.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
if [ -n "$script_dir" ] && [ -f "$script_dir/${SKILLS[0]}/SKILL.md" ]; then
  CLONE_DIR="$script_dir"
  echo "→ using local checkout: $CLONE_DIR"
elif [ -d "$CLONE_DIR/.git" ]; then
  echo "→ updating existing clone: $CLONE_DIR"
  git -C "$CLONE_DIR" pull --ff-only
else
  echo "→ cloning $REPO_URL → $CLONE_DIR"
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

mkdir -p "$SKILLS_DIR"
for s in "${SKILLS[@]}"; do
  target="$SKILLS_DIR/$s"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "⚠️  $target exists and is not a symlink — skipped (move it away and re-run)"
    continue
  fi
  ln -sfn "$CLONE_DIR/$s" "$target"
  echo "✓ linked $target"
done

echo
echo "Done. In any Claude Code session, type / and you should see:"
printf '  /%s\n' "${SKILLS[@]}"
