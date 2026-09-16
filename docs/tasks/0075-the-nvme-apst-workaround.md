Title: Bar the NVMe's deepest power state on the xps9370
Model: cheap
Milestone: none — hygiene
Model-because: the change is one kernel parameter whose exact text,
exact file, and exact placement are given below, with an evaluation
check as the receipt — this brief leaves the implementer no
composition to do, which is what makes the cheap tier right. What
would rule it out is any freedom in the diff; there is none. The one
standing instruction that survives the tier: if the file at placement
time does not match what this brief cites, stop and report rather
than adapt — the risk in a mechanical task is a stale spec, and the
answer to that is escalation, not improvisation.

# Task 0075 — the NVMe APST workaround

## Why, from the incident

On 2026-09-16 at ~01:24 this chassis's PC401 NVMe stopped serving
I/O while the machine ran on from page cache for six and a half
hours. The full forensic record is in task 0074's brief (the
detector this incident shipped); the root-cause evidence, gathered
the same morning, is this brief's to carry:

- SMART afterwards showed a healthy drive: zero Media and Data
  Integrity Errors, zero Error Information Log entries, 100% spare,
  5% worn. A drive failing I/O logs errors; a drive whose link or
  controller has gone dark logs nothing, because from its side
  nothing happened. The controller-side silence during six hours of
  failed host writes is the dropout shape, not the media-failure
  shape.
- The drive's APST table (`nvme get-feature -f 0x0c -H`) was
  programmed to enter PS4 — the deepest state, 7 mW, 5 ms exit
  latency — after 100 ms of idle, from every operational state, with
  no intermediate step. An idle machine at 01:24 had this drive
  parked in PS4 essentially continuously.
- The pinned kernel carries no protective quirk for this model, and
  the table proves it: a kernel applying `NVME_QUIRK_NO_DEEPEST_PS`
  never programs ITPS=4.
- The PC401 in the XPS 9370 is a pairing with a documented history
  of exactly this dropout, and `/proc/cmdline` shows no
  `nvme_core.default_ps_max_latency_us` workaround was in place.

Probable cause, not proven: the kernel messages that would prove a
controller dropout (`nvme controller is down`, reset attempts) were
lost with the unpersisted journal — that loss is the whole subject
of task 0074. The falsifier is stated below.

A dependency, stated so it cannot dangle silently: task 0074 (the
incident's detector, which this brief and the shipped comment both
cite) rides its own branch and PR #131, unmerged as this is written.
The incident-ships-its-detector obligation is carried by 0074, not
here; if that work is ever abandoned rather than merged, the
obligation reverts to open and this brief's 0074 citations need
re-pointing. Merge order between the two does not otherwise matter —
this fix does not depend on the detector to function, only the
falsifier's *visibility* does.

## The change

Add to `hosts/xps9370/default.nix`, immediately after the
`hardware.enableRedistributableFirmware = true;` block and its
comment (both cited from the file as of `origin/main` @ 63764d8),
this block, verbatim:

```nix
  # Bar every NVMe controller in this machine from autonomous power
  # states costing more than 5500 µs of entry+exit latency. On this
  # chassis's single drive (the PC401 — disko.nix gives it the one
  # M.2 slot) that bars PS4 (6000 µs, 7 mW), the state implicated in
  # the 2026-09-16 write-path dropout, and keeps PS3 (2000 µs, 70 mW)
  # as the idle floor — about 60 mW over full APST, against the watts
  # that 0 (APST off) would cost. The parameter is module-global, not
  # per-device: a second drive would inherit the bar.
  #
  # Probable cause, not proven — task 0075's brief carries the
  # evidence chain, task 0074 the detector the incident shipped.
  # Verified against kernel 6.18.44 (the pin of the day), which
  # programmed this drive into PS4 after 100 ms of idle and carries
  # no NO_DEEPEST_PS quirk for it. Falsifier: a dropout recurring
  # with this in place refutes the PS4 theory; the next step is 0.
  # Retire the line if a pinned kernel gains a PC401 quirk, or with
  # the drive.
  boot.kernelParams = [ "nvme_core.default_ps_max_latency_us=5500" ];
```

The comment deliberately carries the constraint, the scope, the
arithmetic, and the falsifier — not the incident narrative, which
lives here. The first draft of this brief specced the full narrative
inline; review flagged it as the accretion pattern
`docs/backlog/code-comments-accrete-the-reasoning-record.md` records,
and the brief was corrected rather than the implementer deviating.

In `hosts/`, not `modules/`, by the hard rule: which power states a
particular drive in a particular chassis can safely enter is a
machine fact. The value is public mechanism in the Principle 01
sense — any stranger deploying this host module onto this chassis
class wants it.

## Verification plan

Agent-verifiable, before the PR:

1. `nix flake check` still passes (the flake must keep evaluating;
   VM tests live in `packages.*` and are not implicated by a
   kernel-parameter change).
2. The parameter is present in the evaluated host: confirm via the
   flake's own evaluation surface for `nixosModules.host-xps9370`
   (an `nix eval` of the composed config's `boot.kernelParams`, or
   the closest check the flake exposes) rather than by re-reading
   the source edit.

Human steps, after merge (they need the machine):

3. Bump the castle-turing pin in the private layer and rebuild
   (`nixos-rebuild switch --flake ~/projects/castle-turing-private#xps9370`
   — the switch needs the resident, per the standing sudo boundary).
4. `cat /proc/cmdline` shows
   `nvme_core.default_ps_max_latency_us=5500`.
5. `sudo nvme get-feature /dev/nvme0 -f 0x0c -H` shows no entry with
   ITPS 4 — the kernel reprograms the drive's APST table at probe
   time under the new budget, and PS3 as the deepest programmed
   state is the observable receipt that the bar is in force.
6. The real test is time: no recurrence. If a dropout does recur
   with the parameter in place, that refutes the PS4 theory — go to
   `0`, and expect task 0074's canary (once deployed) to have
   caught and timestamped it.

## Implementation prompt

Read this brief in full. Make exactly the change in "The change" —
the comment block and the one `boot.kernelParams` line, placed as
specified in `hosts/xps9370/default.nix` — and nothing else. Run
verification steps 1 and 2 and include their output in your report.
If the file does not match the cited placement context, or
`boot.kernelParams` is already set anywhere in the host module, stop
and report instead of adapting. Report any judgment call you had to
make where these instructions were ambiguous.
