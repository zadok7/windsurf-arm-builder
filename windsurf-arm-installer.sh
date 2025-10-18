#!/usr/bin/env bash
# Windsurf ARM Builder for Linux
# Build and run Windsurf IDE on ARM64 Linux systems
#
# This script assembles a working Windsurf installation by combining:
# - VS Code ARM64 binaries (from Microsoft)
# - Windsurf resources and extensions (from official x64 tarball)
# - Codeium ARM language server (from GitHub)
#
# Based on the original work by @rodriguezst: github.com/rodriguezst/windsurf-arm
# This version provides a standalone bash installer (no Nix dependency)

set -euo pipefail
shopt -s nullglob nocaseglob

VER="windsurf-arm"
say()  { printf "[windsurf-arm:%s] %s\n" "$VER" "$*"; }
warn() { printf "[windsurf-arm:%s:WARN] %s\n" "$VER" "$*" >&2; }
die()  { printf "[windsurf-arm:%s:ERROR] %s\n" "$VER" "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null || die "Required command not found: $1"; }

yesno() {
  local prompt="$1" def="${2:-default_yes}" ans=""
  case "$def" in
    default_yes) prompt="$prompt [Y/n] " ;;
    default_no)  prompt="$prompt [y/N] " ;;
    *)           prompt="$prompt [y/n] "  ;;
  esac
  read -r -p "$prompt" ans || ans=""
  case "${ans,,}" in
    y|yes) return 0 ;;
    n|no)  return 1 ;;
    *)     [[ "$def" == "default_yes" ]] && return 0 || return 1 ;;
  esac
}

is_gzip() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  file --mime-type "$f" | grep -q 'gzip'
}

pick_newest() { ls -1t -- "$@" 2>/dev/null | head -n1 || true; }

fetch_vscode_tarball() {
  local ver="$1" dest="$2"
  local url="" tmp="" out=""
  mkdir -p "$dest"
  url="https://update.code.visualstudio.com/${ver}/linux-arm64/stable"
  out="$dest/code-linux-arm64-${ver}.tar.gz"
  tmp="${out}.part"
  say "Downloading VS Code ARM64 ${ver}" >&2
  echo "URL: $url" >&2
  if curl -fL --progress-bar --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    mv -f "$tmp" "$out"
    is_gzip "$out" || { rm -f "$out"; die "VS Code download is not gzip"; }
    printf "%s\n" "$out"
  else
    rm -f "$tmp"
    die "Failed to download VS Code ${ver}"
  fi
}

fetch_codeium_ls() {
  local version="$1" dest="$2"
  local url=""
  if [[ "$version" == "latest" ]]; then
    url="https://github.com/Exafunction/codeium/releases/latest/download/language_server_linux_arm"
  else
    url="https://github.com/Exafunction/codeium/releases/download/language-server-v${version}/language_server_linux_arm"
  fi
  say "Downloading Codeium LS ($version)" >&2
  echo "URL: $url" >&2
  curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url" || return 1
  chmod +x "$dest"
}

ARCH="$(uname -m)"
[[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] || die "This script targets ARM64/aarch64. Detected: $ARCH"

require_cmd tar
require_cmd rsync
require_cmd jq
require_cmd file
require_cmd curl

echo
echo "========================================="
echo "Step 0: Output / isolation directory"
echo "========================================="
DEFAULT_OUTDIR="$HOME/apps/windsurf-arm-current"
read -r -p "Choose output dir (default: $DEFAULT_OUTDIR): " OUTDIR
OUTDIR="${OUTDIR:-$DEFAULT_OUTDIR}"
OUTDIR="${OUTDIR/#\~/$HOME}"

# Check if directory exists and has content
if [[ -d "$OUTDIR" ]] && [[ -n "$(ls -A "$OUTDIR" 2>/dev/null)" ]]; then
  warn "Output directory already exists and contains files: $OUTDIR"
  if yesno "Remove existing installation and start fresh?" default_no; then
    say "Cleaning existing installation..."
    rm -rf "${OUTDIR:?}/"*
    say "Cleaned: $OUTDIR"
  else
    warn "Installing over existing files - this may cause issues!"
    if ! yesno "Continue anyway?" default_no; then
      die "Installation cancelled by user"
    fi
  fi
fi

mkdir -p "$OUTDIR"
say "Using OUTDIR: $OUTDIR"

# Isolated data roots
DATA_DIR="$OUTDIR/data"
USER_DATA_DIR="$DATA_DIR/userdata"
EXTENSIONS_DIR="$DATA_DIR/extensions"
mkdir -p "$USER_DATA_DIR/User" "$USER_DATA_DIR/logs" "$EXTENSIONS_DIR"

# temp
TMPDL="$OUTDIR/_downloads"
mkdir -p "$TMPDL"

echo
echo "========================================="
echo "Step 1: Windsurf x64 Tarball"
echo "========================================="
read -r -p "Path to Windsurf x64 tarball (or a directory containing one): " WIND_IN
WIND_IN="${WIND_IN/#\~/$HOME}"
WIND_TGZ=""

if [[ -z "${WIND_IN}" ]]; then
  die "Windsurf tarball is required (no public URL to fetch reliably)."
elif [[ -f "$WIND_IN" ]]; then
  WIND_TGZ="$WIND_IN"
elif [[ -d "$WIND_IN" ]]; then
  WIND_TGZ="$(pick_newest "$WIND_IN"/Windsurf-linux-x64-*.tar.gz "$WIND_IN"/windsurf-linux-x64-*.tar.gz)"
  [[ -n "$WIND_TGZ" ]] || die "Could not find Windsurf-linux-x64-*.tar.gz in $WIND_IN"
else
  die "Not found: $WIND_IN"
fi
is_gzip "$WIND_TGZ" || die "Not a gzip tarball: $WIND_TGZ"
say "Using Windsurf tar: $(basename "$WIND_TGZ")"

echo
echo "========================================="
echo "Step 2: Derive required VS Code version"
echo "========================================="
DERIVED_VSC_VER=""
product_json_path="$(tar -tzf "$WIND_TGZ" | grep -m1 'resources/app/product.json' || true)"
pkg_json_path="$(tar -tzf "$WIND_TGZ" | grep -m1 'resources/app/package.json' || true)"

if [[ -n "$pkg_json_path" ]]; then
  DERIVED_VSC_VER="$(tar -xOf "$WIND_TGZ" "$pkg_json_path" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
fi
if [[ -z "$DERIVED_VSC_VER" && -n "$product_json_path" ]]; then
  DERIVED_VSC_VER="$(tar -xOf "$WIND_TGZ" "$product_json_path" 2>/dev/null | jq -r '.vscodeVersion // empty' 2>/dev/null || true)"
fi
if [[ -z "$DERIVED_VSC_VER" ]]; then
  warn "Could not detect VS Code version from Windsurf; defaulting to 1.94.0"
  DERIVED_VSC_VER="1.94.0"
fi
say "Required VS Code version: $DERIVED_VSC_VER"

echo
echo "========================================="
echo "Step 3: VS Code ARM64 Base"
echo "========================================="
read -r -p "Path to VS Code ARM64 tarball (press Enter to DOWNLOAD ${DERIVED_VSC_VER}): " VSC_IN
VSC_IN="${VSC_IN/#\~/$HOME}"
VSC_TGZ=""

if [[ -n "$VSC_IN" ]]; then
  [[ -f "$VSC_IN" ]] || die "Not found: $VSC_IN"
  is_gzip "$VSC_IN" || die "Not a gzip tarball: $VSC_IN"
  VSC_TGZ="$VSC_IN"
else
  VSC_TGZ="$(fetch_vscode_tarball "$DERIVED_VSC_VER" "$TMPDL")"
fi
say "Using VS Code ARM tar: $(basename "$VSC_TGZ")"

echo
echo "========================================="
echo "Step 4: Extract and assemble"
echo "========================================="
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say "[1/7] Extracting VS Code ARM base"
mkdir -p "$work/vscode-arm"
tar -xzf "$VSC_TGZ" -C "$work/vscode-arm" --strip-components=1

say "[2/7] Extracting Windsurf x64"
mkdir -p "$work/windsurf-x64"
tar -xzf "$WIND_TGZ" -C "$work/windsurf-x64" --strip-components=1

say "[3/7] Laying down ARM base into OUTDIR"
rsync -a --delete "$work/vscode-arm/" "$OUTDIR/"

# Rename binary
[[ -x "$OUTDIR/code"   ]] && mv -f "$OUTDIR/code"   "$OUTDIR/windsurf" || true
[[ -x "$OUTDIR/codium" ]] && mv -f "$OUTDIR/codium" "$OUTDIR/windsurf" || true

say "[4/7] Overlay Windsurf resources (selective copy)"
# Copy Windsurf JS overlays
rsync -a "$work/windsurf-x64/resources/app/out/" "$OUTDIR/resources/app/out/"
rsync -a "$work/windsurf-x64/resources/app/"*.json "$OUTDIR/resources/app/" || true

# Copy node_modules.asar
rm -f "$OUTDIR/resources/app/node_modules.asar" || true
if [[ -f "$work/windsurf-x64/resources/app/node_modules.asar" ]]; then
  cp "$work/windsurf-x64/resources/app/node_modules.asar" "$OUTDIR/resources/app/"
fi

# Copy resources directory
rm -rf "$OUTDIR/resources/app/resources" || true
if [[ -d "$work/windsurf-x64/resources/app/resources" ]]; then
  rsync -a "$work/windsurf-x64/resources/app/resources/" "$OUTDIR/resources/app/resources/"
fi

# Copy bin directory
rm -rf "$OUTDIR/bin" || true
if [[ -d "$work/windsurf-x64/bin" ]]; then
  cp -R "$work/windsurf-x64/bin" "$OUTDIR/"
fi

say "[5/7] Copy Windsurf extension (v18: COMPLETE file patterns)"
ext_src="$work/windsurf-x64/resources/app/extensions"
ext_dst="$OUTDIR/resources/app/extensions"

# Copy windsurf-* extensions (if any)
for ws_ext in "$ext_src"/windsurf-*; do
  if [[ -d "$ws_ext" ]]; then
    rsync -a "$ws_ext/" "$ext_dst/$(basename "$ws_ext")/"
  fi
done

# Create windsurf directory if needed
mkdir -p "$ext_dst/windsurf"

# v18 FIX: Include *.html and *.txt files (cascade-panel.html, LICENSE.txt)
for item in "$ext_src/windsurf"/*.js "$ext_src/windsurf"/*.json "$ext_src/windsurf"/*.mjs \
            "$ext_src/windsurf"/*.html "$ext_src/windsurf"/*.txt "$ext_src/windsurf"/.prettierignore; do
  if [[ -e "$item" ]]; then
    cp "$item" "$ext_dst/windsurf/"
  fi
done

# Copy specific directories
for subdir in assets dist out customEditor schemas; do
  if [[ -d "$ext_src/windsurf/$subdir" ]]; then
    rsync -a "$ext_src/windsurf/$subdir/" "$ext_dst/windsurf/$subdir/"
  fi
done

say "[6/7] Install ARM Language Server"
mkdir -p "$ext_dst/windsurf/bin"

echo
echo "========================================="
echo "⚠️  Known Limitation: @file Feature"
echo "========================================="
echo
echo "Windsurf's @file feature requires a CUSTOM language server with"
echo "proprietary endpoints (GetCodeMapsForRepos) that Windsurf only"
echo "provides for x64 Linux, not ARM Linux."
echo
echo "We will install the public Codeium ARM language server, which:"
echo "  ✅ Works great for most Windsurf features"
echo "  ✅ Fast native ARM performance"
echo "  ✅ Stable and well-tested"
echo "  ❌ @file feature will NOT work (returns 404)"
echo "  ❌ GetCodeMapsForRepos endpoint missing"
echo
echo "This is a Windsurf limitation, not a build issue."
echo "We cannot work around this without x86-64 system libraries."
echo
read -r -p "Press Enter to continue with ARM language server..."
echo

say "Installing native ARM language server (Codeium)..."

read -r -p "Path to Codeium LS (ARM) binary (press Enter to auto-download): " LS_IN
LS_IN="${LS_IN/#\~/$HOME}"

if [[ -n "$LS_IN" ]]; then
  [[ -f "$LS_IN" ]] || die "Not found: $LS_IN"
  install -Dm755 "$LS_IN" "$ext_dst/windsurf/bin/language_server_linux_arm"
else
  # Try to detect version from extension
  ls_ver=""
  ext_text_file=$(find "$ext_dst/windsurf" -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.json' \) -print0 | xargs -0 grep -Il "LANGUAGE_SERVER_VERSION" 2>/dev/null | head -n1 || true)
  if [[ -n "$ext_text_file" ]]; then
    ls_ver=$(grep -oE 'LANGUAGE_SERVER_VERSION[^0-9]*([0-9]+(\.[0-9]+)*)' "$ext_text_file" | grep -oE '([0-9]+(\.[0-9]+)*)' | head -n1 || true)
  fi
  
  if [[ -n "$ls_ver" ]]; then
    say "Detected Codeium LS version: $ls_ver"
    if ! fetch_codeium_ls "$ls_ver" "$ext_dst/windsurf/bin/language_server_linux_arm"; then
      warn "Download v$ls_ver failed; trying latest…"
      fetch_codeium_ls "latest" "$ext_dst/windsurf/bin/language_server_linux_arm" || die "Could not obtain Codeium LS"
    fi
  else
    say "Could not detect LS version; fetching latest"
    fetch_codeium_ls "latest" "$ext_dst/windsurf/bin/language_server_linux_arm" || die "Could not obtain Codeium LS"
  fi
fi
say "✅ ARM language server installed"
echo

# fd helper
say "Installing fd helper (ARM)"
tmpfd="$(mktemp -d)"; trap 'rm -rf "$tmpfd"' RETURN
if curl -fL -o "$tmpfd/fd.tar.gz" "https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-aarch64-unknown-linux-gnu.tar.gz"; then
  tar -xzf "$tmpfd/fd.tar.gz" -C "$tmpfd"
  find "$tmpfd" -type f -name 'fd' -executable -exec install -Dm755 {} "$ext_dst/windsurf/bin/fd" \;
  say "Installed fd"
else
  warn "Could not download fd; continuing without it"
fi

say "[7/7] Chrome sandbox perms (optional)"
if [[ -f "$OUTDIR/chrome-sandbox" ]]; then
  if sudo chown root:root "$OUTDIR/chrome-sandbox" && sudo chmod 4755 "$OUTDIR/chrome-sandbox"; then
    say "chrome-sandbox setuid root OK"
  else
    warn "Could not set chrome-sandbox perms; you can run with --no-sandbox"
  fi
else
  warn "chrome-sandbox not found; you may need --no-sandbox"
fi

echo
echo "========================================="
echo "Step 5: Settings seed"
echo "========================================="
SETTINGS="$USER_DATA_DIR/User/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
if [[ ! -f "$SETTINGS" ]]; then
  cat > "$SETTINGS" <<'JSON'
{
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false,
  "window.showReleaseNotes": false
}
JSON
  say "Wrote $SETTINGS"
else
  say "Keeping existing $SETTINGS"
fi

echo
echo "========================================="
echo "Step 6: Launcher"
echo "========================================="
LAUNCHER="$HOME/.local/bin/windsurf"
mkdir -p "$(dirname "$LAUNCHER")"
LOGFILE="$OUTDIR/windsurf.log"

echo "Pick launch mode:"
echo "  1) Recommended: --disable-gpu"
echo "  2) No sandbox:  --disable-gpu --no-sandbox"
echo "  3) SwiftShader: --disable-gpu --enable-unsafe-swiftshader"
echo "  4) Max compat:  --disable-gpu --disable-gpu-sandbox --no-sandbox"
read -r -p "Choice [1-4] (default: 1): " choice
choice="${choice:-1}"

LAUNCH_FLAGS=""
case "$choice" in
  1) LAUNCH_FLAGS="--disable-gpu" ;;
  2) LAUNCH_FLAGS="--disable-gpu --no-sandbox" ;;
  3) LAUNCH_FLAGS="--disable-gpu --enable-unsafe-swiftshader" ;;
  4) LAUNCH_FLAGS="--disable-gpu --disable-gpu-sandbox --no-sandbox" ;;
  *) LAUNCH_FLAGS="--disable-gpu" ;;
esac

cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
OUTDIR="$OUTDIR"
BIN="\$OUTDIR/windsurf"
USER_DATA_DIR="$USER_DATA_DIR"
EXTENSIONS_DIR="$EXTENSIONS_DIR"
LOGFILE="$LOGFILE"
FLAGS="$LAUNCH_FLAGS --disable-updates --user-data-dir=\$USER_DATA_DIR --extensions-dir=\$EXTENSIONS_DIR"

mkdir -p "\$USER_DATA_DIR" "\$EXTENSIONS_DIR"
chmod 700 "\$USER_DATA_DIR"

# Check for foreground mode
FOREGROUND=false
for arg in "\$@"; do
  if [[ "\$arg" == "--foreground" ]]; then
    FOREGROUND=true
    shift
    break
  fi
done

if [[ "\${WINDSURF_FOREGROUND:-}" == "1" ]]; then
  FOREGROUND=true
fi

if [[ "\$FOREGROUND" == true ]]; then
  echo "Launching Windsurf in FOREGROUND mode..."
  exec "\$BIN" \$FLAGS "\$@"
else
  nohup "\$BIN" \$FLAGS "\$@" >> "\$LOGFILE" 2>&1 & disown
  echo "Windsurf launched in background. Logs: \$LOGFILE"
  echo "To launch in foreground: windsurf --foreground"
fi
EOF
chmod +x "$LAUNCHER"
say "Created launcher: $LAUNCHER"
echo "Add to PATH if needed:  echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc && source ~/.bashrc"

echo
echo "========================================================================================"
echo "Installation Complete!"
echo "OUTDIR:        $OUTDIR"
echo "User-data:     $USER_DATA_DIR"
echo "Extensions:    $EXTENSIONS_DIR (for user-installed extensions only)"
echo "Launcher:      $LAUNCHER"
echo "========================================================================================"
echo
echo "🚀 Launch Windsurf:"
echo "  Background (default):  windsurf"
echo "  Foreground (w/ logs):  windsurf --foreground"
echo "                    or:  WINDSURF_FOREGROUND=1 windsurf"
echo
echo "  💡 Use foreground mode to see errors and debug issues"
echo "========================================================================================"
echo
echo "✅ What Works:"
echo "  ✅ Cascade AI chat and code editing"
echo "  ✅ Autocomplete and language server"
echo "  ✅ Terminal integration"
echo "  ✅ Native ARM performance"
echo "  ✅ All standard Windsurf features"
echo
echo "⚠️  Known Limitation:"
echo "  ❌ @file feature does NOT work"
echo "     Requires Windsurf's custom language server (not available for Linux ARM)"
echo "     Windsurf publishes custom ARM LS for macOS but not Linux"
echo "     See README.md for detailed explanation and evidence"
echo "========================================================================================"
