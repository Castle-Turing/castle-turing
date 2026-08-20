# The secrets slot: where a private layer says *which* encrypted file
# holds its credentials, and *where on this machine* the key that
# decrypts them lives (docs/tasks/0031-secrets-tooling.md).
#
# This module is deliberately thin. The mechanism is sops-nix's own —
# `sops.secrets.*`, `sops.templates.*`, and the activation-time
# `sops-install-secrets` run that writes plaintext to /run and nowhere
# else; flake.nix's `nixosModules.secrets` binds that module alongside
# this one so a private layer needs neither the input nor the import.
# What this file adds is the two-option interface Principle 01 asks for:
# public mechanism here, private configuration (the ciphertext, the key,
# and the actual secret) in the resident's own repo.
#
# Nothing here requires a secret to exist. A configuration that imports
# this module and declares nothing evaluates, which is what lets
# `nixosConfigurations.example` prove the slot against a dummy resident
# (Principle 02 consequence 2).
{ config, lib, ... }:
let
  cfg = config.castle.secrets;
in
{
  options.castle.secrets = {
    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./secrets.yaml";
      description = ''
        The private layer's encrypted secrets file. Wired to
        `sops.defaultSopsFile`.

        A Nix *path*, not a string, deliberately: evaluating this
        configuration copies the file into the world-readable Nix
        store, and for this file that is the intended distribution
        mechanism rather than a leak, because it is ciphertext.
        Contrast `docs/private-layer.md`'s warning under "The agent's
        state" about *plaintext* state landing in the store the same
        way (`docs/tasks/0030-state-outside-the-flake.md`) — that
        hazard is about plaintext, and this file is not plaintext.

        What must never be copied anywhere an evaluation can reach is
        the key that decrypts it — see `ageKeyFile`.

        Supplied by the private layer; see `docs/private-layer.md`.
      '';
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sops-nix/key.txt";
      description = ''
        Where the age private key that decrypts `sopsFile` lives on
        this machine — never in either repo. Wired to
        `sops.age.keyFile`.

        The default is the path this project's own enrollment steps
        plant the key at with `nixos-anywhere --extra-files` (see
        `docs/private-layer.md`); override it only with a specific
        reason to use a different one, since the install-time staging
        and this option have to agree or the first activation fails
        with a missing-key error.
      '';
    };
  };

  config = lib.mkMerge [
    # Gated, because sops.defaultSopsFile is `types.path` with no
    # default of its own upstream: leaving it undefined is what lets a
    # resident import this module before they have any secrets. Nothing
    # in sops-nix reads it until a `sops.secrets.<name>` without its own
    # sopsFile override exists.
    (lib.mkIf (cfg.sopsFile != null) { sops.defaultSopsFile = cfg.sopsFile; })

    {
      # Unconditional, unlike the gated defaultSopsFile above: declaring
      # a path nothing yet consumes costs nothing, and it means the
      # enrollment path always targets the same documented location
      # whether or not a resident has declared any secrets yet.
      #
      # mkDefault for the same reason as the two lines below, and it was
      # a bare definition until review asked why this one line was
      # rigid. A private layer that follows sops-nix's own documentation
      # and writes `sops.age.keyFile = "/persist/sops/key.txt"` directly
      # should simply win. Bare, it did not: two definitions of a
      # non-mergeable option collide on mergeEqualOption, and the error
      # a resident gets talks about conflicting definitions without ever
      # naming castle.secrets.ageKeyFile as the way out. This module's
      # premise is that the resident keeps the whole upstream surface,
      # so the framework states preferences at a priority their own
      # definitions beat.
      sops.age.keyFile = lib.mkDefault cfg.ageKeyFile;

      # The machine's SSH host keys are NOT decryption identities here,
      # in either of the two forms sops-nix derives one.
      #
      # Upstream gives `sops.age.sshKeyPaths` the host's *ed25519* keys
      # as its default and `sops.gnupg.sshKeyPaths` the host's *RSA*
      # keys, sixteen lines apart in the same file, and
      # `sops-install-secrets` imports each into a keyring it decrypts
      # with. So setting `age.keyFile` keeps neither of them out —
      # which is what docs/tasks/0031 originally assumed, and what two
      # successive passes over this module each half-corrected: the
      # first closed only the age half, and the review that verified it
      # read past the gnupg sibling in its own grep output.
      #
      # Left in place, either one lets a resident encrypt a secret to
      # an identity the machine will not have after a wipe — add the
      # host key's PGP fingerprint to .sops.yaml, the common recipe,
      # and everything works until the reinstall that makes it
      # permanently unreadable. That is precisely the re-enrollment
      # puzzle the planted age key exists to avoid, so both lists are
      # emptied, not one.
      #
      # mkDefault, not a bare definition, so a resident who actually
      # wants ssh-derived identities can still say so. Emptying the
      # gnupg list has a second, smaller benefit: upstream requires it
      # to be explicitly unset before `sops.gnupg.home` may be set at
      # all, so this clears that footgun too.
      #
      # Nothing else on this module's surface carries a decryption
      # identity by default — checked rather than assumed:
      # age.generateKey is false, age.plugins is empty, and gnupg.home
      # is null on a configuration importing this module.
      sops.age.sshKeyPaths = lib.mkDefault [ ];
      sops.gnupg.sshKeyPaths = lib.mkDefault [ ];
    }
  ];
}
