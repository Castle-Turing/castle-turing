The delivery seat has no record shim

Task 0069 defines the delivery seat and fixes the records it owes
the journal: claim, result with outcome and implementer, question on
park. The current tenant (emcee, the operator's harness) will emit
its own journal events through a generic hook rather than learn this
project's record format — the dependency direction both projects
committed to on 2026-09-01 is that the harness depends on nothing
above it, and integration shims live with the integrator.

The missing piece is the shim: a castle-owned translator that
consumes the tenant's event stream and appends delivery records. It
cannot be specced until the hook and its event schema exist on the
harness side (queued there as of 2026-09-07). When that lands,
promote this entry: the spec must state what the shim does when
events are missing or arrive twice — the tenant's own journal file
is the source of truth for reconciliation; the hook is a doorbell,
not the mail.
