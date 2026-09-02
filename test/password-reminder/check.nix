# Table-tests the password-reminder machinery
# (docs/tasks/0036-reminder-banner-states.md) against the artifacts a
# built system actually ships — the check script exactly as
# systemd.services.castle-password-reminder-check will run it, and the
# interactive-shell banner exactly as environment.interactiveShellInit
# renders it — per the read-the-generated-artifact rule: `nix flake
# check` proving the module *evaluates* says nothing about what the
# generated script does. The states this table exercises include the
# ones no CI install ever reaches: 0032's "Considered and rejected"
# declined a negative-path VM install, a decision 0036 keeps, and this
# table is the cheap honest substitute.
#
# The script's three positional parameters are its test seams — the
# systemd unit starts it with none, so production always uses the real
# paths and this file drives the same generated text, never a copy.
{
  pkgs,
  # config.systemd.services.castle-password-reminder-check.script from
  # nixosConfigurations.example (admin username "resident" — the
  # fixture shadow lines and the pinned banner text below both depend
  # on that placeholder).
  script,
  # config.environment.interactiveShellInit from the same system.
  shellInit,
}:
let
  scriptFile = pkgs.writeText "castle-password-reminder-check.sh" script;
  shellInitFile = pkgs.writeText "interactive-shell-init.sh" shellInit;
  # Distinct opaque strings, deliberately not shaped like real crypt
  # hashes (test/vm-install's fixture-hash convention): the script
  # compares bytes and strips lock prefixes; it never validates hash
  # shapes, so a test value that *looked* like a hash would only
  # suggest a sensitivity that does not exist.
  seedHash = "fixture-seed-value-not-a-real-crypt-hash";
  otherHash = "fixture-chosen-value-a-different-string";
  # The banner block, byte-for-byte as modules/base/default.nix must
  # render it for username "resident". A whole-block pin rather than
  # per-string greps so the *precedence* is part of what is pinned:
  # password-changed silences everything, password-absent outranks the
  # seeded message. Deliberately duplicated from the module — a change
  # to either side must touch both, which is what "pinned literally"
  # means. (The bare `resident` arguments are what this nixpkgs pin's
  # escapeShellArg emits for a word needing no quoting.)
  expectedBanner = pkgs.writeText "expected-banner-block" ''
    if [ ! -e /var/lib/castle-turing/password-changed ]; then
      if [ -e /var/lib/castle-turing/password-absent ]; then
        printf '\n\033[1;33mNote:\033[0m the %s account has no password at all: most likely its seed never decrypted when the account was first created, and a rebuild will not repair an existing account. Set one now with \033[1msudo passwd %s\033[0m.\n\n' resident resident
      else
        printf '\n\033[1;33mNote:\033[0m the %s account is still using its seeded initial password. Run \033[1mpasswd\033[0m to set your own.\n\n' resident
      fi
    fi
  '';
in
pkgs.runCommand "password-reminder-states" { } ''
  seed=${pkgs.lib.escapeShellArg seedHash}
  other=${pkgs.lib.escapeShellArg otherHash}

  # run_case NAME SHADOW-FIELD SEED-MODE PRIOR-MARKER WANTED-MARKER
  #   SHADOW-FIELD: the field, or __no-resident-line__ for a shadow
  #                 file with no entry for the account at all
  #   SEED-MODE: present | missing (the age-key-never-planted machine)
  #   markers:   none | changed | absent | both ("both" as a prior is
  #              the crash-persisted state a kill between two marker
  #              writes could leave; as a result it is what no run may
  #              ever produce or preserve)
  run_case() {
    name=$1; field=$2; seedmode=$3; prior=$4; want=$5
    dir="$PWD/case-$name"
    mkdir -p "$dir/state"
    if [ "$field" = __no-resident-line__ ]; then
      printf 'root:*:20000:0:99999:7:::\n' >"$dir/shadow"
    else
      printf 'root:*:20000:0:99999:7:::\n%s:%s:20000:0:99999:7:::\n' resident "$field" >"$dir/shadow"
    fi
    seedpath="$dir/seed"
    if [ "$seedmode" = present ]; then
      printf '%s\n' "$seed" >"$seedpath"
    fi
    case "$prior" in
      changed) touch "$dir/state/password-changed" ;;
      absent) touch "$dir/state/password-absent" ;;
      both)
        touch "$dir/state/password-changed"
        touch "$dir/state/password-absent"
        ;;
    esac
    # bash -e replicates the NixOS job-script shebang (`bash -e`, no
    # pipefail) the unit really runs under.
    ${pkgs.bash}/bin/bash -e ${scriptFile} "$dir/shadow" "$dir/state" "$seedpath"
    got=none
    if [ -e "$dir/state/password-changed" ]; then got=changed; fi
    if [ -e "$dir/state/password-absent" ]; then
      if [ "$got" = changed ]; then got=both; else got=absent; fi
    fi
    if [ "$got" != "$want" ]; then
      echo "FAIL: $name (field='$field' seed=$seedmode prior=$prior): wanted $want, got $got"
      exit 1
    fi
    echo "ok: $name -> $want"
  }

  # State 1, seeded: a hash equal to the seed, however locked (a lock
  # prefix is not a password change — 0032's `passwd -l` bug).
  run_case seeded-fresh "$seed" present none none
  run_case seeded-locked "!$seed" present none none
  run_case seeded-clears-changed "$seed" present changed none
  run_case seeded-clears-absent "$seed" present absent none

  # State 2, changed: a real hash differing from the seed.
  run_case changed "$other" present none changed
  run_case changed-locked "!$other" present none changed
  run_case recovered-from-absent "$other" present absent changed
  run_case heals-crash-both "$other" present both changed

  # State 3, no password at all: every field shape the guard groups,
  # including the double-strip case (`!!`) that motivated stripping
  # twice.
  run_case absent-bang '!' present none absent
  run_case absent-double-bang '!!' present none absent
  run_case absent-star '*' present none absent
  run_case absent-locked-star '!*' present none absent
  run_case absent-empty "" present none absent
  run_case absent-overrides-changed '!' present changed absent

  # The headline machine (the brief's "Why"): the age key is missing,
  # so the seed is unreadable AND the account is passwordless. The
  # pre-0036 script order exited at the unreadable-seed guard before
  # ever reading shadow, and kept showing the seeded-password message.
  run_case absent-seed-missing '!' missing none absent

  # State 4, unknowable: a real hash but no seed to compare against.
  # password-changed is left exactly as it was, in both directions --
  # with one decidable exception: a real hash appearing after
  # password-absent cannot be the seed (creation with an unresolved
  # seed writes a lock, never the seed), so that transition is proof
  # of a hand-set password and records changed even seedless. Caught
  # by cross-model review: without it, `sudo passwd` on the
  # never-fixed-key machine ended in the false seeded message.
  run_case unknowable-keeps-changed "$other" missing changed changed
  run_case unknowable-keeps-none "$other" missing none none
  run_case recovered-seed-missing "$other" missing absent changed

  # No entry for the account in the shadow file at all: not evidence,
  # so nothing is touched -- in particular an earned password-changed
  # survives a renamed username or a mid-rewrite shadow copy.
  run_case no-line-keeps-changed __no-resident-line__ present changed changed
  run_case no-line-keeps-none __no-resident-line__ present none none
  run_case no-line-keeps-absent __no-resident-line__ missing absent absent

  # The banner: pin the generated three-state block byte-for-byte as a
  # substring of the merged interactiveShellInit (other modules may
  # legitimately contribute their own lines around it).
  init="$(cat ${shellInitFile})"
  expected="$(cat ${expectedBanner})"
  case "$init" in
    *"$expected"*)
      echo "ok: banner block pinned byte-for-byte"
      ;;
    *)
      echo "FAIL: environment.interactiveShellInit does not contain the expected three-state banner block"
      echo "--- expected (test/password-reminder/check.nix):"
      cat ${expectedBanner}
      echo "--- generated (modules/base/default.nix):"
      cat ${shellInitFile}
      exit 1
      ;;
  esac

  touch $out
''
