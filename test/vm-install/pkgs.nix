# The package set the harness builds its own tooling from (qemu, OVMF,
# nixos-anywhere) — this flake's own pinned nixpkgs, so the harness stays
# on exactly the nixpkgs revision the mechanism itself is tested against.
(builtins.getFlake (toString ../..)).inputs.nixpkgs.legacyPackages.x86_64-linux
