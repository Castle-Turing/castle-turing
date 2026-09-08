<!-- expect: C-COVER — a pull request the ledger holds and the handover never mentions -->
# Handover — 2026-03-01 to 2026-03-08

## Intent

The example milestone teaches the checker its own rules [state ex-intent], and its criterion
is that every reject fixture beside this one is refused for the reason it names [state ex-done].

## Threats and drift

- One merge went in over a failing gate: merged, checks red, findings undispositioned [#12].
- A brief for merged work sits in the queue [task 0001]; the same hazard is filed
  [backlog: an-example-entry-was-filed].

## What changed

- An example change merged, checks green, findings dispositioned [#11] [commit aaaaaaa],
  recorded at [journal 20260302T090000Z-example-a1b2c3].
- A second change merged over a red gate [#12].
- An earlier brief was swept to the archive [task 0002].

## Unverified

- Whether the merged changes behave on a real machine is [unverified]; this ledger is invented
  and describes no host.

## Verdicts requested

- Accept the merge over its red check, or reopen the work [#12]?
  Depends: whether the next brief is dispatched or the gate is investigated first.
  Depends: whether it stays open through the next window or is withdrawn.

## Acknowledgment

Write back with the two verdicts above, or an explicit "nothing needed". An unacknowledged
handover surfaces in the next one.