# Nix Status

A Noctalia bar widget for NixOS, standing in for arch-updater. NixOS has no
pending updates to count: versions are pinned in the system flake's
`flake.lock` and only move with `nix flake update`. So the widget shows:

- the **nixpkgs pin's age** in days (the text),
- whether a **reboot** is needed: the kernel, initrd or kernel modules
  (NVIDIA's among them) differ between `/run/booted-system` and
  `/run/current-system`,
- whether a **switch is pending**: the running system's `nixos-version`
  names a different nixpkgs revision than `flake.lock`,
- whether `flake.lock` has **uncommitted** changes,
- every input's pinned date and revision (tooltip).

Glyph color: `error` if the check failed, `warning` for reboot or pending
switch, `primary` once the nixpkgs pin is 14 days old, `on_surface`
otherwise.

**Left click** opens a terminal running `nh os switch --update` on the
flake; **right click** re-checks. It also re-checks every minute; all of it
is local (no network), so a check takes milliseconds.

The flake path (`$HOME/src/nixos`) and the 14-day threshold are constants at
the top of `service.luau`.

## Install

As a local drop-in:

```sh
ln -s ~/src/noctalia-nix ~/.local/share/noctalia/plugins/nix-status
noctalia msg plugins enable filedesless/nix-status
```

Then add a widget of type `filedesless/nix-status:widget` to a bar.
