#!/usr/bin/env bash
# Send SIGTERM to the runner listener 15 s from now, while this step is still running,
# the same signal a self-hosted runner gets on a node shutdown or pod eviction.
set -euo pipefail
ps -eo pid,user,comm,args | grep -E 'Runner\.(Listener|Worker)' | grep -v grep
(sleep 15; sudo kill -TERM "$(pgrep -x Runner.Listener)") &
sleep 300
