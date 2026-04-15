# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory sharehistory hist_ignore_dups hist_ignore_space

# Completions
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

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

# helm
source <(helm completion zsh)

# uv
eval "$(uv generate-shell-completion zsh)"

# PATH
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
