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

# Plugins
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Starship
eval "$(starship init zsh)"

# direnv
eval "$(direnv hook zsh)"

# zoxide
eval "$(zoxide init zsh)"

# fzf
source /usr/share/doc/fzf/examples/key-bindings.zsh
source /usr/share/doc/fzf/examples/completion.zsh

# CUDA
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# kubectl — aliases match CKA exam environment
source <(kubectl completion zsh)
alias k=kubectl
compdef __start_kubectl k

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

# helm
source <(helm completion zsh)

# uv
eval "$(uv generate-shell-completion zsh)"

# Editor
export EDITOR=nvim
export VISUAL=nvim

# 1Password SSH agent
export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"

# 1Password CLI completion
eval "$(op completion zsh)"
compdef _op op

# AWS via 1Password — run any aws command with credentials from the vault
# Setup: store AWS credentials in 1Password as env vars AWS_ACCESS_KEY_ID and
# AWS_SECRET_ACCESS_KEY, then: op run --env-file=~/.aws/.op-env -- aws ...
# Quick alias for the Achraf profile:
aws-op() {
  op run --env-file="$HOME/.aws/.op-env.personal" -- aws "$@"
}

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
