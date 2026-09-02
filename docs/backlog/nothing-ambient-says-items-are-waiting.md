# Nothing ambient says items are waiting

**What.** After task 0034, the resident learns something needs them in
exactly two ways: a notification at the moment it fires, or opening
the modal to look. A missed notification leaves no trace anywhere
ambient — a blocking question can sit suspended for days with the
desktop showing nothing. The obvious shape is a waiting-count in the
swaybar (the bar is already restated wholesale in `modules/home`, so
there is a place to put it), deriving the same
questions-proposals-unread list the inbox view derives, and saying
nothing at all when the count is zero.

**Why it can wait.** The notification-plus-chord loop is adequate
while the journal sees a few records a day, and the bar's statusCommand
is currently plain i3status — feeding castle-derived state into it is
its own small design (poll vs. inotify, and how much the bar may say
before it becomes noise). Related: [[ambient-default-channel]], which
wants a channel between interrupt and digest — a bar count may be
exactly what that channel's deliveries look like.
