#!/usr/bin/env bash
set -euo pipefail

ROOT=/Users/sayori/.no-mistakes/worktrees/0b06e6c2f206/01M198X7TB2A2DE7QRCDSVS2C3
REAL_TMUX=$(command -v tmux)
FISH_BIN=$(command -v fish)
SLEEP_BIN=$(command -v sleep)
SOCKET="fm-relaunch-evidence-$$"
SESSION=relaunch-evidence
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-relaunch-evidence.XXXXXX")

cleanup() {
  "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  rm -rf "$LAB"
}
trap cleanup EXIT

tmux() { "$REAL_TMUX" -L "$SOCKET" "$@"; }

mkdir -p "$LAB/bin/claude"
ln -s "$SLEEP_BIN" "$LAB/bin/claude/claude"
ln -s "$SLEEP_BIN" "$LAB/bin/codex"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
fm_backend_source tmux

tmux new-session -d -s "$SESSION" -n fish -x 120 -y 30 \
  -e TRACEPARENT=stale "$FISH_BIN --no-config --interactive"

tmux send-keys -t "$SESSION:fish" -l \
  'function fish_prompt; if set -q FM_PROMPT_COUNT; set -gx FM_PROMPT_COUNT (math $FM_PROMPT_COUNT + 1); else; set -gx FM_PROMPT_COUNT 1; end; set -gx TRACEPARENT prompt-restored; printf "proof> "; end'
tmux send-keys -t "$SESSION:fish" Enter
sleep 0.2
tmux send-keys -t "$SESSION:fish" -l \
  'printf "PROMPT_HOOK_OBS traceparent=%s prompts=%s\n" "$TRACEPARENT" "$FM_PROMPT_COUNT"'
tmux send-keys -t "$SESSION:fish" Enter
sleep 0.2

launch='set -e TRACEPARENT; /bin/sh -c "test -z \"\${TRACEPARENT+x}\""; and begin; set -gx FM_RAW_SETUP ready; exec /bin/sh -c "printf \"AGENT_%s traceparent=%s raw_setup=%s prompts=%s\\n\" STARTED \"\${TRACEPARENT-unset}\" \"\${FM_RAW_SETUP-unset}\" \"\${FM_PROMPT_COUNT:-0}\"; sleep 30"; end'
tmux send-keys -t "$SESSION:fish" -l "$launch"
tmux send-keys -t "$SESSION:fish" Enter

pane=
for _ in $(seq 1 50); do
  pane=$(tmux capture-pane -p -t "$SESSION:fish" -S -30)
  case "$pane" in
    *AGENT_STARTED*) break ;;
  esac
  sleep 0.1
done

prompt_observation=$(printf '%s\n' "$pane" | grep 'PROMPT_HOOK_OBS' | tail -1)
agent_observation=$(printf '%s\n' "$pane" | grep 'AGENT_STARTED' | tail -1)
case "$prompt_observation" in
  *'traceparent=prompt-restored prompts='*) ;;
  *) printf 'missing prompt-hook observation\n' >&2; exit 1 ;;
esac
case "$agent_observation" in
  *'traceparent=unset raw_setup=ready prompts='*) ;;
  *) printf 'replacement inherited stale trace context or lost raw shell behavior\n' >&2; exit 1 ;;
esac

tmux new-window -d -t "$SESSION:" -n agent -- "$LAB/bin/claude/claude" 30
tmux new-window -d -t "$SESSION:" -n wrong -- "$LAB/bin/codex" 30
sleep 0.2

positive_1=rejected
positive_2=rejected
fm_backend_agent_started tmux "$SESSION:agent" claude && positive_1=started
fm_backend_agent_started tmux "$SESSION:agent" claude && positive_2=started
[ "$positive_1" = started ] && [ "$positive_2" = started ]

shell_verdict=started
wrong_verdict=started
absent_verdict=started
fm_backend_agent_started tmux "$SESSION:fish" claude || shell_verdict=rejected
fm_backend_agent_started tmux "$SESSION:wrong" claude || wrong_verdict=rejected
fm_backend_agent_started tmux "$SESSION:absent" claude || absent_verdict=rejected
[ "$shell_verdict" = rejected ]
[ "$wrong_verdict" = rejected ]
[ "$absent_verdict" = rejected ]

printf 'Firstmate relaunch runtime evidence\n'
printf 'HEAD=%s\n' "$(git -C "$ROOT" rev-parse HEAD)"
printf 'fish=%s\n' "$($FISH_BIN --version)"
printf 'tmux=%s\n' "$($REAL_TMUX -V)"
printf '%s\n' "$prompt_observation"
printf '%s\n' "$agent_observation"
printf 'selected=claude target=%s:agent confirmation_1=%s confirmation_2=%s foreground=[%s]\n' \
  "$SESSION" "$positive_1" "$positive_2" \
  "$(fm_backend_tmux_foreground_argv0s "$SESSION:agent" | tr '\n' ' ')"
printf 'selected=claude target=%s:fish verdict=%s foreground=[%s]\n' \
  "$SESSION" "$shell_verdict" \
  "$(fm_backend_tmux_foreground_comms "$SESSION:fish" | tr '\n' ' ')"
printf 'selected=claude target=%s:wrong verdict=%s foreground=[%s]\n' \
  "$SESSION" "$wrong_verdict" \
  "$(fm_backend_tmux_foreground_argv0s "$SESSION:wrong" | tr '\n' ' ')"
printf 'selected=claude target=%s:absent verdict=%s\n' "$SESSION" "$absent_verdict"
