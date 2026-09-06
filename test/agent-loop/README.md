# test/agent-loop — conventions the scenarios hold each other to

One rule so far, bought by five diagnoses of the same defect
(task 0046 for the mechanism, task 0064 for this suite): **a
scenario that creates two records with no `refs` edge between them
must not assert on which sorts first.** Ids carry one-second stamps
and a random suffix, so same-second order is a coin — on a fast CI
runner, a frequently flipped one. Either give the pair a real order
(a `refs` edge, or a `sleep 1` between the writes, with a comment
saying why), or write the assertions order-agnostically, deriving
roles from what the journal says happened. `record-order.sh` catches
mechanism code sorting by whole id; no grep can catch a test
*assuming* creation order, so this sentence is the guard.
