# Nix Status

A Noctalia bar widget for NixOS, standing in for arch-updater. NixOS has no
pending updates to count: versions are pinned in the system flake's
`flake.lock` and only move with `nix flake update`. So the widget shows:

- the **nixpkgs pin's age** in days (the text), and the newest commit on
  its branch on GitHub (checked hourly),
- whether a **reboot** is needed: the kernel, initrd or kernel modules
  (NVIDIA's among them) differ between `/run/booted-system` and
  `/run/current-system`,
- whether a **switch is pending**: the files git tracks in the repo,
  uncommitted edits included, differ from `/etc/nixos/flake`, the source
  the system was built from (see below; Markdown files don't count);
  failing that, the repo's `flake.lock` differs from
  `/etc/nixos/flake.lock`; failing that, the running system's
  `nixos-version` names a different nixpkgs revision than `flake.lock`,
- whether a **test is still live**: `/run/current-system` isn't the boot
  default (`/nix/var/nix/profiles/system`), e.g. after `nixos-rebuild test`,
- whether the flake has **uncommitted** changes (staged or not),
- every input's pinned date and revision (tooltip).

Bar: a snowflake (red if the check failed), then a glyph per flag, always
in place, lit when set and dimmed when not: power (reboot), flask (test),
refresh-alert (switch), git-commit (uncommitted changes), download
(newer nixpkgs on GitHub). Hovering one says what it means; the text is the
nixpkgs pin's age.

**Left click** opens a floating panel with the pinned and latest nixpkgs
revisions side by side, what needs doing (reboot, switch, commit, update)
or a line saying nothing does, every input's pin, and a row of buttons: a
**Check** icon, then up to three more. **Switch** shows when a switch is pending
or a test is live: it makes the system match the repo for good, whatever was
being tested. **Back** shows while a test is live and re-activates the boot
default. **Update** is always there. Switch and Update
run `nh os switch [--update]` on the flake in `$TERMINAL`; every button
command ends with `noctalia msg plugin filedesless/nix-status:service all
check`, so the widget updates as soon as it finishes. **Right click**
re-checks. Local checks run every minute and cost milliseconds; the GitHub
one (one API request) runs hourly, well under the unauthenticated limit.

There are no Optimize or Clean buttons on purpose: on a system with
`nix.settings.auto-optimise-store` and `nix.gc.automatic` both already
happen on their own.

The flake path (`$HOME/src/nixos`) and the 14-day threshold are constants at
the top of `service.luau`.

## Install

As a local drop-in:

```sh
ln -s ~/src/noctalia-nix ~/.local/share/noctalia/plugins/nix-status
noctalia msg plugins enable filedesless/nix-status
```

Then add a widget of type `filedesless/nix-status:widget` to a bar.

## Telling when a switch is pending

`nix flake update` only rewrites `flake.lock`, and an edited `.nix` file
does nothing either until the next switch. To see any change, have the
system keep the flake source it was built from, and its commit (shown in
the panel and `nixos-version --json`, `-dirty` for a build from
uncommitted edits), in a module that gets the flake's `inputs`:

```nix
environment.etc."nixos/flake".source = inputs.self.outPath;
system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
```

The widget compares that tree with the files git tracks, as a git flake
only sees those: an untracked file doesn't count until it's `git add`ed.
Keeping just the lock (`environment.etc."nixos/flake.lock".source =
./flake.lock;`) still works, but only notices inputs moving.
