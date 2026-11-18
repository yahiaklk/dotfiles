# dotfiles

Personal dev environment for Ubuntu/Debian (bare-metal or WSL). No credentials are stored in this repo.

## Install

```bash
git clone https://github.com/yahiaklk/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh            # checklist: pick what this machine gets
```

Not every machine needs everything, so `install.sh` installs **components** you choose:

```bash
./install.sh dev                 # a preset
./install.sh minimal k8s         # presets and components mix
./install.sh zsh git nvim        # just these (plus core and dependencies)
./install.sh --all               # everything
./install.sh --list              # components, presets, dependencies
./install.sh --dry-run dev       # print every command and link, change nothing
./install.sh --upgrade nvim helm # reinstall at the latest release
./install.sh --check-updates     # what has a newer release
```

With no arguments it opens a checklist, pre-ticked with what this machine has
(`~/.config/dotfiles/selection`). Named runs add to that list (`./install.sh k8s`
later keeps everything installed before); the checklist replaces it, so untick an
item there to drop it. `core` is always included and dependencies are
added automatically (`nvim` needs `node`, `git-hooks` needs `git`). Each component
is idempotent: reruns skip what's already in place, and anything a link would
replace is moved to `~/.dotfiles-backup/<timestamp>/`. The script refuses to run
as root; it calls `sudo` itself for apt.

### Presets

| Preset | Components |
|--------|-----------|
| `minimal` | git zsh vim tmux update-check |
| `dev` | minimal + node nvim uv direnv ssh claude |
| `k8s` | kubectl k9s helm |
| `full` | every component |

### Components

| Component | Installs / links |
|-----------|------------------|
| `core` | apt: curl git unzip gnupg ca-certificates python3 whiptail; `~/.local/bin` |
| `git` | `.gitconfig`, `.gitignore_global`; apt `gh` (the credential helper) |
| `git-hooks` | Conventional Commits and branch-name hooks for repos under `~/projects/` (off unless picked) |
| `zsh` | zsh, fzf, zsh-autosuggestions, zsh-syntax-highlighting, starship (+ `starship.toml`), zoxide, `.zshrc`, default shell |
| `vim` | `.vimrc` (minimal, CKA-exam compatible) |
| `tmux` | tmux, `.tmux.conf` (prefix `Ctrl+a`, vi mode, catppuccin colours) |
| `node` | nvm and the current Node LTS (Mason needs npm) |
| `nvim` | Neovim's official release build in `~/.local/opt` (the apt one is too old for this config), ripgrep, build-essential, `nvim/`, plugin sync |
| `uv` | uv |
| `direnv` | direnv, `~/.config/direnv/direnvrc` (`layout_uv`, `layout_node`) |
| `ssh` | `~/.ssh/config`: keepalives, plus `Include ~/.ssh/config.local` |
| `1password` | 1Password CLI (`op`) from 1Password's apt repo. Optional: pick it only on machines that should reach the vault |
| `kubectl` | latest stable kubectl in `~/.local/bin`, checked against its sha256 |
| `k9s` | latest k9s release in `~/.local/bin`, checked against GitHub's sha256 |
| `helm` | Helm 4 in `~/.local/bin` (official script, verifies its own checksum) |
| `terraform` | `.terraformrc` and its plugin cache (not terraform itself) |
| `gestures` | libinput-gestures config (touchpad laptops; the tool itself isn't installed) |
| `claude` | checks that the npm-installed Claude Code has its native binary |
| `update-check` | weekly systemd user timer running `--check-updates` |

`.zshrc` loads every optional tool only when it's present, so any subset of components gives a shell without errors.

## Updates

`./install.sh --check-updates` compares the installed version of each tool not managed by apt (nvim, starship, zoxide, uv,
nvm, node, kubectl, k9s, helm) with its latest release, and marks **MAJOR** jumps (first number changed; for 0.x
versions, the second). The `update-check` component runs it weekly through a systemd user timer
(`systemctl --user list-timers dotfiles-update-check.timer`). When something is outdated, new shells print one line
about it. apt packages, including `gh` and `op`, are updated by `apt upgrade`.

## Per-machine settings

Two files are read if they exist and are never tracked here:

- `~/.zshrc.local`: sourced at the end of `.zshrc`
- `~/.ssh/config.local`: included at the top of `~/.ssh/config`, so its settings win

For example, a machine that uses the 1Password SSH agent puts `export SSH_AUTH_SOCK=~/.1password/agent.sock` in
`~/.zshrc.local` and this in `~/.ssh/config.local`:

```
Host *
    IdentityAgent "~/.1password/agent.sock"
```

Likewise `~/.gitconfig.local` is included by `.gitconfig` (e.g. to turn commit signing back on for one machine).
Commit signing is off by default.

## Testing

Run the installer against a scratch `HOME`, with fake `sudo`, `apt-get`, `curl`, `chsh` and friends first on `PATH`. Never
run it for real against your own `HOME` except with `--dry-run`.

`.gitignore` blocks `**/.ssh/`, `**/.aws/credentials`, `**/.kube/config`, `*.pem` and `*.key` as a safety net.
