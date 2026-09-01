#!/usr/bin/env bash
# test/agent-loop/notify-stub.sh — CASTLE_NOTIFY_COMMAND stub for CI
# (docs/tasks/0009-ambient-intake.md item 5). There is no notification
# daemon, no mako, and no display session in a CI runner, so this
# stands in for notify-send: `castle route` invokes it exactly the way
# it would invoke the real thing (`<command> <title> <body>`), and this
# script logs the call instead of trying to reach one. run.sh asserts
# against $CASTLE_NOTIFY_LOG's contents to prove the notify channel
# really fired, not just that a decision record claimed it would.
set -euo pipefail
: "${CASTLE_NOTIFY_LOG:?notify-stub.sh: CASTLE_NOTIFY_LOG must be set}"
# Since docs/tasks/0034 the invocation is `<command> <flags...>
# <title> <body>` (app-name and the open action ride in front), and it
# arrives from a detached waiter rather than the router's own process.
# The log line stays `<title> :: <body>` so every existing assertion
# still reads it; the flags land in a sibling log for the assertions
# that are about them.
printf '%s\n' "$*" >> "${CASTLE_NOTIFY_ARGS_LOG:-/dev/null}"
title="${@: -2:1}"
body="${@: -1}"
printf '%s :: %s\n' "$title" "$body" >> "$CASTLE_NOTIFY_LOG"
