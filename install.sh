#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu/Debian machine (WSL or bare-metal) from this repo.
# Usage: ./install.sh
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$1" >&2; }

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    mv "$dst" "$backup_dir/"
    warn "backed up existing $dst -> $backup_dir/"
  fi
  ln -s "$src" "$dst"
  echo "linked $dst -> $src"
}

log "Installing apt packages"
sudo apt-get update
sudo apt-get install -y zsh neovim direnv fzf tmux unzip curl git gnupg apt-transport-https

log "Installing Helm (user-local, no sudo)"
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get_helm.sh
  chmod +x /tmp/get_helm.sh
  HELM_INSTALL_DIR="$HOME/.local/bin" /tmp/get_helm.sh --no-sudo || true
  rm -f /tmp/get_helm.sh
else
  echo "helm already installed"
fi

log "Installing 1Password CLI (apt repo)"
if ! command -v op >/dev/null; then
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
    | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null
  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22
  curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
  sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
  sudo apt-get update
  sudo apt-get install -y 1password-cli
else
  echo "op already installed"
fi

log "Installing starship, zoxide, uv (user-local, no sudo)"
command -v starship >/dev/null || curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
command -v zoxide    >/dev/null || curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash -s -- --bin-dir "$HOME/.local/bin"
command -v uv        >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$HOME/.local/bin" sh

log "Installing zsh plugins"
mkdir -p "$HOME/.zsh"
[ -d "$HOME/.zsh/zsh-autosuggestions" ]     || git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions"
[ -d "$HOME/.zsh/zsh-syntax-highlighting" ] || git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/zsh-syntax-highlighting"

log "Linking dotfiles"
link "$DOTFILES_DIR/zsh/.zshrc"                                        "$HOME/.zshrc"
link "$DOTFILES_DIR/vim/.vimrc"                                        "$HOME/.vimrc"
link "$DOTFILES_DIR/git/.gitconfig"                                    "$HOME/.gitconfig"
link "$DOTFILES_DIR/git/.gitignore_global"                             "$HOME/.gitignore_global"
link "$DOTFILES_DIR/git/hooks"                                         "$HOME/.config/git/hooks"
link "$DOTFILES_DIR/git/projects.gitconfig"                            "$HOME/.config/git/projects.gitconfig"
link "$DOTFILES_DIR/terraform/.terraformrc"                            "$HOME/.terraformrc"
link "$DOTFILES_DIR/nvim"                                              "$HOME/.config/nvim"
link "$DOTFILES_DIR/starship/.config/starship.toml"                    "$HOME/.config/starship.toml"
link "$DOTFILES_DIR/direnv/direnvrc"                                   "$HOME/.config/direnvrc"
link "$DOTFILES_DIR/libinput-gestures/.config/libinput-gestures.conf"  "$HOME/.config/libinput-gestures.conf"
link "$DOTFILES_DIR/aws/config"                                        "$HOME/.aws/config"
link "$DOTFILES_DIR/ssh/config"                                        "$HOME/.ssh/config"
link "$DOTFILES_DIR/tmux/.tmux.conf"                                   "$HOME/.tmux.conf"
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/config"

log "Syncing nvim plugins"
command -v nvim >/dev/null && nvim --headless "+Lazy! sync" +qa

log "Verifying Claude Code CLI"
if [ -n "${CLAUDECODE:-}" ]; then
  warn "running inside a Claude Code session — skipping claude-code verification"
  warn "(reinstalling the package a running session executes from can crash it mid-script)"
elif command -v npm >/dev/null; then
  claude_bin="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/bin/claude.exe"
  if [ -f "$claude_bin" ]; then
    # The postinstall placeholder stub is a ~500 byte shell script; the real
    # native binary is tens of MB. A stub left in place means the optional
    # platform package silently failed to download (npm doesn't fail the
    # install for a failed optional dep).
    size=$(stat -c%s "$claude_bin" 2>/dev/null || echo 0)
    if [ "$size" -lt 100000 ]; then
      warn "claude-code native binary missing (found a ${size}-byte stub) — reinstalling"
      npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1
      npm cache clean --force >/dev/null 2>&1
      npm install -g @anthropic-ai/claude-code@latest
      size=$(stat -c%s "$claude_bin" 2>/dev/null || echo 0)
      if [ "$size" -lt 100000 ]; then
        warn "still just a stub after reinstall — likely a network/TLS issue fetching the"
        warn "optional platform package. Try: npm install -g @anthropic-ai/claude-code-linux-x64@\$(npm view @anthropic-ai/claude-code version)"
      else
        echo "claude-code native binary installed (${size} bytes)"
      fi
    else
      echo "claude-code native binary OK (${size} bytes)"
    fi
  else
    echo "claude-code not installed via npm — skipping (install separately if needed)"
  fi
else
  echo "npm not found — skipping claude-code check"
fi

log "Setting zsh as default shell"
if [ "$SHELL" != "$(command -v zsh)" ]; then
  chsh -s "$(command -v zsh)" && echo "default shell set to zsh (restart your terminal)" \
    || warn "could not chsh automatically — run: chsh -s \$(which zsh)"
fi

log "Done. Restart your shell (or run 'exec zsh') to pick up changes."
warn "Note: commit signing uses the 1Password desktop app's SSH signing helper (op-ssh-sign)."
warn "Install/configure the 1Password app separately — the CLI alone doesn't provide it."
