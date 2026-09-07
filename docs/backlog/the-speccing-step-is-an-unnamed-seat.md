The speccing step is an unnamed seat

The self-assembly pipeline is a chain of artifact handshakes: a
worker turn's finding → an outbox-filed backlog entry → a numbered
brief in docs/tasks/ → the delivery seat (task 0069) → a pull
request → review → the resident's merge. Every arrow is named
except one: backlog entry to numbered brief. Today that arrow is
held by the resident and by ad-hoc sessions.

It is a reasoning seat by this architecture's own definition — it
chooses the smallest next chunk of useful work, asks clarifying
questions, and writes a spec whose errors a small implementer will
follow off a cliff — and it has no definition, no records, and no
occupancy declaration. Noted 2026-09-07 during the delivery-seat
capture and deliberately not specced then: naming it is real work,
and doing it as a side effect of another seat's brief is how guard
language gets written badly.
