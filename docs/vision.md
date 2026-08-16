# Castle Turing

*Castle Turing is an AI-native personal computing environment. This vision document is the founding context for the project — distilled from the originating conversation, August 2026. The name is from **The Diamond Age**: the castle where the Primer teaches Nell computation, and escape comes through understanding the machine.*

## What this is

This project builds a personal computing environment where AI lives at the operating system level and customizes the entire system — and by extension every application — to its user. Not a voice interface bolted on top. Not a chat box. An agent deeply plugged into the actual workflow, making real decisions about how applications and information are handled, interacting through natural language only when that happens to be the right channel.

The reference points are two. The first is fictional: the Young Lady's Illustrated Primer from Neal Stephenson's *The Diamond Age* — a system with a durable theory of its user, serving the user's intentions about themselves rather than merely their behavior patterns. The second is real: a genuinely competent executive assistant. Not one who schedules meetings and files expenses, but one to whom executive function itself can be offloaded — who decides whether a meeting is worth taking given current workload, who reads the email and makes sure nothing falls through the cracks, who spends her principal's attention deliberately and sparingly to keep her model of his priorities accurate. That is the target, and it should be almost invisible.

## The core inversion

Current AI products are maximally conversational and minimally judgmental: every action is a chat exchange, nothing is decided for you. This project builds the inverse. The agent's default output is nothing. Its second most common output is a completed action you only notice if you go looking. Its rarest output is a small, well-timed question that exists to refine its model of your priorities.

A second inversion follows: the interruption medium is itself a decision the AI makes. Natural language is one channel among several. A two-button modal composed on the fly, a status bar turning amber, a rearranged workspace, a note left in a morning digest, silence — these are all valid outputs, and choosing among them is a core competence of the system. The failure mode of every prior attempt at proactive computing (Clippy is the cautionary ancestor) was not wrong answers but wrong timing and wrong channel. An assistant that interrupts badly gets disabled within a week no matter how smart it is.

## Why Linux, why now

The terminal-centric, text-based Unix environment is accidentally the most AI-legible computing environment ever built. Everything that makes it good for a keyboard-driven human — plain-text configs, maildir instead of a webmail DOM, composable small tools, everything scriptable — is exactly what makes it tractable for an agent. An AI operating a GUI must screenshot, interpret pixels, and simulate clicks. An AI operating this environment reads files, calls tools, and speaks IPC. The environment and the assistant share a native language.

NixOS specifically is the substrate because it turns the entire operating system into a text artifact: something an agent can read, reason about, and safely modify, with rollback as a guarantee rather than a hope. The machine stops being a garden that decays and becomes a program that is versioned. "Set up just right" becomes a checked-in state instead of undocumented tacit knowledge that must be re-derived after every reinstall.

A tiling window manager (Sway or Hyprland) is the display surface. Full programmatic control over workspaces, tiles, and layouts via IPC means the laptop can behave less like a workspace and more like a dashboard: tiles rearranged and resized based on focus, communication apps exiled during deep work, the day's state legible at a glance. The window manager is the agent's hands.

Hardware note: the machine is a Dell XPS 13 9370 (8th-gen i7, 16GB, touchscreen) — a well-supported target with a dedicated nixos-hardware module. It is a project machine, not the daily driver; nothing critical depends on it. That is deliberate: the AI-assisted customization is allowed to be the hobby.

## What the system does, concretely

Email is handled, not processed. The agent reads new mail against stated priorities and its running model of the current situation, tags and archives, drafts replies worth the user's voice into a drafts folder, and surfaces the few things that genuinely need attention. The inbox becomes an audit log of the agent's work rather than a task queue for the human.

Slack messages are prioritized against both standing strategic priorities and whatever the day's dumpster fire is.

Attention is defended. Deep-focus mode engages in the morning when the user is fresh, arranged around the week's top priorities. Rabbit holes get interrupted when a real commitment is at stake — an upcoming interview, a meeting about to be missed.

Open loops are swept. A recurring pass across mail and messages tracks what was promised, what is awaited, and what is about to fall through the cracks.

## Design principles

**Judgment applied silently, punctuated by rare, tiny queries.** The interaction pattern of the great assistant was mostly not conversational. Interruptions were her model-building: she spent small amounts of attention early to buy accuracy that let her spend almost none later. The system should do the same — deliberately chatty during an initial apprenticeship period, asking the priority questions, then going quiet as the model fills in. It should not try to be impressive on day one.

**Trust is built through a legible history.** Every triaged email, declined meeting, and deferral is logged with its reasoning in a decision journal — not shown, but always inspectable. A short weekly audit replaces confirmation dialogs sprayed across the day. Corrections during the audit are the training signal. Invisibility is not the absence of oversight; it is oversight moved to a time and channel of the user's choosing.

**Force is the escalation of a conversation, not the opening move.** Coercive interventions (yanking the user out of Hacker News) are graduated: ambient cue first, then a nudge, then the hard workspace swap reserved for genuinely hard commitments. The great assistant would not have closed the laptop; she would have appeared in the doorway. A system with authority over attention must be right about what matters and must fail gracefully when it is not — sometimes the rabbit hole is avoidance, and sometimes it is where the good idea comes from.

**Serve stated preferences, not just revealed ones.** A merely observant system optimizes for behavior patterns; the Primer served its user's intentions about herself. An OS that quietly decides what you see based only on what you do is a feed algorithm with root access. The user's model must include who they are trying to be.

**Decide the authority taxonomy early.** Which categories of decision are made silently, which are made-then-reported, and which are queued for explicit approval. When the agent declines a meeting, someone on the other end is being told no by a machine wearing the user's authority; the failure modes there are social, not technical. This taxonomy, more than any model capability, is the actual spec.

**Comprehension has an altitude, and a mode — and only the lowest of each is owed by default.** Silent competence measured only by throughput can leave the resident behind the system meant to serve them; an audit they can't meaningfully evaluate is oversight in name only. Staying capable spans two axes, and the agent should assume the minimal case on both. By default: a current map of how the pieces fit together — what changed, what depends on what, where the risk sits — legible enough that a resident who has never touched the implementation can still exercise real judgment. By stated preference, calibrated to demonstrated competence rather than maximized: a working intuition for technique in domains the resident wants to keep pace with, and rarer still, a full descent into one component on demand. And wherever a domain is one the resident wants to actually grow in, not merely track, the default posture is doing, not being shown: a real, bounded task handed over with coaching, scope widening only as demonstrated performance earns it — safe to offer for real, not simulated, because rollback already is the safe place to fail that the Primer needed fiction for. That performance is also the signal the authority taxonomy above should run on: what the resident has done, not what they've read, is what calibrates how much review a domain still needs.

## Architecture in one paragraph

NixOS is the declarative substrate the agent can safely modify. Text-native tools (maildir/notmuch for mail, direct APIs for Slack and calendar) are the interfaces it operates fluently. A tiling window manager driven over IPC is its display surface. The acting layer is a set of seats held by replaceable intelligences — Claude Code is the current tenant, never a structural member (see `docs/architecture.md`). A decision journal is the trust mechanism. Graduated intervention channels — note, ambient cue, nudge, modal, forced context switch — form the interaction grammar, expanded as trust accrues. The repo versions all of it together: system config, glue scripts, and these design documents.

## Starting point

The smallest full loop that exercises every layer: **morning focus mode plus email triage, with a decision journal.** At a set time, the agent arranges the workspace around the week's top priority and suppresses communication surfaces; in the background it triages mail against a stated-priorities document and logs every decision with reasoning. This is the fastest path to the question that matters most: does the invisible admin feel like a superpower or a nag?

## Open questions

How is ambient context captured — what does the agent observe (window focus, calendar, mail, more?), at what cost, and with what local/cloud split? What does the stated-priorities document look like, and how does the weekly audit ritual actually work? Where is the line in the authority taxonomy for outward-facing actions? What is the escalation ladder's exact shape, and how does the agent learn when its interruption was wrong? How is a resident's demonstrated competence actually measured and stored per domain — and does that one signal drive both explanation altitude and the authority taxonomy, or do the two need separate mechanisms?