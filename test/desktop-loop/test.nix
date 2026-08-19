# test/desktop-loop/test.nix — docs/tasks/0011: boot the REAL desktop
# stack (modules/base, home, desktop, dev, agent — no test-only stand-in
# for the mechanism under test itself) in a NixOS VM, log in through the
# real, unmodified greetd+tuigreet prompt, press the real
# $mod+Shift+Return keybinding, and assert on the journal records the
# loop actually produces.
#
# Since docs/tasks/0021-auto-dispatch.md this test also enables
# castle.agent.dispatch.enable, which turns it into that feature's
# acceptance condition: the resident presses one chord, types one
# complaint, and a claimed, worked, routed errand appears with no
# `castle work` or `castle route` typed anywhere. See the
# dispatchWorker binding below for the safety floor that keeps CI from
# attempting a real model call while doing it.
#
# Since docs/tasks/0023-resume-cold.md it is that task's acceptance
# condition too, and by the same standard: the resident answers a
# blocking question through the real modal, and the errand continues —
# a second turn, with a fresh tenant handed the errand's own records and
# the resident's own words, still with no command typed anywhere.
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

  # check_assertions.py: an independent, already-reviewed re-derivation
  # of the frontmatter format that does not share agent/castle's own
  # parser (see that file's header for why that independence matters).
  checkAssertions = ../agent-loop/check_assertions.py;

  # The worker tenant this VM runs, and it is a **safety floor rather
  # than an incidental config choice** (docs/tasks/0021-auto-dispatch.md
  # §7). `castle.agent.worker.command` defaults to
  # `castle-worker-claude`, a real `claude -p` invocation, and this VM
  # imports modules/dev, which installs the `claude` binary — so
  # enabling dispatch without pinning the command would make CI attempt
  # a real, networked model call with credentials the CI environment
  # does not have, on every run.
  #
  # It reuses test/agent-loop/contract-worker.sh rather than
  # reimplementing the contract, the same way this file already reuses
  # check_assertions.py: what runs in a booted VM should be what the
  # no-Nix harness already proves. The wrapper exists for two concrete
  # reasons — the fixture's `#!/usr/bin/env bash` shebang and its
  # `cat`/`sleep` calls both need tools on $PATH, and a systemd *user*
  # service's $PATH is not something this test should have to assume.
  # `pkgs.writeShellScript` gives an absolute-shebang, executable store
  # path; the PATH line supplies the rest.
  #
  # It raises a `question` before running the contract worker, and that
  # is not decoration: swapping scripted-worker.sh out for the contract
  # fixtures removed the only thing in this VM that ever produced a
  # question record, leaving the worker-raises-a-question-and-the-router
  # delivers-it path — a central claim of docs/architecture.md — with no
  # coverage at all inside a booted systemd session. A tenant that files
  # a question mid-errand and finishes anyway is exactly what
  # agent/castle-worker-claude's prompt instructs a real tenant to do.
  # stdout is the reasoning channel that lands in the result body, so
  # the record id goes to /dev/null rather than into the account.
  # Since docs/tasks/0023-resume-cold.md the question is raised
  # `--blocking`, and only on a turn that is not itself a resumption.
  # Neither half is decoration.
  #
  # `--blocking` is what makes answering it through the real modal, in
  # the real Sway session, actually continue the errand — this task's
  # acceptance condition, asserted at the end of the script with no
  # `castle work` and no `castle route` typed anywhere, exactly the way
  # 0021's own was.
  #
  # The CASTLE_RESUME_ANSWER_IDS guard is what stops that continuation
  # raising a *third* question this run would then have to route and
  # account for. A tenant that questions unconditionally, resumed turns
  # included, would leave the journal holding a question nobody
  # answered at the moment the test declares success.
  dispatchWorker = pkgs.writeShellScript "castle-dispatch-test-worker" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep ]}:$PATH
    # Read the errand's records here rather than letting the contract
    # fixture consume them, then hand the same bytes on: this wrapper
    # has to see the continuation packet to say anything true about it,
    # and contract-worker.sh still gets exactly what `castle work`
    # wrote.
    packet="$(cat)"
    if [ -z "''${CASTLE_RESUME_ANSWER_IDS:-}" ]; then
      castle record --type question --provenance requested --seat worker \
        --refs "$CASTLE_REQUEST_ID" \
        --blocking \
        --body "Scripted posture question for $CASTLE_REQUEST_ID: fix it and tell you, or explain first?" \
        >/dev/null
    else
      echo "castle-dispatch-test-worker: resumed with $CASTLE_RESUME_ANSWER_IDS"
      # The whole claim this VM exists to make about resumption, checked
      # by the tenant that would be lied to: a fresh process, with no
      # memory of the turn that asked the question, received the
      # resident's own answer on its stdin. Asserted here rather than
      # only in the test script because a packet that arrived empty
      # would otherwise still produce a perfectly healthy-looking
      # second result.
      if printf '%s\n' "$packet" | grep -qF -- "${answerBody}"; then
        echo "castle-dispatch-test-worker: the packet carried the resident's answer"
      else
        echo "castle-dispatch-test-worker: the packet did NOT carry the resident's answer" >&2
        exit 7
      fi
    fi
    printf '%s\n' "$packet" | ${pkgs.bash}/bin/bash ${../agent-loop/contract-worker.sh}
  '';

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

  # Non-default for the same reason testStateDir is. `castle work`
  # used to fall back to its working directory when no repo root was
  # configured, and the dispatch unit's working directory is `%h` — so
  # a test that left this alone could not tell a working
  # castle.agent.repo.private handoff from a silent fallback to the
  # resident's home directory. docs/tasks/0024-config-target.md
  # removed that fallback, but the blindness argument is unchanged:
  # a default-valued fixture proves nothing about the handoff. Nothing
  # is checked out here beyond the `.git` the activation script below
  # creates — the path exists to be carried through the unit's
  # environment into the tenant's, where the scripted worker prints it
  # back, and (since 0024) to satisfy the pre-flight that refuses a
  # private root which is not a working tree.
  testRepoRoot = "/home/resident/private/checkout";

  # Plain, hardware-neutral fixture text — not personal data, never
  # meant to resemble a real complaint or a real correction.
  complaintBody = "The cursor is hard to see on this VM after the loop test logs in.";
  correctionBody = "You interrupted me over something that could have waited.";
  # The second errand, and the answer typed at its question
  # (docs/tasks/0022-answer-in-ui.md). Distinct from complaintBody so
  # every assertion below can tell the two errands apart by their text
  # alone, and hardware-neutral for the same reason the two above are.
  answerComplaintBody = "The panel clock is hard to read at a glance on this VM.";
  answerBody = "Make it larger and leave the format alone.";
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
  # login) — OCR paces the two tuigreet prompts below, and one moment
  # after them: the answer picker, where a keypress sent before the
  # program has engaged cbreak is discarded by TCSAFLUSH rather than
  # merely mistimed (docs/tasks/0022, review round 1). Everything else
  # after Sway starts asserts via its own IPC socket or the journal's
  # own files, never pixels, per docs/tasks/0011's scope.
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

      # This node imports modules/desktop but no host module, so nothing
      # else states what a swapless machine should do at critical
      # battery. modules/desktop asserts that upower's default
      # (HybridSleep) cannot stand on a machine with no swap — see task
      # 0020 — and this VM has none. A test VM has no battery either, so
      # the value is inert here; it is declared to satisfy the same
      # honesty the assertion enforces everywhere else.
      castle.power.criticalPowerAction = "PowerOff";

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

      # docs/tasks/0021-auto-dispatch.md: with these three lines, this
      # test becomes the feature's actual acceptance condition — file
      # one request through the modal and a routed outcome appears with
      # no subsequent resident CLI action at all. It also proves the
      # systemd user unit really saw the configured CASTLE_STATE_DIR
      # and CASTLE_PRIVATE_ROOT (bug 2b's shape, now proven for the
      # dispatch unit specifically rather than only for the modal): the
      # scripted tenant prints its $CASTLE_PRIVATE_ROOT, and the test
      # asserts that string lands in the result record.
      # An existing state directory IS the documented resident
      # contract: castle.agent.stateDir points into a private repo
      # checkout that has already been cloned onto the machine
      # (docs/private-layer.md). `castle dispatch` refuses to create it
      # — a sweep that mkdir'd the resident's state directory before
      # their journal was restored into it would break the restore and
      # write a watermark claiming nothing predates it — so this VM has
      # to supply what a real host's private repo supplies. The
      # ordering the assertions below depend on — an empty-refs
      # watermark already down before the resident files anything —
      # comes from the castle-dispatch-watermark unit, which runs at
      # user-manager start, not from anything about this rule; the
      # directory has to exist for that unit to find a journal to mark.
      systemd.tmpfiles.rules = [
        "d /home/resident/private 0755 resident users -"
        "d ${testStateDir} 0755 resident users -"
      ];

      # A real git working tree at testRepoRoot, not a bare directory.
      # Since docs/tasks/0024-config-target.md `castle work` refuses a
      # turn whose private checkout is not one — the same reasoning as
      # the state directory above: a real host's private repo is a
      # clone the resident made before turning dispatch on
      # (docs/private-layer.md), and this VM has to supply what that
      # clone supplies. It stays empty apart from `.git`; nothing is
      # checked out here, and the path exists only to be carried
      # through the unit's environment into the tenant's, where the
      # scripted worker prints it back.
      #
      # An activation script rather than a tmpfiles rule because
      # tmpfiles cannot run `git init`, and it runs at boot activation,
      # well before the 5s-after-login dispatch timer could reach it.
      system.activationScripts.castleLoopTestCheckout = ''
        mkdir -p ${testRepoRoot}
        if [ ! -e ${testRepoRoot}/.git ]; then
          ${pkgs.git}/bin/git -C ${testRepoRoot} init -q
        fi
        chown -R resident:users ${testRepoRoot}
      '';

      castle.agent.dispatch.enable = true;
      castle.agent.worker.command = "${dispatchWorker}";
      castle.agent.repo.private = testRepoRoot;

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

    # --- Assert the session opened on workspace 1, before any key is
    # pressed (docs/tasks/0019, defect 1). Sway takes the first workspace
    # *mentioned in the config* as its initial workspace; home-manager
    # emits `keybindings` sorted by key name, so without
    # `defaultWorkspace` hoisting the workspace-1 binding to the front
    # (modules/home/default.nix), `Mod1+0`'s `workspace number 10`
    # binding sorts first and every session opens on workspace 10
    # instead. This is red on the code this brief starts from — it would
    # report "10" here. ---------------------------------------------------
    workspaces = swaymsg("get_workspaces")
    focused = [ws for ws in workspaces if ws.get("focused")]
    assert len(focused) == 1, f"expected exactly one focused workspace, got: {workspaces}"
    focused_name = focused[0]["name"]
    assert focused_name == "1", (
        f"session opened on workspace {focused_name!r}, not workspace \"1\": {workspaces}. "
        "Sway takes the first workspace mentioned in the generated config as its "
        "initial workspace; see docs/tasks/0019 (defect 1) and "
        "wayland.windowManager.sway.config.defaultWorkspace in modules/home/default.nix."
    )
    print("OK: session opened on workspace 1")

    # --- Press the key, file a request (docs/tasks/0011 scope item 3) -
    NODE_GROUPS = ["nodes", "floating_nodes"]

    def walk(tree):
        yield tree
        for group in NODE_GROUPS:
            for node in tree.get(group, []):
                yield from walk(node)

    def has_modal():
        return any(node.get("app_id") == "castle-modal" for node in walk(swaymsg("get_tree")))

    machine.send_key("meta_l-shift-ret")
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

    # --- The errand starts itself (docs/tasks/0021-auto-dispatch.md) -
    # No `castle work` and no `castle route` are typed anywhere below.
    # A systemd user path unit notices the request record the modal
    # just wrote, `castle dispatch` takes the errand's lease, records a
    # claim, runs the configured (scripted, model-free) tenant, and
    # routes the result — all of it inside the real Sway session, from
    # one keystroke's worth of resident action.
    machine.copy_from_host("${checkAssertions}", "/tmp/check_assertions.py")

    claim_path = machine.wait_until_succeeds(
        "su - resident -c 'ls ${testStateDir}/journal/*-claim-*.md'",
        timeout=dt.timedelta(minutes=5),
    ).strip()
    claim_record = machine.succeed(f"su - resident -c 'cat {claim_path}'")
    assert f"refs: {request_id}" in claim_record, claim_record
    assert "seat: worker" in claim_record, claim_record
    print("OK: dispatch claimed the errand — 'in progress' is now something the journal can earn")

    result_path = machine.wait_until_succeeds(
        "su - resident -c 'ls ${testStateDir}/journal/*-result-*.md'",
        timeout=dt.timedelta(minutes=5),
    ).strip()
    result_record = machine.succeed(f"su - resident -c 'cat {result_path}'")
    assert "outcome: completed" in result_record, result_record
    assert f"refs: {request_id}" in result_record, result_record
    assert "provenance: requested" in result_record, result_record
    # The tenant printed its own $CASTLE_PRIVATE_ROOT: this string can
    # only be here if the unit's Environment= reached the worker
    # process, which is bug 2b's shape proven for the dispatch unit.
    assert "${testRepoRoot}" in result_record, result_record
    # docs/tasks/0024-config-target.md, the same handoff one layer on:
    # contract-worker.sh stamps $CASTLE_TARGET_FILE with `private` and
    # `castle work` folds that into the result's own frontmatter. This
    # is the cheapest available proof that the target channel survives
    # the real dispatch unit's environment, not only the plain-bash
    # harness's.
    assert "target: private" in result_record, result_record
    print("OK: a worker turn ran and wrote a completed result, with no resident CLI action")

    # The routing decision, produced by the same sweep's tail step.
    machine.wait_until_succeeds(
        "su - resident -c \"grep -l '^channel: notify' ${testStateDir}/journal/*-decision-*.md\"",
        timeout=dt.timedelta(minutes=5),
    )

    # The question the tenant raised mid-errand, and the router's
    # decision about it — the path nothing else in this VM exercises.
    question_path = machine.wait_until_succeeds(
        "su - resident -c 'ls ${testStateDir}/journal/*-question-*.md'",
        timeout=dt.timedelta(minutes=5),
    ).strip()
    question_id = question_path.rsplit("/", 1)[-1][: -len(".md")]
    question_record = machine.succeed(f"su - resident -c 'cat {question_path}'")
    assert f"refs: {request_id}" in question_record, question_record
    assert "seat: worker" in question_record, question_record
    question_decision = machine.wait_until_succeeds(
        "su - resident -c \"grep -l '^refs: " + question_id + "$' ${testStateDir}/journal/*-decision-*.md\"",
        timeout=dt.timedelta(minutes=5),
    ).strip()
    assert "channel: notify" in machine.succeed(
        f"su - resident -c 'cat {question_decision}'"
    ), question_decision
    print(f"OK: the tenant's mid-errand question {question_id} was routed to notify by the same sweep")

    journal_dump = machine.succeed("su - resident -c 'cat ${testStateDir}/journal/*.md'")
    assert "type: decision" in journal_dump, journal_dump
    assert "evidence:" in journal_dump and request_id in journal_dump, journal_dump
    # The watermark decision (docs/tasks/0021 §2.2): written by
    # castle-dispatch-watermark at the instant this session's user
    # manager started, before the resident had a compositor to file
    # anything with.
    assert "seat: dispatch" in journal_dump, journal_dump
    assert "watermark:" in journal_dump, journal_dump
    print("OK: dispatch routed the auto-produced result and left a watermark record behind")

    # --- The watermark did not swallow the request that woke dispatch
    # (docs/tasks/0021 §2.2) -------------------------------------------
    #
    # The direct regression assertion for the defect that made this
    # unit exist. This VM's journal starts empty, so a watermark
    # established at session start has nothing outstanding to name and
    # its `refs` must be empty. When the *first sweep* owned that write
    # instead, a graphical login plus one modal keystroke beat its 5s
    # OnStartupSec: the resident's request was outstanding when the
    # watermark landed, was named in these refs, and was excluded from
    # automatic dispatch by name — permanently, with the sweep printing
    # "nothing eligible" and nothing ever triggering again. If that
    # race is ever reintroduced, the request id reappears on this line.
    watermark_path = machine.succeed(
        "su - resident -c \"grep -l '^watermark: ' ${testStateDir}/journal/*-decision-*.md\""
    ).strip()
    watermark_record = machine.succeed(f"su - resident -c 'cat {watermark_path}'")
    assert request_id not in watermark_record, watermark_record
    # `render_record` writes an empty refs list as the bare field with
    # nothing after the colon (agent/castle's write_record joins the
    # list with commas; the empty join is ""), so this is the exact
    # serialization of "excluded nothing."
    assert "\nrefs: \n" in watermark_record, watermark_record
    print("OK: the watermark's refs are empty — the resident's first request was not excluded by it")

    # And the unit that wrote it really is the one that ran. Three
    # properties, not one, because `Result` alone asserts nothing:
    # systemd reports `Result=success` for a unit that does not exist
    # AND for one that exists but never started, so a check on it
    # alone would stay green through a typo in the unit name, a lost
    # `wantedBy`, or a `ConditionUser` that excluded the resident —
    # every failure it is supposed to catch. `LoadState` proves the
    # unit exists, a non-empty `ExecMainStartTimestamp` proves its
    # ExecStart actually ran (a skipped condition leaves it empty),
    # and `Result` then proves it did not fail. `is-active` is no use
    # either way: this oneshot sets no RemainAfterExit, so it is
    # inactive once finished, exactly like one that never ran.
    #
    # XDG_RUNTIME_DIR is set explicitly rather than relying on
    # pam_systemd to furnish it to `su -`; `systemctl --user` needs it
    # to find the resident's manager, and depending on the PAM stack
    # here would make this assertion fail for a reason that has
    # nothing to do with dispatch.
    watermark_props = machine.succeed(
        "su - resident -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user show "
        "castle-dispatch-watermark -p LoadState -p ExecMainStartTimestamp -p Result'"
    )
    assert "LoadState=loaded" in watermark_props, watermark_props
    assert "Result=success" in watermark_props, watermark_props
    started_at = [
        line.split("=", 1)[1]
        for line in watermark_props.splitlines()
        if line.startswith("ExecMainStartTimestamp=")
    ]
    assert started_at and started_at[0].strip(), watermark_props
    print("OK: castle-dispatch-watermark ran at session start and exited success")

    digest_out = machine.succeed("su - resident -c 'castle digest'")
    assert f"Errand {request_id}" in digest_out, digest_out
    assert "${complaintBody}" in digest_out, digest_out
    print("OK: castle digest rendered the errand")

    # --- File a correction through the modal's other path (docs/tasks/
    # 0011 scope item 4, second half) ----------------------------------
    machine.send_key("meta_l-shift-ret")
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

    # --- Answer a question through the modal, with no `castle answer`
    # typed anywhere (docs/tasks/0022-answer-in-ui.md) -----------------
    #
    # A second request, filed exactly the way the first one was, so
    # dispatch starts it on its own and the scripted tenant raises a
    # second question. Two pending questions is the point rather than an
    # accident of sequencing: the picker has to show a list and the
    # resident has to choose out of it, which a run with one pending
    # question could pass without ever proving.
    machine.send_key("meta_l-shift-ret")
    retry(lambda last: has_modal())
    machine.send_chars("${answerComplaintBody}\n.\n")
    machine.sleep(2)
    machine.send_key("ret")  # bare Enter: "something to fix" -> request
    machine.sleep(1)
    machine.send_key("ret")  # dismiss
    retry(lambda last: not has_modal())

    second_request_path = machine.wait_until_succeeds(
        "su - resident -c \"grep -l '${answerComplaintBody}' ${testStateDir}/journal/*-request-*.md\"",
        timeout=dt.timedelta(minutes=5),
    ).strip()
    second_request_id = second_request_path.rsplit("/", 1)[-1][: -len(".md")]

    # Waited for, not assumed: dispatch has to notice the request, take
    # its lease, run the turn and route it before this record exists.
    # The tenant raises exactly one question per turn, so the second
    # question is the one naming the second request.
    second_question_path = machine.wait_until_succeeds(
        "su - resident -c \"grep -l '^refs: " + second_request_id + "$' ${testStateDir}/journal/*-question-*.md\"",
        timeout=dt.timedelta(minutes=5),
    ).strip()
    second_question_id = second_question_path.rsplit("/", 1)[-1][: -len(".md")]
    print(f"OK: a second errand ran itself and raised {second_question_id}")

    # The real chord, on the real Sway session — same naming convention
    # as "meta_l-shift-ret" above (modules/home/default.nix binds
    # Mod4+Shift+a to castle-modal --mode answer).
    machine.send_key("meta_l-shift-a")
    retry(lambda last: has_modal())
    # Waited for on screen, not slept past (review round 1, finding 6).
    # has_modal() only proves the foot window exists, and a fixed sleep
    # can lose the keypress outright: `tty.setcbreak` defaults to
    # TCSAFLUSH, which *discards* anything already queued on the tty, so
    # a digit sent between the window appearing and cbreak being engaged
    # is not merely mistimed — it is thrown away. castle-modal engages
    # cbreak BEFORE it prints the picker, so any picker text being
    # visible is proof the flush has already happened and a keypress can
    # no longer be eaten. Partial match, matching this file's existing
    # OCR style.
    machine.wait_for_text("aiting on you")
    # The one thing no headless test can show a human: what the picker
    # actually looks like on screen.
    machine.screenshot("08-modal-answer-picker")

    # Oldest first, so the first errand's question is [1] and this one
    # is [2]. Pressing 2 is the whole assertion — a resident choosing
    # one question out of several by a number they can see, never by a
    # record id they had to find first.
    machine.send_key("2")
    # The sleeps below stay: once the keypress is read, the tty is
    # restored with TCSADRAIN, which preserves anything queued rather
    # than discarding it — so from here on a small timing miss costs
    # nothing.
    machine.sleep(2)
    machine.send_chars("${answerBody}\n.\n")
    machine.sleep(2)
    machine.screenshot("09-modal-answer-filed")
    machine.send_key("ret")  # dismiss ("Press Enter to close.")
    retry(lambda last: not has_modal())

    answer_path = machine.succeed(
        "su - resident -c 'ls ${testStateDir}/journal/*-answer-*.md'"
    ).strip()
    assert "\n" not in answer_path, f"expected exactly one answer record, got: {answer_path}"
    answer_record = machine.succeed(f"su - resident -c 'cat {answer_path}'")
    # Exactly the question that was picked, and only it: `refs` is the
    # whole claim an answer makes about what it closes.
    assert f"\nrefs: {second_question_id}\n" in answer_record, answer_record
    assert "seat: intake" in answer_record, answer_record
    assert "provenance: requested" in answer_record, answer_record
    assert "${answerBody}" in answer_record, answer_record

    # And the other question is still waiting: nothing names it, which
    # is the whole definition of pending on every surface that reads it.
    answers_naming_first = machine.succeed(
        "su - resident -c \"grep -l '^refs: " + question_id + "$' ${testStateDir}/journal/*-answer-*.md || true\""
    ).strip()
    assert answers_naming_first == "", (
        f"the first errand's question was answered too: {answers_naming_first}"
    )
    print(
        f"OK: the modal filed an answer to {second_question_id} — the question the "
        "resident picked, verbatim, with no record id typed anywhere and the other "
        "question still pending"
    )

    # --- And that answer resumes the errand, cold
    # (docs/tasks/0023-resume-cold.md) -------------------------------
    #
    # The acceptance condition for that task, end to end: the resident
    # answered a blocking question through the real modal, in the real
    # Sway session, and nothing else happened. No `castle work`, no
    # `castle route`, no `castle dispatch` is typed below — the answer
    # record landing in the journal is what wakes the path unit, and the
    # sweep's own eligibility fold is what decides there is a turn to
    # run.
    #
    # Deliberately the LAST journal segment in this script. Three
    # assertions above (`ls`-ing a `*-claim-*.md` / `*-result-*.md` glob
    # and `.strip()`-ing the single line into a path) hold only while
    # this journal has exactly one claim and one result, and a resumed
    # turn adds a second of each. Anything this segment introduces
    # earlier would break them on a multi-line string sliced as a path
    # — a Python exception, not a legible assertion failure.
    answer_id = answer_path.rsplit("/", 1)[-1][: -len(".md")]

    def count_matching(pattern, glob):
        # `|| true` for the empty case, and `grep -c .` rather than
        # `wc -l` so no match counts as 0 rather than 1 blank line.
        return int(
            machine.succeed(
                "su - resident -c \"grep -l '" + pattern + "' "
                + "${testStateDir}/journal/" + glob + " 2>/dev/null | grep -c . || true\""
            ).strip()
        )

    # `retry`'s timeout is a timedelta, not a number of seconds — it
    # compares against an elapsed timedelta internally, and an int here
    # raises a TypeError deep in the driver rather than failing the
    # assertion it was guarding.
    retry(
        lambda last: count_matching("^refs: " + second_request_id, "*-claim-*.md") == 2,
        timeout=dt.timedelta(minutes=5),
    )
    retry(
        lambda last: count_matching("^refs: " + second_request_id + ",", "*-result-*.md") == 2,
        timeout=dt.timedelta(minutes=5),
    )
    print(f"OK: answering {second_question_id} started a second worker turn on {second_request_id}")

    # The claim is the receipt: the answer named in its own refs, after
    # the request id, is what spends it — and is why no later sweep
    # resumes this errand a third time.
    resumed_claim_path = machine.succeed(
        "su - resident -c \"grep -l '^refs: " + second_request_id + "," + answer_id
        + "$' ${testStateDir}/journal/*-claim-*.md\""
    ).strip()
    assert "\n" not in resumed_claim_path, resumed_claim_path
    resumed_claim_id = resumed_claim_path.rsplit("/", 1)[-1][: -len(".md")]

    resumed_result_path = machine.succeed(
        "su - resident -c \"grep -l '^refs: " + second_request_id + "," + resumed_claim_id
        + "$' ${testStateDir}/journal/*-result-*.md\""
    ).strip()
    resumed_result = machine.succeed(f"su - resident -c 'cat {resumed_result_path}'")
    assert "outcome: completed" in resumed_result, resumed_result
    # Both halves of what a resumed tenant is handed, reported by the
    # tenant itself: the environment variable that says this is a
    # resumption, and the resident's own words arriving on stdin in a
    # process that has never seen the turn that asked the question.
    assert f"resumed with {answer_id}" in resumed_result, resumed_result
    assert "the packet carried the resident's answer" in resumed_result, resumed_result
    print(
        f"OK: the resumed turn ran cold — {resumed_claim_id} spent {answer_id}, and the "
        "fresh tenant received the resident's answer on its stdin with no warm session "
        "anywhere"
    )

    # Exactly two questions in this whole run: one per first turn, and
    # none from the resumed one. A third would mean this segment left
    # the journal holding a question nobody answered at the moment the
    # test declares success.
    question_count = int(
        machine.succeed(
            "su - resident -c 'ls ${testStateDir}/journal/*-question-*.md | wc -l'"
        ).strip()
    )
    assert question_count == 2, f"expected exactly 2 questions, found {question_count}"

    # And the resumed result is routed like any other — waited for, not
    # assumed, since check_assertions.py below requires it.
    resumed_result_id = resumed_result_path.rsplit("/", 1)[-1][: -len(".md")]
    machine.wait_until_succeeds(
        "su - resident -c \"grep -l '^refs: " + resumed_result_id
        + "$' ${testStateDir}/journal/*-decision-*.md\"",
        timeout=dt.timedelta(minutes=5),
    )
    print("OK: the resumed turn's result was routed like a first turn's, by the same sweep")

    # --- The notify channel, checked for silence rather than for a
    # popup. `castle route` deliberately never lets a failed
    # notification break routing — it warns on stderr and carries on —
    # so the only evidence that the resident was actually told lives in
    # the log the dispatch unit writes to. This assertion is here
    # because the first run of this test found the warning: a systemd
    # user manager's PATH has no `notify-send` in it, and every
    # notification an auto-dispatched errand fired was being dropped
    # into a non-fatal message nobody would ever read. Honest limit:
    # this proves the notify command ran without complaint, not that a
    # human saw a popup — mako cannot report reception, which is
    # docs/architecture.md's Proposal 06 receipt half, still unbuilt.
    # Scoped to the dispatch unit's own log, not the whole system
    # journal: a match anywhere else would be a different process's
    # problem, and — the reason this is a `succeed` plus an `assert`
    # rather than a `fail` on a grep — a mistyped journalctl filter
    # exits nonzero all by itself, which would turn this into an
    # assertion that passes because it checked nothing. The first
    # assertion below is what keeps that honest: the unit's log has to
    # contain the sweep's own report of the turn it ran, so we know we
    # are reading a log that exists and belongs to the right unit.
    dispatch_log = machine.succeed(
        "journalctl --no-pager _SYSTEMD_USER_UNIT=castle-dispatch.service"
    )
    assert "dispatch: worked" in dispatch_log, dispatch_log
    # `castle route:` rather than `notify command`: _fire_notification
    # has two failure warnings — an unparseable CASTLE_NOTIFY_COMMAND
    # and a notify command that could not be run — and only the second
    # says "notify command". Both are prefixed "castle route:", and the
    # router's ordinary reports are not: they print "route: ..." and
    # the sweep prints "dispatch: ..." (agent/castle's cmd_route and
    # cmd_dispatch — checked, not assumed). So this one substring
    # covers both warnings without matching healthy output.
    assert "castle route:" not in dispatch_log, dispatch_log
    print("OK: the router's notify channel fired with no fallback warning")

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

    print("PASS: the ambient-intake loop ran end to end in a real Sway session driven by keystrokes alone — the errand started itself, and an answered blocking question continued it.")
  '';
}
