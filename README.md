# dotfiles

## Setup

```sh
git clone git@github.com:gakutasu/dotfiles.git ~/dotfiles
sh ~/dotfiles/setup.sh
```

`setup.sh` symlinks the dotfiles into `$HOME` (existing files are kept as
`*.backup.<timestamp>`), links systemd user units, and runs the modules below.

## Modules

Standalone, re-runnable setup scripts under `modules/`. Each can also be run
on its own, e.g. `sh ~/dotfiles/modules/japanese.sh`.

- `modules/japanese.sh`: Japanese input with ibus + Mozc on GNOME, for both
  Wayland and X11. The jp keyboard layout is declared in
  `.config/mozc/ibus_config.textproto` instead of `setxkbmap`, which never
  reaches native Wayland clients (Zenkaku/Hankaku did not toggle the IME).
