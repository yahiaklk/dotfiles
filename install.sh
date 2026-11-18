#!/usr/bin/env bash
# Set up an Ubuntu/Debian machine (WSL or bare-metal) from this repo, one
# component at a time. Run `./install.sh --help` for usage.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECTION_FILE="$HOME/.config/dotfiles/selection"
UPDATES_FILE="$HOME/.cache/dotfiles/updates"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
NVIM_MIN="0.11"   # nvim/ uses vim.lsp.config(), new in 0.11
export PATH="$HOME/.local/bin:$PATH"

DRY_RUN=0
UPGRADE=0
REPLACE_SELECTION=0   # 1 when the checklist chose the components
TMP=""

# ---------------------------------------------------------------------------
# Components (listed in install order), dependencies and presets
# ---------------------------------------------------------------------------
COMPONENTS=(core git git-hooks zsh vim tmux node nvim uv direnv ssh 1password
            kubectl k9s helm terraform gestures claude update-check)

declare -A DESC=(
  [core]="base apt packages, ~/.local/bin (always included)"
  [git]="gitconfig, global gitignore, gh (credential helper)"
  [git-hooks]="Conventional Commits hooks for repos under ~/projects"
  [zsh]="zsh, plugins, starship, zoxide, fzf, default shell"
  [vim]="minimal .vimrc (servers, exams)"
  [tmux]="tmux and .tmux.conf"
  [node]="nvm and the current Node LTS"
  [nvim]="Neovim release build in ~/.local, config, plugins"
  [uv]="uv (Python)"
  [direnv]="direnv and direnvrc (layout_uv, layout_node)"
  [ssh]="ssh client config (keepalives; per-machine config.local)"
  [1password]="1Password CLI (op): optional, vault access"
  [kubectl]="kubectl, latest stable, checksum-verified"
  [k9s]="k9s, latest release, checksum-verified"
  [helm]="Helm, latest release"
  [terraform]=".terraformrc and its plugin cache"
  [gestures]="libinput-gestures config (touchpad laptops)"
  [claude]="check the Claude Code native binary"
  [update-check]="weekly check for new versions of these tools"
)

# Hard dependencies, added automatically.
declare -A DEPS=(
  [git-hooks]="git"
  [nvim]="node"   # Mason installs pyright, yamlls and bashls with npm
)

declare -A PRESETS=(
  [minimal]="git zsh vim tmux update-check"
  [dev]="minimal node nvim uv direnv ssh claude"
  [k8s]="kubectl k9s helm"
  [full]="${COMPONENTS[*]}"
)
PRESET_ORDER=(minimal dev k8s full)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$1" >&2; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# run CMD [ARGS...]: run a command, or only print it under --dry-run.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run]'; printf ' %q' "$@"; printf '\n'
    return 0
  fi
  "$@"
}

# run_sh 'PIPELINE': the same, for a shell pipeline.
run_sh() {
  if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] %s\n' "$1"; return 0; fi
  bash -c "$1"
}

# write_file PATH CONTENT
write_file() {
  if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] write %s\n' "$1"; return 0; fi
  printf '%s\n' "$2" >"$1"
  echo "wrote  $1"
}

# True when TOOL should be (re)installed: missing, or --upgrade given.
need_install() { [ "$UPGRADE" = 1 ] || ! have "$1"; }

# version_ge A B: true when version A >= version B.
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# Architecture names: GOARCH style (kubectl, k9s) and uname style (nvim).
arch_go()   { case "$(uname -m)" in x86_64) echo amd64 ;; aarch64|arm64) echo arm64 ;; *) uname -m ;; esac; }
arch_nvim() { case "$(uname -m)" in x86_64) echo x86_64 ;; aarch64|arm64) echo arm64 ;; *) uname -m ;; esac; }

link() {
  local src="$1" dst="$2" bk
  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
    echo "ok     $dst"
    return 0
  fi
  run mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    bk="$BACKUP_DIR/${dst#"$HOME"/}"
    run mkdir -p "$(dirname "$bk")"
    run mv "$dst" "$bk"
    warn "backed up $dst -> $bk"
  fi
  run ln -s "$src" "$dst"
  [ "$DRY_RUN" = 1 ] || echo "linked $dst -> $src"
}

apt_install() {
  local missing=() p
  for p in "$@"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
  done
  if [ ${#missing[@]} -eq 0 ]; then echo "ok     apt: $*"; return 0; fi
  if [ ! -e "$TMP/apt-updated" ]; then
    run sudo apt-get update
    touch "$TMP/apt-updated"
  fi
  run sudo apt-get install -y "${missing[@]}"
}

fetch() { run curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"; }

verify_sha256() {
  if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] verify sha256 of %s\n' "$1"; return 0; fi
  local got
  got="$(sha256sum "$1" | cut -d' ' -f1)"
  if [ -z "$2" ] || [ "$got" != "$2" ]; then
    warn "checksum mismatch for $(basename "$1"): expected '${2}', got '$got'"
    return 1
  fi
  echo "ok     sha256 $(basename "$1")"
}

gh_release() { curl -fsSL "https://api.github.com/repos/$1/releases/latest"; }

# Read the tag (no ASSET) or one asset's sha256 digest from a release JSON on stdin.
release_field() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
if len(sys.argv) == 1:
    print(d["tag_name"])
else:
    for a in d.get("assets", []):
        if a["name"] == sys.argv[1] and (a.get("digest") or "").startswith("sha256:"):
            print(a["digest"].split(":", 1)[1])
' "$@"
}

# gh_download REPO ASSET DEST: download ASSET from REPO's latest GitHub release
# and check it against the sha256 digest GitHub publishes for that asset.
gh_download() {
  local json tag sha
  if ! json="$(gh_release "$1")"; then
    if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] download latest %s from %s\n' "$2" "$1"; return 0; fi
    warn "cannot reach the GitHub API for $1"
    return 1
  fi
  tag="$(release_field <<<"$json")"
  sha="$(release_field "$2" <<<"$json")"
  echo "       $1 $tag"
  fetch "https://github.com/$1/releases/download/$tag/$2" "$3"
  verify_sha256 "$3" "$sha"
}

load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] || return 1
  set +eu
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
}

# ---------------------------------------------------------------------------
# Components: c_<name>, with "-" turned into "_". Each one runs in a subshell
# with `set -e`, so a failure stops that component and the next one runs.
# ---------------------------------------------------------------------------
c_core() {
  apt_install curl git unzip gnupg ca-certificates python3 whiptail
  run mkdir -p "$HOME/.local/bin"
}

c_git() {
  apt_install gh
  link "$DOTFILES_DIR/git/.gitconfig"        "$HOME/.gitconfig"
  link "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
}

c_git_hooks() {
  link "$DOTFILES_DIR/git/hooks"             "$HOME/.config/git/hooks"
  link "$DOTFILES_DIR/git/projects.gitconfig" "$HOME/.config/git/projects.gitconfig"
}

c_zsh() {
  apt_install zsh fzf
  run mkdir -p "$HOME/.zsh"
  local p zsh_path current
  for p in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ -d "$HOME/.zsh/$p" ]; then echo "ok     ~/.zsh/$p"
    else run git clone --depth 1 "https://github.com/zsh-users/$p" "$HOME/.zsh/$p"; fi
  done
  if need_install starship; then
    fetch https://starship.rs/install.sh "$TMP/starship.sh"
    run sh "$TMP/starship.sh" --yes --bin-dir "$HOME/.local/bin"
  else echo "ok     starship"; fi
  if need_install zoxide; then
    fetch https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh "$TMP/zoxide.sh"
    run sh "$TMP/zoxide.sh" --bin-dir "$HOME/.local/bin"
  else echo "ok     zoxide"; fi
  link "$DOTFILES_DIR/zsh/.zshrc"                     "$HOME/.zshrc"
  link "$DOTFILES_DIR/starship/.config/starship.toml" "$HOME/.config/starship.toml"

  zsh_path="$(command -v zsh || echo /usr/bin/zsh)"
  current="$(getent passwd "$(id -un)" | cut -d: -f7)"
  if [ "$current" != "$zsh_path" ]; then
    run chsh -s "$zsh_path" || warn "could not change the default shell: run chsh -s $zsh_path"
  else echo "ok     default shell is zsh"; fi
}

c_vim()  { link "$DOTFILES_DIR/vim/.vimrc" "$HOME/.vimrc"; }

c_tmux() {
  apt_install tmux
  link "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
}

c_node() {
  export NVM_DIR="$HOME/.nvm"
  if [ "$UPGRADE" = 1 ] || [ ! -s "$NVM_DIR/nvm.sh" ]; then
    local tag
    tag="$(gh_release nvm-sh/nvm | release_field)" || tag=""
    if [ -z "$tag" ] && [ "$DRY_RUN" = 0 ]; then warn "cannot find the latest nvm release"; return 1; fi
    run mkdir -p "$NVM_DIR"
    fetch "https://raw.githubusercontent.com/nvm-sh/nvm/${tag:-<latest>}/install.sh" "$TMP/nvm-install.sh"
    # PROFILE=/dev/null: the installer must not append to ~/.zshrc, which is a
    # link into this repo. .zshrc already loads nvm.
    run env PROFILE=/dev/null NVM_DIR="$NVM_DIR" bash "$TMP/nvm-install.sh"
  else echo "ok     nvm"; fi
  if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] nvm install --lts && nvm alias default lts/*"; return 0; fi
  load_nvm || { warn "nvm.sh not found in $NVM_DIR after install"; return 1; }
  nvm install --lts && nvm alias default 'lts/*'
}

nvim_ok() {
  have nvim || return 1
  version_ge "$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" "$NVIM_MIN"
}

c_nvim() {
  apt_install ripgrep build-essential   # telescope live_grep; treesitter parsers
  if [ "$UPGRADE" = 1 ] || ! nvim_ok; then
    local a f
    a="$(arch_nvim)"; f="nvim-linux-$a.tar.gz"
    gh_download neovim/neovim "$f" "$TMP/$f"
    run mkdir -p "$HOME/.local/opt"
    run rm -rf "$HOME/.local/opt/nvim-linux-$a"
    run tar -xzf "$TMP/$f" -C "$HOME/.local/opt"
    run ln -sfn "$HOME/.local/opt/nvim-linux-$a/bin/nvim" "$HOME/.local/bin/nvim"
  else echo "ok     nvim $(nvim --version | head -1)"; fi
  link "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
  run nvim --headless "+Lazy! sync" +qa
}

c_uv() {
  if ! have uv; then
    fetch https://astral.sh/uv/install.sh "$TMP/uv.sh"
    run env UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$TMP/uv.sh"
  elif [ "$UPGRADE" = 1 ]; then
    run uv self update
  else echo "ok     uv"; fi
}

c_direnv() {
  apt_install direnv
  link "$DOTFILES_DIR/direnv/direnvrc" "$HOME/.config/direnv/direnvrc"
}

c_ssh() {
  run mkdir -p "$HOME/.ssh"
  run chmod 700 "$HOME/.ssh"
  link "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config"
  # ssh refuses a config that others can write; chmod follows the link.
  run chmod 600 "$HOME/.ssh/config"
  if [ ! -e "$HOME/.ssh/config.local" ]; then
    echo "       per-machine settings (e.g. an agent socket) go in ~/.ssh/config.local"
  fi
}

c_1password() {
  if need_install op; then
    local arch kr=/usr/share/keyrings/1password-archive-keyring.gpg pol=AC2D62742012EA22
    arch="$(dpkg --print-architecture)"
    fetch https://downloads.1password.com/linux/keys/1password.asc "$TMP/1password.asc"
    fetch https://downloads.1password.com/linux/debian/debsig/1password.pol "$TMP/1password.pol"
    run sudo gpg --batch --yes --dearmor --output "$kr" "$TMP/1password.asc"
    run_sh "echo 'deb [arch=$arch signed-by=$kr] https://downloads.1password.com/linux/debian/$arch stable main' | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null"
    run sudo mkdir -p "/etc/debsig/policies/$pol" "/usr/share/debsig/keyrings/$pol"
    run sudo install -m 644 "$TMP/1password.pol" "/etc/debsig/policies/$pol/1password.pol"
    run sudo gpg --batch --yes --dearmor --output "/usr/share/debsig/keyrings/$pol/debsig.gpg" "$TMP/1password.asc"
    rm -f "$TMP/apt-updated"   # the new repo needs an apt-get update
    apt_install 1password-cli
  else echo "ok     op"; fi
  warn "Sign in to op (op signin) only on machines that should reach your vault."
}

c_kubectl() {
  if need_install kubectl; then
    local v a base
    a="$(arch_go)"
    v="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" || v=""
    if [ -z "$v" ] && [ "$DRY_RUN" = 0 ]; then warn "cannot read the latest kubectl version"; return 1; fi
    base="https://dl.k8s.io/release/${v:-<stable>}/bin/linux/$a"
    echo "       kubectl ${v:-<stable>}"
    fetch "$base/kubectl" "$TMP/kubectl"
    fetch "$base/kubectl.sha256" "$TMP/kubectl.sha256"
    verify_sha256 "$TMP/kubectl" "$(cat "$TMP/kubectl.sha256" 2>/dev/null)"
    run install -m 755 "$TMP/kubectl" "$HOME/.local/bin/kubectl"
  else echo "ok     kubectl"; fi
}

c_k9s() {
  if need_install k9s; then
    local f
    f="k9s_Linux_$(arch_go).tar.gz"
    gh_download derailed/k9s "$f" "$TMP/$f"
    run tar -xzf "$TMP/$f" -C "$TMP" k9s
    run install -m 755 "$TMP/k9s" "$HOME/.local/bin/k9s"
  else echo "ok     k9s"; fi
}

c_helm() {
  if need_install helm; then
    # The official script verifies the release checksum itself.
    fetch https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 "$TMP/get-helm.sh"
    run env HELM_INSTALL_DIR="$HOME/.local/bin" USE_SUDO=false bash "$TMP/get-helm.sh"
  else echo "ok     helm"; fi
}

c_terraform() {
  link "$DOTFILES_DIR/terraform/.terraformrc" "$HOME/.terraformrc"
  run mkdir -p "$HOME/.terraform.d/plugin-cache"
  have terraform || echo "       terraform itself is not installed by this script"
}

c_gestures() {
  link "$DOTFILES_DIR/libinput-gestures/.config/libinput-gestures.conf" "$HOME/.config/libinput-gestures.conf"
  have libinput-gestures || echo "       needs libinput-gestures and xdotool, not installed by this script"
}

c_claude() {
  if [ -n "${CLAUDECODE:-}" ]; then
    warn "running inside a Claude Code session: skipping the claude-code check"
    warn "(reinstalling the package a running session executes from can crash it)"
    return 0
  fi
  if ! have npm; then echo "       npm not found: skipping the claude-code check"; return 0; fi
  local bin size
  bin="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/bin/claude.exe"
  if [ ! -f "$bin" ]; then echo "       claude-code not installed via npm: skipping"; return 0; fi
  # The postinstall placeholder is a ~500-byte script; the native binary is
  # tens of MB. A stub means the optional platform package failed to download
  # (npm doesn't fail the install for a failed optional dependency).
  size=$(stat -c%s "$bin" 2>/dev/null || echo 0)
  if [ "$size" -ge 100000 ]; then echo "ok     claude-code native binary (${size} bytes)"; return 0; fi
  warn "claude-code native binary missing (${size}-byte stub): reinstalling"
  run npm uninstall -g @anthropic-ai/claude-code
  run npm cache clean --force
  run npm install -g @anthropic-ai/claude-code@latest
  [ "$DRY_RUN" = 1 ] && return 0
  size=$(stat -c%s "$bin" 2>/dev/null || echo 0)
  if [ "$size" -lt 100000 ]; then
    warn "still a stub after reinstall: likely a network/TLS issue fetching the platform package. Try:"
    warn "npm install -g @anthropic-ai/claude-code-linux-x64@\$(npm view @anthropic-ai/claude-code version)"
    return 1
  fi
  echo "ok     claude-code native binary (${size} bytes)"
}

c_update_check() {
  local dir="$HOME/.config/systemd/user"
  run mkdir -p "$dir"
  write_file "$dir/dotfiles-update-check.service" "[Unit]
Description=Check the tools installed by ~/dotfiles for new releases

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash \"$DOTFILES_DIR/install.sh\" --check-updates"
  write_file "$dir/dotfiles-update-check.timer" "[Unit]
Description=Weekly check for new releases of the tools installed by ~/dotfiles

[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target"
  if have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    run systemctl --user daemon-reload
    run systemctl --user enable --now dotfiles-update-check.timer
  else
    warn "no systemd user session (WSL without systemd?): the weekly timer is not active."
    warn "Run ./install.sh --check-updates by hand, or enable systemd in /etc/wsl.conf."
  fi
}

# ---------------------------------------------------------------------------
# --check-updates: compare installed versions with the latest releases.
# apt packages are left to `apt upgrade`; op comes from 1Password's apt repo.
# ---------------------------------------------------------------------------
UPDATE_TOOLS=(nvim starship zoxide uv nvm node kubectl k9s helm)
# The component that (re)installs each tool.
declare -A TOOL_COMPONENT=([nvim]=nvim [starship]=zsh [zoxide]=zsh [uv]=uv [nvm]=node [node]=node
                           [kubectl]=kubectl [k9s]=k9s [helm]=helm)

semver() { grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }

installed_version() {
  case "$1" in
    nvim)     have nvim && nvim --version | head -1 ;;
    starship) have starship && starship --version | head -1 ;;
    zoxide)   have zoxide && zoxide --version ;;
    uv)       have uv && uv --version ;;
    nvm)      ( load_nvm && nvm --version ) ;;
    node)     ( load_nvm >/dev/null 2>&1; have node && node --version ) ;;
    kubectl)  have kubectl && kubectl version --client 2>/dev/null | head -1 ;;
    k9s)      have k9s && k9s version --short 2>/dev/null | head -1 ;;
    helm)     have helm && helm version --short ;;
  esac 2>/dev/null | semver
}

latest_version() {
  case "$1" in
    nvim)     gh_release neovim/neovim | release_field ;;
    starship) gh_release starship/starship | release_field ;;
    zoxide)   gh_release ajeetdsouza/zoxide | release_field ;;
    uv)       gh_release astral-sh/uv | release_field ;;
    nvm)      gh_release nvm-sh/nvm | release_field ;;
    node)     curl -fsSL https://nodejs.org/dist/index.tab | awk -F'\t' 'NR > 1 && $10 != "-" { print $1; exit }' ;;
    kubectl)  curl -fsSL https://dl.k8s.io/release/stable.txt ;;
    k9s)      gh_release derailed/k9s | release_field ;;
    helm)     gh_release helm/helm | release_field ;;
  esac 2>/dev/null | semver
}

# Major: the first number changed, or, for 0.x versions, the second one.
is_major() {
  local a b
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  [ "${a[0]}" != "${b[0]}" ] || { [ "${a[0]}" = 0 ] && [ "${a[1]}" != "${b[1]}" ]; }
}

check_updates() {
  local t cur new outdated=() failed=0 line comps=" "
  printf '%-10s %-12s %-12s\n' tool installed latest
  for t in "${UPDATE_TOOLS[@]}"; do
    cur="$(installed_version "$t")"
    if [ -z "$cur" ]; then printf '%-10s %-12s\n' "$t" "-"; continue; fi
    new="$(latest_version "$t")"
    if [ -z "$new" ]; then printf '%-10s %-12s %-12s\n' "$t" "$cur" "(lookup failed)"; failed=1; continue; fi
    if version_ge "$cur" "$new"; then
      printf '%-10s %-12s %-12s\n' "$t" "$cur" "up to date"
    else
      line="$(printf '%-10s %-12s %-12s' "$t" "$cur" "$new")"
      is_major "$cur" "$new" && line="$line MAJOR"
      printf '%s\n' "$line"
      outdated+=("$line")
      [[ "$comps" == *" ${TOOL_COMPONENT[$t]} "* ]] || comps+="${TOOL_COMPONENT[$t]} "
    fi
  done
  mkdir -p "$(dirname "$UPDATES_FILE")"
  if [ ${#outdated[@]} -gt 0 ]; then
    { echo "# checked $(date +%F)"; printf '%s\n' "${outdated[@]}"; } >"$UPDATES_FILE"
    echo
    echo "Upgrade with: $DOTFILES_DIR/install.sh --upgrade${comps% }"
  else
    rm -f "$UPDATES_FILE"
  fi
  return "$failed"
}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
declare -A SELECTED=()
ADDED_DEPS=()

add_name() {
  local n="$1" x
  if [ -n "${PRESETS[$n]+set}" ]; then
    for x in ${PRESETS[$n]}; do add_name "$x"; done
  elif [ -n "${DESC[$n]+set}" ]; then
    [ -n "${SELECTED[$n]+set}" ] && return 0
    SELECTED[$n]=1
    for x in ${DEPS[$n]:-}; do
      if [ -z "${SELECTED[$x]+set}" ]; then ADDED_DEPS+=("$x (for $n)"); add_name "$x"; fi
    done
  else
    die "unknown component or preset: '$n' (see ./install.sh --list)"
  fi
}

print_list() {
  local c p
  echo "Components (install order):"
  for c in "${COMPONENTS[@]}"; do
    printf '  %-13s %s%s\n' "$c" "${DESC[$c]}" "${DEPS[$c]:+  [needs: ${DEPS[$c]}]}"
  done
  echo
  echo "Presets:"
  for p in "${PRESET_ORDER[@]}"; do
    if [ "$p" = full ]; then printf '  %-13s %s\n' "$p" "every component (same as --all)"
    else printf '  %-13s %s\n' "$p" "${PRESETS[$p]}"; fi
  done
}

usage() {
  cat <<EOF
Usage: ./install.sh [options] [component|preset ...]

With no names, opens a checklist (whiptail, or a numbered prompt) pre-ticked
with this machine's saved selection. core is always included, and
dependencies are added automatically. Named components are added to the saved
selection; the checklist replaces it.

Options:
  -a, --all          install every component (preset "full")
  -l, --list         list components and presets
  -n, --dry-run      print every command and link, change nothing
  -u, --upgrade      reinstall tools that are already present (latest release)
      --check-updates  compare installed tools with their latest releases
  -h, --help         this help

Examples:
  ./install.sh dev               ./install.sh minimal k8s
  ./install.sh zsh git nvim      ./install.sh --dry-run --all
  ./install.sh --upgrade nvim helm
EOF
}

# Remember what this machine has. Named runs add to the saved selection; the
# checklist replaces it, since it starts from the saved list (unticking an item
# there is how it leaves the list).
save_selection() {
  local c keep=() prev=" "
  [ "$REPLACE_SELECTION" = 1 ] || prev=" $(cat "$SELECTION_FILE" 2>/dev/null) "
  for c in "${COMPONENTS[@]}"; do
    [ "$c" = core ] && continue
    if [ -n "${SELECTED[$c]+set}" ] || [[ "$prev" == *" $c "* ]]; then keep+=("$c"); fi
  done
  mkdir -p "$(dirname "$SELECTION_FILE")"
  printf '%s\n' "${keep[*]}" >"$SELECTION_FILE"
}

choose_interactive() {
  local saved c i args=() picked reply choices=()
  saved=" $(cat "$SELECTION_FILE" 2>/dev/null || echo "${PRESETS[minimal]}") "
  for c in "${COMPONENTS[@]}"; do [ "$c" != core ] && choices+=("$c"); done

  if [ ! -t 0 ]; then
    die "no components given and no terminal: name components, a preset or --all (see --list)"
  fi
  REPLACE_SELECTION=1
  if have whiptail; then
    for c in "${choices[@]}"; do
      if [[ "$saved" == *" $c "* ]]; then args+=("$c" "${DESC[$c]}" ON); else args+=("$c" "${DESC[$c]}" OFF); fi
    done
    picked="$(whiptail --title "dotfiles" --separate-output \
      --checklist "Space toggles, Enter installs. Presets: ./install.sh --list" \
      26 90 18 "${args[@]}" 3>&1 1>&2 2>&3)" || die "cancelled"
    for c in $picked; do add_name "$c"; done
  else
    i=1
    for c in "${choices[@]}"; do
      printf '%3d) %-13s %s%s\n' "$i" "$c" "${DESC[$c]}" "$([[ "$saved" == *" $c "* ]] && echo '  *')"
      i=$((i + 1))
    done
    echo "Presets: ${PRESET_ORDER[*]}   (* = last selection)"
    read -r -p "Numbers or names, Enter for the * ones: " reply
    [ -n "$reply" ] || reply="$saved"
    for c in $reply; do
      if [[ "$c" =~ ^[0-9]+$ ]]; then
        { [ "$c" -ge 1 ] && [ "$c" -le ${#choices[@]} ]; } || die "no item $c"
        add_name "${choices[$((c - 1))]}"
      else add_name "$c"; fi
    done
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local mode=install names=() c d fn rc ok=() failed=() plan=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -a|--all)        names+=(full) ;;
      -l|--list)       mode=list ;;
      -n|--dry-run)    DRY_RUN=1 ;;
      -u|--upgrade)    UPGRADE=1 ;;
      --check-updates) mode=check ;;
      -h|--help)       mode=help ;;
      -*)              die "unknown option: $1 (see --help)" ;;
      *)               names+=("$1") ;;
    esac
    shift
  done

  case "$mode" in
    help)  usage; return 0 ;;
    list)  print_list; return 0 ;;
    check) check_updates; return ;;
  esac

  [ "$(id -u)" -ne 0 ] || die "don't run this as root or with sudo: it calls sudo itself where needed"

  for c in "${names[@]}"; do add_name "$c"; done
  [ ${#names[@]} -gt 0 ] || choose_interactive
  SELECTED[core]=1

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  for c in "${COMPONENTS[@]}"; do [ -n "${SELECTED[$c]+set}" ] && plan+=("$c"); done
  echo "Installing: ${plan[*]}"
  for d in "${ADDED_DEPS[@]}"; do echo "  added dependency: $d"; done
  [ "$DRY_RUN" = 1 ] && echo "(dry run: nothing will change)"

  for c in "${plan[@]}"; do
    log "$c"
    fn="c_${c//-/_}"
    # A plain statement, not `if ( ... )` or `( ... ) || ...`: bash ignores
    # set -e in a subshell used as a condition.
    ( set -e; "$fn" )
    rc=$?
    if [ "$rc" -eq 0 ]; then ok+=("$c"); else failed+=("$c"); warn "$c failed"; fi
  done

  [ "$DRY_RUN" = 1 ] || save_selection

  log "Summary"
  echo "ok:     ${ok[*]:-none}"
  if [ ${#failed[@]} -gt 0 ]; then
    echo "failed: ${failed[*]}  (rerun: ./install.sh ${failed[*]})"
    return 1
  fi
  if [ "$DRY_RUN" = 0 ] && [ -n "${SELECTED[zsh]+set}" ]; then echo "Restart your shell (or run 'exec zsh') to pick up changes."; fi
  return 0
}

main "$@"
