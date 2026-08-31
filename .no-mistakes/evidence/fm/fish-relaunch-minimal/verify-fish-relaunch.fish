#!/etc/profiles/per-user/sayori/bin/fish

set -lx TRACEPARENT stale
printf 'host-shell: '
rtk fish --version

set legacy_cmd "unset TRACEPARENT; echo legacy-shell-survived"
printf 'legacy-command: %s\n' "$legacy_cmd"
rtk fish -c "$legacy_cmd"
printf 'legacy-exit=%s\n' "$status"

set fixed_probe "if set -q TRACEPARENT; echo replacement-carrier-present; exit 1; else; echo replacement-carrier-unset; end"
printf 'fixed-command: env -u TRACEPARENT <replacement>\n'
rtk env -u TRACEPARENT fish -c "$fixed_probe"
or exit $status
printf 'fixed-exit=%s\n' "$status"

set -lx FM_TEST_REQUIRE_FISH 1
rtk /bin/bash tests/fm-control-relaunch.test.sh
or exit $status
rtk /bin/bash tests/fm-trace-context-spawn.test.sh
or exit $status
