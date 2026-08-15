# modules/dev — the tools this project's own development happens with:
# Emacs, git, gh, ripgrep, fd, and claude-code. System packages only (no
# private data, no host assumptions) — the point of
# docs/tasks/0005-dogfooding-desktop.md is that this project can host its
# own development, so this module is deliberately boring: install the
# tools, nothing to configure per-person here (git's *identity* is
# personal data and lives in modules/home instead, per Principle 01).
#
# `claude-code` is confirmed present in this flake's pinned nixpkgs
# (checked at the time this module was written — if a future pin bump
# ever drops it, that is a nixpkgs packaging fact worth noting here, not
# a reason to improvise a wrapper: prefer bumping back or waiting for it
# to return over hand-rolling an install path in this module).
{ lib, pkgs, ... }:

{
  # claude-code is packaged under an unfree license in nixpkgs; scoped to
  # just this package rather than a blanket `allowUnfree`, so adding it
  # doesn't silently normalize unfree software project-wide.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

  environment.systemPackages = with pkgs; [
    emacs
    git
    gh
    ripgrep
    fd
    claude-code
  ];
}
