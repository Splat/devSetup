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
for pkg in tmux lf node; do
  if ! command -v "$pkg" &>/dev/null; then
    info "Installing $pkg..."
    brew install "$pkg"
    success "$pkg installed"
  elif [[ $UPGRADE -eq 1 ]]; then
    info "Upgrading $pkg..."
    brew upgrade "$pkg" || true
  else
    skip "$pkg"
  fi
done

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
  echo "[install] ERROR: go not found — install Go first: https://go.dev/dl/"
  exit 1
fi

for tool in "golang.org/x/tools/gopls@latest" "github.com/go-delve/delve/cmd/dlv@latest"; do
  bin="${tool##*/}"
  bin="${bin%%@*}"
  if ! command -v "$bin" &>/dev/null || [[ $UPGRADE -eq 1 ]]; then
    info "Installing/upgrading $bin..."
    go install "$tool"
    success "$bin installed"
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

# ── Final manual steps ────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Manual steps remaining:"
echo ""
echo "  1. Reload your shell:"
echo "       source $SHELL_RC"
echo ""
echo "  2. Install vim plugins (inside vim):"
echo "       :PlugInstall   (or :PlugUpdate after --upgrade)"
echo "       :GoInstallBinaries"
echo "       :CocInstall coc-go"
echo ""
echo "  3. Install tmux plugins:"
echo "       tmux"
echo "       # then press: Ctrl-a I  (or Ctrl-a U to update)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
