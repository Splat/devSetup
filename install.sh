#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()    { echo "[install] $*"; }
success() { echo "[install] ✓ $*"; }
skip()    { echo "[install] - $* (already done)"; }

# Usage: install.sh [--upgrade]   (--upgrade also updates already-installed tools)
UPGRADE=0
case "${1:-}" in
  --upgrade|-u) UPGRADE=1 ;;
  "") ;;
  *) echo "Usage: $0 [--upgrade]"; exit 1 ;;
esac

# ── Homebrew ──────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon puts brew in /opt/homebrew
  # Apple Silicon: /opt/homebrew, Intel: /usr/local
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$b" ]]; then
      eval "$("$b" shellenv)"
      break
    fi
  done
  success "Homebrew installed"
else
  skip "Homebrew"
fi

# ── CLI tools via brew ────────────────────────────────────────────────────────
# brew_tool <command> <brew-name> [cask] [self-update-cmd...]
# Installs if the command is missing. With --upgrade, upgrades only if Homebrew
# manages it; otherwise runs the tool's own updater, or warns if it has none
# (e.g. Go from go.dev, claude from its native installer).
brew_tool() {
  local cmd="$1" name="$2" kind="${3:-formula}"
  shift 3 || shift $#
  local flag="--formula" upgrade_flags=()
  if [[ "$kind" == "cask" ]]; then
    flag="--cask"
    upgrade_flags=(--cask --greedy)
  fi

  if ! command -v "$cmd" &>/dev/null; then
    info "Installing $name..."
    brew install "$flag" "$name"
    success "$name installed"
  elif [[ $UPGRADE -eq 1 ]]; then
    if brew list "$flag" "$name" &>/dev/null; then
      info "Upgrading $name..."
      brew upgrade "${upgrade_flags[@]}" "$name" || true
    elif [[ $# -gt 0 ]]; then
      info "Updating $cmd via '$*'..."
      "$@" || echo "[install] WARNING: '$*' failed — continuing"
    else
      echo "[install] - $cmd not managed by Homebrew; update it manually"
    fi
  else
    skip "$cmd"
  fi
}

brew_tool git   git          formula
brew_tool go    go           formula
brew_tool tmux  tmux         formula
brew_tool lf    lf           formula
brew_tool node  node         formula

# ── AI coding assistants ──────────────────────────────────────────────────────
brew_tool claude  claude-code  cask claude update
brew_tool copilot copilot-cli  cask
brew_tool codex   codex        cask

# ── TPM (tmux plugin manager) ─────────────────────────────────────────────────
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
  info "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  success "TPM installed"
elif [[ $UPGRADE -eq 1 ]]; then
  info "Updating TPM..."
  git -C "$HOME/.tmux/plugins/tpm" pull --ff-only
else
  skip "TPM"
fi

# ── Go tools ──────────────────────────────────────────────────────────────────
if ! command -v go &>/dev/null; then
  echo "[install] ERROR: go not found after install — check your PATH"
  exit 1
fi

# Go-installed binaries (dlv, gopls, godoc) live here; needed for the checks below
export PATH="$(go env GOPATH)/bin:$PATH"

for tool in "golang.org/x/tools/gopls@latest" "github.com/go-delve/delve/cmd/dlv@latest" "golang.org/x/tools/cmd/godoc@latest"; do
  bin="${tool##*/}"
  bin="${bin%%@*}"
  if ! command -v "$bin" &>/dev/null || [[ $UPGRADE -eq 1 ]]; then
    info "Installing/upgrading $bin..."
    # Don't abort the whole install if a tool needs a newer Go than installed
    if go install "$tool"; then
      success "$bin installed"
    else
      echo "[install] WARNING: failed to install $bin (check your Go version) — continuing"
    fi
  else
    skip "$bin"
  fi
done

# ── vim-plug ──────────────────────────────────────────────────────────────────
PLUG_PATH="$HOME/.vim/autoload/plug.vim"
if [[ ! -f "$PLUG_PATH" || $UPGRADE -eq 1 ]]; then
  info "Installing/upgrading vim-plug..."
  curl -fLo "$PLUG_PATH" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  success "vim-plug installed"
else
  skip "vim-plug"
fi

# ── Symlink config files ──────────────────────────────────────────────────────
info "Symlinking config files..."

symlink() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    skip "$(basename "$dst")"
  else
    ln -sf "$src" "$dst"
    success "$(basename "$dst") → $dst"
  fi
}

symlink "$REPO_DIR/tmux.conf"        "$HOME/.tmux.conf"
symlink "$REPO_DIR/.vimrc"           "$HOME/.vimrc"
symlink "$REPO_DIR/lfrc"             "$HOME/.config/lf/lfrc"
symlink "$REPO_DIR/coc-settings.json" "$HOME/.vim/coc-settings.json"

# ── dev-session script ────────────────────────────────────────────────────────
mkdir -p "$HOME/bin"
if [[ ! -f "$HOME/bin/dev-session" ]] || ! diff -q "$REPO_DIR/dev-session.sh" "$HOME/bin/dev-session" &>/dev/null; then
  cp "$REPO_DIR/dev-session.sh" "$HOME/bin/dev-session"
  chmod +x "$HOME/bin/dev-session"
  success "dev-session installed to ~/bin"
else
  skip "dev-session"
fi

# ── Vim plugins (headless) ────────────────────────────────────────────────────
# PlugInstall/PlugUpdate also runs vim-go's GoUpdateBinaries hook.
if [[ $UPGRADE -eq 1 ]]; then PLUG_CMD="PlugUpdate"; else PLUG_CMD="PlugInstall"; fi
info "Running vim :$PLUG_CMD --sync..."
if vim -N -es -u "$HOME/.vimrc" -i NONE -c "$PLUG_CMD --sync" -c "qa!" </dev/null; then
  success "vim plugins ready"
else
  echo "[install] WARNING: :$PLUG_CMD failed — run it manually inside vim"
fi

info "Installing coc-go..."
if vim -N -es -u "$HOME/.vimrc" -i NONE -c "CocInstall -sync coc-go" -c "qa!" </dev/null; then
  success "coc-go ready"
else
  echo "[install] WARNING: :CocInstall coc-go failed — run it manually inside vim"
fi

# ── tmux plugins (TPM, headless) ──────────────────────────────────────────────
if [[ $UPGRADE -eq 1 ]]; then
  "$HOME/.tmux/plugins/tpm/bin/update_plugins" all || echo "[install] WARNING: TPM update failed"
else
  "$HOME/.tmux/plugins/tpm/bin/install_plugins" || echo "[install] WARNING: TPM install failed"
fi

# ── PATH entries ─────────────────────────────────────────────────────────────
SHELL_RC="$HOME/.zshrc"
[[ "$SHELL" == *bash* ]] && SHELL_RC="$HOME/.bash_profile"

if ! grep -q 'brew shellenv' "$SHELL_RC" 2>/dev/null; then
  # Brew lives in /opt/homebrew on Apple Silicon but /usr/local on Intel, so
  # resolve the path at shell startup instead of hardcoding one architecture.
  cat >> "$SHELL_RC" <<'EOF'
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
EOF
  success "Added brew shellenv to $SHELL_RC"
else
  skip "brew shellenv already in $SHELL_RC"
fi

if ! grep -q 'HOME/bin' "$SHELL_RC" 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
  success "Added ~/bin to PATH in $SHELL_RC"
else
  skip "~/bin already in PATH"
fi

# Go-installed tools (dlv, gopls, godoc) need GOPATH/bin on PATH or they won't be found
if ! grep -q 'GOPATH' "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" <<'EOF'
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
EOF
  success "Added GOPATH/bin to PATH in $SHELL_RC"
else
  skip "GOPATH already in $SHELL_RC"
fi

# ── Final steps ───────────────────────────────────────────────────────────────
# A tmux server started before an upgrade keeps running the old version, and the
# new client can't attach to it ("open terminal failed: not a terminal").
if tmux info &>/dev/null; then
  client_ver="$(tmux -V | awk '{print $2}')"
  server_ver="$(tmux display-message -p '#{version}' 2>/dev/null || true)"
  if [[ -n "$server_ver" && "$client_ver" != "$server_ver" ]]; then
    echo ""
    echo "[install] WARNING: running tmux server is $server_ver but installed tmux is $client_ver."
    echo "          New sessions/attach will fail until the server restarts."
    echo "          Save your work, then run 'tmux kill-server' (ends ALL sessions)."
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done. Remaining:"
echo ""
echo "  1. Reload your shell:"
echo "       source $SHELL_RC"
echo ""
echo "  2. Sign in on first use: claude, copilot (/login), codex"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
