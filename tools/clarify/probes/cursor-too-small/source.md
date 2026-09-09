# Statement: the cursor is too small

Speaker: resident
Date: 2026-09-08

The mouse cursor is too small to find on this laptop's panel.

I mean the cursor Sway itself draws. The XWayland and GTK cursor-scaling
gap is a separate problem and is not part of this.

Done means I have looked at the cursor on the real hardware and said it
is right. A number reasoned out from the panel's resolution and never
looked at does not count, whatever it computes to.

The value belongs in the host module rather than the shared desktop
module, because the right size depends on which panel is in front of me.
