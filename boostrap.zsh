#!/usr/bin/env zsh
# macOS bootstrap for mise and core tools
# Installs: Homebrew (if missing), mise and tools, and AWS CLI

set -euo pipefail
IFS=$'\n\t'

trap 'echo "[mise-setup][ERROR] Failed at line $LINENO." >&2' ERR

log()  { printf "[mise-setup] %s\n" "$*"; }
warn() { printf "[mise-setup][WARN] %s\n" "$*" >&2; }
die()  { printf "[mise-setup][ERROR] %s\n" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Function to ensure the script is running on macOS
# Exits with an error if the operating system is not Darwin (macOS)
require_macos() {
  local os
  os="$(uname -s 2>/dev/null || true)"
  [[ "$os" == "Darwin" ]] || die "This script is for macOS (Darwin). Detected: $os"
}

# Function to ensure Homebrew is installed
# Installs Homebrew if it is not already present
# Official Homebrew: https://brew.sh
ensure_brew() {
  if have brew; then
    log "Homebrew found: $(brew --version | head -n1)"
  else
    log "Installing Homebrew…"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Ensure brew is on PATH for Apple Silicon and Intel
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$('/opt/homebrew/bin/brew' shellenv)"
    local zprofile="$HOME/.zprofile"
    mkdir -p "$(dirname "$zprofile")"
    grep -Fqs "eval \"$('/opt/homebrew/bin/brew' shellenv)\"" "$zprofile" || \
      printf '\n# Homebrew (Apple Silicon)\n%s\n' "eval \"$('/opt/homebrew/bin/brew' shellenv)\"" >> "$zprofile"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$('/usr/local/bin/brew' shellenv)"
    local zprofile="$HOME/.zprofile"
    mkdir -p "$(dirname "$zprofile")"
    grep -Fqs "eval \"$('/usr/local/bin/brew' shellenv)\"" "$zprofile" || \
      printf '\n# Homebrew (Intel)\n%s\n' "eval \"$('/usr/local/bin/brew' shellenv)\"" >> "$zprofile"
  fi
}

# Function to ensure mise is installed
# Installs mise via Homebrew if not present and activates it for the shell
# Official mise: https://mise.jdx.dev
ensure_mise() {
  if have mise; then
    log "mise found: $(mise --version | head -n1)"
    brew upgrade mise || true
  else
    log "Installing mise via Homebrew…"
    brew install mise
  fi

  # Activate mise in zsh for future shells
  local zshrc="$HOME/.zshrc"
  mkdir -p "$(dirname "$zshrc")"
  if ! grep -Fqs 'eval "$(mise activate zsh)"' "$zshrc"; then
    printf '\n# mise activation\neval "$(mise activate zsh)"\n' >> "$zshrc"
    log "Appended mise activation to $zshrc"
  fi

  # Activate mise in current shell
  # shellcheck disable=SC1090
  eval "$(mise activate zsh)"
}

verify_mise() {
  log "Verifying tools listed in mise.toml…"

  if [[ ! -f "mise.toml" ]]; then
    die "mise.toml not found. Cannot verify tools."
  fi

  # Extract tool names from mise.toml
  local tools
  tools=$(grep -oP '^[a-zA-Z0-9_-]+(?=\s*=)' mise.toml)

  for tool in $tools; do
    if have "$tool"; then
      log "$tool version: $($tool --version 2>/dev/null || echo 'Unknown version')"
    else
      warn "$tool is not installed or not on PATH."
    fi
  done
}

# Function to trust and install tools from mise.toml or .tool-versions
# Ensures project-specific tool versions are installed
trust_project_config() {
  # If running inside a repo that already has mise.toml or .tool-versions, trust and install
  if [[ -f "mise.toml" || -f ".tool-versions" ]]; then
    log "Project config detected; trusting and installing…"
    mise trust -y || true
    mise use --yes -g || true
  else
    die "No mise.toml or .tool-versions found. Please add one to the project."
  fi
}

# Main function to orchestrate the setup process
# Calls all other functions in the correct order
main() {
  require_macos
  ensure_brew
  ensure_mise
  trust_project_config
  install_awscli
  verify_mise
  log "Done. Open a new terminal or 'source ~/.zshrc' to ensure PATH is updated."
}

main "$@"

