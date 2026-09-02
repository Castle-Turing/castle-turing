# Task 0038 — the notification's action key is `default`, literally

Task 0034's deep-link died at the last inch: the waiter registered its
action under the key `open`, and mako's stock left-click binding is
`invoke-default-action` — which invokes the action whose *key* is the
freedesktop-reserved word `default`, not whichever action a sender
happens to attach. A plain click therefore fell through to dismissal.
Found by exactly the verification 0034's brief reserved for a human (a
real click on the reference host — every headless fake invoked the
action by name and could not miss this), and proven in isolation
before fixing: `notify-send --action=default=Open` + one click printed
`default`.

The fix is the constant: `NOTIFY_ACTION_NAME = "default"` (the label
shown to daemons stays "Open"), with the reasoning at the constant's
definition, and every test and doc that pinned the old spelling
updated — the headless suite's argv assertion, its fake daemon's
action output, `modules/agent`'s `notify.command` description,
`agent/README.md`, and 0034's own deviations note (now stated
key-agnostically).

Non-goals: no mako-specific configuration (0034's daemon-agnostic
argument survives — `default` is spec-reserved, not mako-flavored);
no second action; no change to dismiss/expiry semantics.

Verification: modal-headless suite locally (its waiter assertions now
pin the new spelling); the real re-test is one more human click on the
reference host after deploy, which is also the outstanding 0034
verification this bug interrupted.
