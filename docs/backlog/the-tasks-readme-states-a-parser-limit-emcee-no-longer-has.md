# The tasks README states a parser limit emcee no longer has

**What.** `docs/tasks/README` warns that "the queue's parser stops
reading headers at the first wrapped line" and requires every
harness-read key above any wrapped value. emcee's `_split_header`
(src/emcee/tasks.py) has since been fixed — a continuation line now
extends the previous key's value, and its docstring records the old
behavior as the 0063 bug it caused. The README's warning is stale
against the only harness currently reading the queue.

**Why it matters.** A reviewer enforcing the README produced a P1
against a correct task file on PR #150, and every future brief-writer
pays the ordering constraint. But the README also says any
`Title:`-headed-markdown harness may consume the queue, so the
conservative rule may be worth keeping *as a portability contract*
rather than as a parser fact — that is a decision, not a correction.

**What we already know.** Task files already in `docs/tasks/` (0082)
place harness-read keys below wrapped values and dispatch fine, so
current practice contradicts the stated rule either way.

**Open questions.** Keep the ordering rule and restate it as a
portability contract, or drop it and let emcee's parser define the
format; either way the README should stop asserting a parser behavior
that is no longer true.
