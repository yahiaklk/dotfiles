# PATH
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory sharehistory hist_ignore_dups hist_ignore_space

# Completions
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# Every tool below is optional: install.sh lets each machine pick its own set,
# so each one is loaded only when it is present.
_have() { (( $+commands[$1] )) }

# Plugins
for _p in ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh \
          ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  [[ -f $_p ]] && source $_p
done
unset _p

_have starship && eval "$(starship init zsh)"
_have direnv   && eval "$(direnv hook zsh)"
_have zoxide   && eval "$(zoxide init zsh)"

# fzf
[[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[[ -f /usr/share/doc/fzf/examples/completion.zsh ]]   && source /usr/share/doc/fzf/examples/completion.zsh

# CUDA
if [[ -d /usr/local/cuda/bin ]]; then
  export PATH=/usr/local/cuda/bin:$PATH
  export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi

# kubectl — aliases match CKA exam environment
alias k=kubectl
if _have kubectl; then
  source <(kubectl completion zsh)
  compdef _kubectl k
fi

# CKA-safe shortcuts (memorize these, they're allowed in the exam)
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deployments'
alias kgns='kubectl get namespaces'
alias kga='kubectl get all'
alias kgpa='kubectl get pods -A'
alias kdp='kubectl describe pod'
alias kds='kubectl describe svc'
alias kdn='kubectl describe node'
alias kdd='kubectl describe deployment'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias krun='kubectl run --rm -it --restart=Never'
alias kcn='kubectl config set-context --current --namespace'
alias kcc='kubectl config current-context'
alias kcu='kubectl config use-context'
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'

# Docker
alias d='docker'
alias dps='docker ps'
alias dpa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dl='docker logs -f'
alias dcp='docker compose'
alias dcpu='docker compose up -d'
alias dcpd='docker compose down'

# Terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfo='terraform output'
alias tfs='terraform state list'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline -20'
alias gd='git diff'
alias gco='git checkout'
alias gsw='git switch'
alias gb='git branch'

# Claude Code (two accounts)
alias cc1='claude'
alias cc2='CLAUDE_CONFIG_DIR=~/.claude-work claude'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ll='ls -lah'
alias mkd='mkdir -p'

_have helm && source <(helm completion zsh)
_have uv   && eval "$(uv generate-shell-completion zsh)"

# Keybindings
bindkey "^[[1;5C" forward-word   # Ctrl+Right
bindkey "^[[1;5D" backward-word  # Ctrl+Left
bindkey "^[[5C"   forward-word   # Ctrl+Right (older terminals)
bindkey "^[[5D"   backward-word  # Ctrl+Left (older terminals)

# Editor
export EDITOR=nvim
export VISUAL=nvim

# 1Password CLI completion (only where the optional 1password component is installed)
if _have op; then
  eval "$(op completion zsh)"
  compdef _op op
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Weekly update check (install.sh update-check component)
if [[ -s ~/.cache/dotfiles/updates ]]; then
  print -P "%F{yellow}dotfiles:%f $(grep -vc '^#' ~/.cache/dotfiles/updates) tool update(s), $(grep -c MAJOR ~/.cache/dotfiles/updates) major: run ~/dotfiles/install.sh --check-updates"
fi

# Per-machine settings (e.g. an SSH agent socket). Not tracked by this repo.
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
unfunction _have
