# test/desktop-loop/test.nix — docs/tasks/0011: boot the REAL desktop
# stack (modules/base, home, desktop, dev, agent — no test-only stand-in
# for the mechanism under test itself) in a NixOS VM, log in through the
# real, unmodified greetd+tuigreet prompt, press the real
# $mod+Shift+space keybinding, and assert on the journal records the
# loop actually produces.
#
# Uses the `nixosTest`/`pkgs.testers.runNixOSTest` framework (a Python
# driver: `wait_for_unit`, `send_key`, `swaymsg`-over-IPC, `screenshot`,
# OCR) rather than extending test/vm-install/'s shell-driven QEMU
# harness — that one exists to exercise *installation* (docs/tasks/0004),
# a different job, and must stay untouched. nixpkgs' own
# nixos/tests/sway.nix is the closest upstream template; read it before
# changing this file — its `-vga none -device virtio-gpu-pci` +
# `WLR_RENDERER=pixman` combination (a real KMS device via virtio, with
# software rendering since there is no working GL in a VM) is copied
# from there directly, not invented here.
#
# Exactly two deliberate departures from a real deployment, both forced
# by "there is no GPU in this VM" and nothing else about the mechanism
# under test:
#
#   1. `virtualisation.qemu.options` gives Sway a KMS device to bind to
#      (see above) — copied from nixpkgs' sway.nix.
#   2. `WLR_RENDERER=pixman` is injected by wrapping the exact `sway`
#      binary tuigreet is told to launch
#      (`env WLR_RENDERER=pixman <sway>`) rather than via a system-wide
#      `environment.variables`: greetd launches the session directly,
#      not through a login shell that would source /etc/profile, so a
#      system-wide env var is not reliably visible to it.
#      test/vm-install/vm-test-system.nix already uses this exact
#      technique to get an env var into a greetd-launched session (see
#      its header comment) — applied here to the *real*
#      tuigreet-mediated login path instead of that harness's
#      auto-login bypass, since docs/tasks/0011 asks for the real login,
#      not a shortcut around it.
#
# Everything else — the admin's typed password, tuigreet itself, the
# Sway config home-manager generates, the modal, the router, the
# journal — is the unmodified, published mechanism. No hosts/* module is
# imported: nixosTest supplies its own virtual hardware profile already
# (true of every nixosTest; no test node ever imports a real hardware
# profile like host-xps9370's nixos-hardware/disko pieces), so this is
# the same module set nixosConfigurations.example already proves
# *evaluates* — this test proves it *boots*.
{ self }:
{ pkgs, lib, ... }:
let
  # A fixed, obviously-synthetic VM-only credential: not a real
  # person's password, and this VM is destroyed at the end of the test
  # run. Generated with:
  #   openssl passwd -6 -salt castleturingtest 'castle-turing-harness-password'
  # and kept as a literal rather than computed at eval time so this
  # file has no extra build-time dependency on openssl being on the
  # evaluator's PATH. modules/desktop's own header comment explains why
  # a login prompt with no working password would recreate
  # docs/tasks/0003-findings.md finding #1 — this is what lets the test
  # actually get past that prompt for real, the same way a resident's
  # private layer would (docs/private-layer.md), just with a throwaway
  # value instead of a real person's.
  testPassword = "castle-turing-harness-password";
  testPasswordHash = "$6$castleturingtest$zio0DohVCoFAZ/ByLr3cUIhPge5lXZ0O1ylANx36BtdkaeKzOqdKht4KBROWu5o3dVZNyIG7UDKROXEl6WVjx0";

  # test/agent-loop/'s own scripted-worker convention (docs/tasks/0011's
  # non-goal: not the real `claude -p` tenant, which needs network and
  # credentials a VM test must not have) — reused as-is via
  # copy_from_host rather than reimplemented, so this test exercises
  # the exact same worker contract test/agent-loop/run.sh already
  # proves, not a second, subtly different one. Same for
  # check_assertions.py: an independent, already-reviewed re-derivation
  # of the frontmatter format that does not share agent/castle's own
  # parser (see that file's header for why that independence matters).
  scriptedWorker = ../agent-loop/scripted-worker.sh;
  checkAssertions = ../agent-loop/check_assertions.py;

  # Deliberately non-default (docs/tasks/0013's bug 2b): the fallback
  # this same value would coincide with is $HOME/.local/state/castle
  # (agent/castle's state_dir()), and a harness where the configured
  # path and the fallback are identical cannot tell a working
  # CASTLE_STATE_DIR handoff from a silently-fallen-back one — that's
  # exactly the shape of bug 2 itself, and exactly what made the
  # original version of this test blind to it. Modeled on the private
  # layer's own real shape (modules/agent's stateDir option doc example,
  # "/home/<you>/private/state") rather than an arbitrary path, so this
  # test exercises the configuration a real resident actually runs, not
  # a synthetic one.
  testStateDir = "/home/resident/private/state";

  # Plain, hardware-neutral fixture text — not personal data, never
  # meant to resemble a real complaint or a real correction.
  complaintBody = "The cursor is hard to see on this VM after the loop test logs in.";
  correctionBody = "You interrupted me over something that could have waited.";
in
{
  name = "desktop-loop";
  # Same escape hatch nixpkgs' own nixos/tests/sway.nix needs, and for
  # the same reason: the driver's mypy-based type checker trips on this
  # script's `swaymsg` helper (a plain function returning `dict | None`
  # depending on a runtime branch), a shape mypy cannot narrow from
  # here. Confirmed against sway.nix's own identical comment before
  # copying it — not applied speculatively.
  skipTypeCheck = true;
  # No structured signal exists before Sway itself starts (that is
  # what the brief calls "genuinely hard" about a headless compositor
  # login) — OCR paces the two tuigreet prompts below. Everything after
  # Sway starts asserts via its own IPC socket or the journal's own
  # files, never pixels, per docs/tasks/0011's scope.
  enableOCR = true;
  # `runNixOSTest` passes `node.pkgs`, which by default makes every
  # `nixpkgs.*` option (including `nixpkgs.config`) read-only across all
  # nodes (nixos/lib/testing/nodes.nix: `node.pkgsReadOnly` defaults to
  # `node.pkgs != null`) by importing
  # nixos/modules/misc/nixpkgs/read-only.nix, which disables the normal
  # nixpkgs module outright and marks `nixpkgs.config` a `types.unique`
  # option. `modules/dev` sets `nixpkgs.config.allowUnfreePredicate`
  # unconditionally (it has no reason to expect it's running inside a
  # nixosTest, and must not be modified just to accommodate one — see
  # this file's header on staying byte-for-byte the published
  # mechanism), so without this, evaluation fails outright with
  # "the option `nodes.machine.nixpkgs.config' is defined multiple
  # times" before a single derivation is even built — this is
  # documented as the intended escape hatch for exactly this case
  # ("Set this to false when any of the nodes... need to configure any
  # of the nixpkgs.* options").
  node.pkgsReadOnly = false;

  nodes.machine =
    { config, pkgs, ... }:
    let
      # A single store path with no embedded spaces, rather than
      # threading `env WLR_RENDERER=pixman <sway>` through greetd's own
      # `command`-string word-splitting AND tuigreet's own forwarded
      # `--cmd` value as one quoted token (code-review finding on this
      # branch: that double-parse chain is real but untested anywhere
      # else in this repo, and worth eliminating rather than trusting
      # it). A wrapper script sidesteps both parsers entirely — greetd
      # and tuigreet only ever see one bare word here. Full store paths
      # inside it (not bare `env`/`sway`, relying on $PATH), same
      # reasoning test/vm-install/vm-test-system.nix's own header
      # comment gives for its identical choice: greetd/its children run
      # with whatever minimal environment the service unit has, not a
      # guaranteed $PATH.
      swayHeadless = pkgs.writeShellScript "sway-headless" ''
        exec ${pkgs.coreutils}/bin/env WLR_RENDERER=pixman ${config.programs.sway.package}/bin/sway
      '';
    in
    {
      imports = [
        self.nixosModules.base
        self.nixosModules.home
        self.nixosModules.desktop
        self.nixosModules.dev
        self.nixosModules.agent
      ];

      system.stateVersion = "26.11";

      castle.admin = {
        username = "resident";
        sshKeys = [ "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key" ];
        initialHashedPassword = testPasswordHash;
      };
      castle.person = {
        gitUserName = "Resident";
        gitUserEmail = "resident@example.invalid";
      };
      # See testStateDir's own comment above (bug 2b): this is the one
      # line that makes the assertions below capable of catching bug 2
      # — without it, the configured path and CASTLE_STATE_DIR's
      # fallback are the same directory and the test cannot fail on
      # this mechanism no matter which one actually fired.
      castle.agent.stateDir = testStateDir;

      # Not a departure from the mechanism under test: a bare NixOS
      # system has no `python3` on $PATH by default (modules/agent's
      # castleCli wraps its own python3 internally, at a store path
      # never exposed as a bare command). test/agent-loop/
      # check_assertions.py deliberately does not import agent/castle
      # (see its own header comment for why), so it needs its own
      # interpreter on $PATH rather than riding on castle's.
      environment.systemPackages = [ pkgs.python3 ];

      # Departure 1 — see file header.
      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      # A full desktop (Sway + Firefox + Emacs + claude-code + OCR
      # polling the framebuffer) is a heavier boot than modules/base
      # alone; give it real headroom rather than find out the hard way
      # in CI, where there is no way to attach and see what's slow.
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;

      # Departure 2 — see file header. Otherwise byte-for-byte
      # modules/desktop's own `default_session.command` (compare
      # against that module's source): the `--time --remember --cmd`
      # flags are unchanged, only what `--cmd` resolves to differs.
      services.greetd.settings.default_session.command =
        lib.mkForce "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${swayHeadless}";
    };

  testScript = ''
    import datetime as dt
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    # --- Log in for real: type at the real, unmodified tuigreet -------
    machine.wait_until_succeeds("pgrep -x tuigreet", timeout=dt.timedelta(minutes=2))
    machine.wait_for_text("sername")
    machine.screenshot("01-tuigreet-username-prompt")
    machine.send_chars("resident\n")
    machine.wait_for_text("assword")
    machine.screenshot("02-tuigreet-password-prompt")
    machine.send_chars("${testPassword}\n")

    # --- Assert Sway is actually running: its own IPC socket, not
    # pixels (docs/tasks/0011 scope item 2). ---------------------------
    # wait_until_succeeds returns the successful attempt's own captured
    # output, so this is the only invocation needed — a second, separate
    # `machine.succeed` of the identical command would just re-run it.
    SWAYSOCK = machine.wait_until_succeeds(
        "su - resident -c 'ls /run/user/*/sway-ipc.*.sock'",
        timeout=dt.timedelta(minutes=3),
    ).strip()
    machine.screenshot("03-sway-session")

    def swaymsg(query_type):
        shell = f"SWAYSOCK={SWAYSOCK} swaymsg -t {query_type}"
        out = machine.succeed(f"su - resident -c '{shell}'")
        return json.loads(out)

    version = swaymsg("get_version")
    assert "sway" in json.dumps(version).lower(), f"get_version did not look like Sway: {version}"
    print(f"OK: Sway session confirmed live over its own IPC socket: {version}")

    # --- Press the key, file a request (docs/tasks/0011 scope item 3) -
    NODE_GROUPS = ["nodes", "floating_nodes"]

    def walk(tree):
        yield tree
        for group in NODE_GROUPS:
            for node in tree.get(group, []):
                yield from walk(node)

    def has_modal():
        return any(node.get("app_id") == "castle-modal" for node in walk(swaymsg("get_tree")))

    machine.send_key("meta_l-shift-spc")
    retry(lambda last: has_modal())
    machine.screenshot("04-modal-open")

    machine.send_chars("${complaintBody}\n.\n")
    machine.sleep(2)
    machine.send_key("ret")  # bare Enter: default classification = "something to fix" (request)
    machine.sleep(1)
    machine.screenshot("05-modal-filed-request")
    machine.send_key("ret")  # dismiss ("Press Enter to close.")
    retry(lambda last: not has_modal())

    # ${testStateDir}, not $HOME/.local/state/castle: this is bug 2b's
    # actual assertion, and the whole point of setting a non-default
    # castle.agent.stateDir above — see that binding's comment. If
    # CASTLE_STATE_DIR silently failed to reach castle-modal (bug 2, the
    # regression this guards), the record would land at the fallback
    # instead and every `ls`/`cat` below against ${testStateDir} would
    # fail outright rather than quietly passing against the wrong file.
    request_path = machine.succeed(
        "su - resident -c 'ls ${testStateDir}/journal/*-request-*.md'"
    ).strip()
    request_id = request_path.rsplit("/", 1)[-1][: -len(".md")]
    print(f"OK: modal filed request {request_id}")

    request_record = machine.succeed(f"su - resident -c 'cat {request_path}'")
    assert "type: request" in request_record, request_record
    assert "provenance: requested" in request_record, request_record
    assert "seat: intake" in request_record, request_record
    assert "${complaintBody}" in request_record, request_record
    print("OK: request record carries the typed text verbatim, with the modal's real provenance/seat")

    # --- castle route / a scripted worker / castle digest (docs/tasks/
    # 0011 scope item 4; non-goal: not the real `claude -p` tenant) ---
    machine.copy_from_host("${scriptedWorker}", "/tmp/scripted-worker.sh")
    machine.copy_from_host("${checkAssertions}", "/tmp/check_assertions.py")

    worker_out = machine.succeed(
        f"su - resident -c 'bash /tmp/scripted-worker.sh castle {request_id}'"
    )
    print(worker_out)

    route_out = machine.succeed("su - resident -c 'castle route'")
    print(route_out)
    assert "-> notify" in route_out, (
        f"castle route did not report routing the requested-provenance result to notify: {route_out}"
    )

    journal_dump = machine.succeed("su - resident -c 'cat ${testStateDir}/journal/*.md'")
    assert "type: decision" in journal_dump, journal_dump
    assert "evidence:" in journal_dump and request_id in journal_dump, journal_dump
    print("OK: castle route wrote a decision record citing evidence")

    digest_out = machine.succeed("su - resident -c 'castle digest'")
    assert f"Errand {request_id}" in digest_out, digest_out
    assert "${complaintBody}" in digest_out, digest_out
    print("OK: castle digest rendered the errand")

    # --- File a correction through the modal's other path (docs/tasks/
    # 0011 scope item 4, second half) ----------------------------------
    machine.send_key("meta_l-shift-spc")
    retry(lambda last: has_modal())
    machine.screenshot("06-modal-open-for-correction")
    machine.send_chars("${correctionBody}\n.\n")
    machine.sleep(2)
    machine.send_key("t")  # "telling you how you're doing" -> correction
    machine.sleep(1)
    machine.screenshot("07-modal-filed-correction")
    machine.send_key("ret")  # dismiss
    retry(lambda last: not has_modal())

    correction_path = machine.succeed(
        "su - resident -c 'ls ${testStateDir}/journal/*-correction-*.md'"
    ).strip()
    correction_id = correction_path.rsplit("/", 1)[-1][: -len(".md")]
    correction_record = machine.succeed(f"su - resident -c 'cat {correction_path}'")
    assert "type: correction" in correction_record, correction_record
    assert "seat: intake" in correction_record, correction_record
    assert "surface: modal" in correction_record, correction_record
    assert "${correctionBody}" in correction_record, correction_record
    print(f"OK: modal filed correction {correction_id} through its other path")

    model_content = machine.succeed("su - resident -c 'cat ${testStateDir}/resident-model.md'")
    assert "provenance: volunteered" in model_content, model_content
    assert f"stated: {correction_id}" in model_content, model_content
    assert "${correctionBody}" in model_content, model_content
    print("OK: the correction produced a volunteered resident-model entry citing it")

    # --- Independent verification: check_assertions.py re-derives the
    # frontmatter itself rather than trusting agent/castle's own parser
    # (its own header explains why), so this is a second,
    # differently-implemented pass over the exact same journal the
    # modal and the real Sway session just produced. -------------------
    check_out = machine.succeed(
        "su - resident -c 'python3 /tmp/check_assertions.py ${testStateDir}/journal'"
    )
    print(check_out)
    assert check_out.startswith("OK:"), check_out

    validate_out = machine.succeed("su - resident -c 'castle validate'")
    print(validate_out)

    print("PASS: the ambient-intake loop ran end to end in a real Sway session driven by keystrokes alone.")
  '';
}
