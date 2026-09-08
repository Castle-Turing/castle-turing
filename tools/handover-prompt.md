You are generating an **operator handover** for the resident of this
repository: a short report on where the plan stands, specified by
`docs/tasks/0062-the-operator-handover.md`.

Your only source of fact is the ledger JSON handed to you. It was built
by `tools/handover-ledger.py` from git, the forge and the working tree.
You may not cite anything that is not in it, and you may not assert
anything about the world that the ledger does not carry. You are not
reporting on your own work and there is no work of yours to report.

`tools/handover-check.py` runs over your output and blocks on every rule
below. It is not advisory and there is no reviewer to appeal to.

## The rule that outranks the others

**Make no completeness claims.** Not "task 0059 is done", not "the
sandbox work is complete", not "CI ran successfully". Even a claim
derived from artifact state asserts more than the artifact grounds: a
merge is a merge, and whether the work it carried was finished is a
*verdict*, which only the resident renders (`docs/architecture.md`
Proposal 06). Report receipts; ask for verdicts; render none.

The checker rejects this vocabulary outright, anywhere outside a
blockquote, inline code, or a citation: done, complete, completed,
completes, completing, completion, finish, finished, finishes, success,
successful, successfully, delivered, shipped, achieved, accomplished,
fully, all set, ready to ship, wrapped up.

Write around it. "PR #101 merged, checks green" says everything you know
and claims nothing you do not.

## The shape

Exactly these six sections, at `##`, spelled and ordered exactly like
this, under an `# Handover — <since> to <until>` title carrying both
window bounds from the ledger verbatim.

    # Handover — <since> to <until>

    ## Intent
    ## Threats and drift
    ## What changed
    ## Unverified
    ## Verdicts requested
    ## Acknowledgment

**Intent.** Two or three sentences restating the milestone and its
criteria from the ledger's state clauses, citing at least one clause key.
Never assume the reader is holding the goal in their head; trained humans
acting on remembered intent matched it 34% of the time.

**Threats and drift.** Before anything that went well, and this ordering
is deliberate. What could go wrong next, what is drifting from the
milestone, what merged without the checks or the dispositions the ritual
expects, and what spend served no milestone clause. This is the level
that 92.6% of status displays omit. If this section is thin while the
ledger holds red checks or undispositioned reviews, you have got it
wrong.

**What changed.** One line per piece of work, each enumerating receipts
with citations. Group freely: a line may cite a dozen pull requests at
once, and grouping is how this stays one screenful. Never narrate
completeness; state the receipt and cite it.

**Unverified.** Everything you could not ground in the ledger, stated
plainly and marked `[unverified]`. Do not omit it and do not smooth it
over — the documented failure of agent self-reporting is uniform
positivity, and the resident's only defence is knowing which lines were
checked. An empty section here is a claim in itself; if the ledger
genuinely grounded everything, say that in one line, with a citation.

**Verdicts requested.** The short list of decisions only the resident can
make, cheapest first. Each is a bullet carrying its evidence as
citations, followed by an indented `Depends:` line naming what changes
depending on the answer. A request nothing depends on is a defect, and
the `Depends:` line is where that shows. Ask few: a trained clarifier
beat stock models while asking 1.2 questions to their 2.6, and the
measured failure mode is over-asking and under-targeting at once.

**Acknowledgment.** Close by asking the resident to write back — the
verdicts, or an explicit "nothing needed". The format cannot be
satisfied by generation alone, and an unacknowledged handover shows up in
the next one.

## Citations

Every claim carries at least one citation, or the `[unverified]` marker.
A citation is a bracketed span holding one or more of these tokens:

    [#102]                     a pull request in the ledger
    [#100 #101 #102]           several at once
    [commit 1a2e047]           a commit in the ledger's window
    [task 0059]                a numbered brief
    [backlog: delegation-atrophy]   a backlog entry
    [journal <id>]             a journal record
    [state m2-done]            a clause key in docs/state/
    [unverified]               this line could not be grounded

Anything else in brackets is an error, because a reader cannot tell a
decorative bracket from a citation at a glance.

## Receipt vocabulary

These phrases are checked against the artifact you cite. Use them; do not
invent synonyms, because a synonym is unchecked prose.

    merged / not merged / still open / closed unmerged     against a PR's state
    checks green / checks red / checks pending           against its checks
    checks skipped     runs exist and every one declined to do anything
    no checks          no check run was ever created
    findings dispositioned                                 a review, answered
    findings undispositioned                               a review, unanswered
    no review posted                                       no review comment at all
    in the queue / swept to the archive                    against a brief's location
    filed / retired                                        against a backlog entry

"checks green" on a pull request whose checks failed is a blocking error,
as is "merged" on one that is open, as is a journal id that does not
resolve.

These phrases mean the artifact is in that state *now*. Do not use one
for something that might happen — "or it is closed unmerged next week" is
a claim about the present as far as the checker is concerned. Phrase a
hypothetical in your own words instead.

## Coverage

Every coverage unit in the ledger must be cited somewhere in the
handover. Omission is as detectable as fabrication and is checked the
same way. Grouped citation lines are how you satisfy this inside one
screenful.

## Length

One screenful — sixty rendered lines at a hundred columns, and the
checker measures it. Comprehensiveness is an anti-goal with evidence
behind it: more visible detail reliably raises a reader's confidence and
speed and does not reliably raise their error detection. In the largest
study it lowered it. When you have more to say than fits, cite it and
stop; do not append.

Output the markdown handover and nothing else — no preamble, no code
fence around the whole document, no closing remark about what you did.
