# The Codex followup cannot push workflow fixes

**What.** On PR #73 (2026-09-02), the Codex review found three valid
problems, and two of the fixes touched `.github/workflows/*.yml`. The
`claude-codex-followup.yml` session judged them correctly, wrote the
fixes, and could not land them: GitHub refuses to let a GitHub App
credential create or update workflow files unless the App holds the
`workflows` permission, and the followup's token does not — its push
was rejected outright with `refusing to allow a GitHub App to create
or update workflow ... without workflows permission`. The session
recorded both fixes in the 0041 brief's Judgment-calls section
instead, and a human-credentialed session applied them (`a564f70`).

**Why it recurs rather than being a one-off.** Task 0041 put real
logic — retry loops, signature matching, time budgets — into exactly
the files the App cannot touch, and CI logic is among the things a
reviewer most usefully reviews. Every future finding whose fix lands
under `.github/workflows/` hits this same wall, and the fallback
currently rests on the session in the Actions run choosing to write
the fix down somewhere durable rather than routing around the refusal.
That worked this time; it is a norm, not a mechanism.

**The decision this entry actually defers.** GitHub's boundary here is
arguably correct: an automated session that can rewrite CI can rewrite
the checks that gate its own output — the same reasoning behind
emcee's veto owning `git push`. So the fix is a policy choice, not a
permission checkbox:

- grant the App the `workflows` permission, accepting that the
  followup can then silently alter what CI runs, on a repo whose merge
  gate is CI; or
- keep the boundary and promote the fallback to a stated contract: a
  workflow-touching fix is *always* recorded (where, in what format,
  and how a human finds it) and never pushed by the App — plus a
  receipt that can be trusted, which is its own open problem:
  [[the-codex-followup-promised-a-receipt-it-never-posted]].

Whichever way this goes, `claude-codex-followup.yml`'s prompt should
tell the session about the boundary up front, so it plans for the
recorded-fix path instead of discovering the rejection after
committing.
