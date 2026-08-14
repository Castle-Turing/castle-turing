# hosts/xps9370 — Dell XPS 13 9370 (reference host)

The project machine: 8th-gen i7, 16GB, touchscreen. Covered by the
`dell-xps-13-9370` module in nixos-hardware.

Will contain: `default.nix`, `hardware-configuration.nix` (generated on the
machine), and any quirks specific to this chassis. Nothing here may be
imported by `modules/`.

To adopt Castle Turing on different hardware, copy this directory's shape as
`hosts/<yourmachine>/` — that is the only hardware-specific work required.
