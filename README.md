# Windsurf ARM Builder for Linux

**Build and run [Windsurf IDE](https://windsurf.ai/) on ARM64 Linux systems**

This script assembles a working Windsurf installation for ARM64 Linux by combining:
- VS Code ARM64 binaries (from Microsoft)
- Windsurf resources and extensions (from official x64 tarball)
- Codeium ARM language server (from GitHub)

> **Note**: This is an **unofficial community project** based on the original work by [@rodriguezst](https://github.com/rodriguezst) ([windsurf-arm](https://github.com/rodriguezst/windsurf-arm)). This version provides a standalone bash installer rather than Nix-based approach.
> 
> Windsurf is developed by [Codeium](https://codeium.com/).

---

## Quick Start

### Prerequisites
- ARM64/aarch64 Linux system
- Latest **Windsurf x64 tarball** downloaded from [windsurf.ai](https://windsurf.ai/)
- ~2GB disk space
- Internet connection (to auto-download VS Code ARM)

### Installation

```bash
# 1. Clone this repository
git clone https://github.com/YOUR_USERNAME/windsurf-arm-builder
cd windsurf-arm-builder

# 2. Run the installer
bash windsurf-arm-installer.sh

# 3. Follow the prompts:
#    - Choose output directory (default: ~/apps/windsurf-arm-current)
#    - Provide path to your Windsurf x64 tarball
#    - Script will auto-download matching VS Code ARM version
#    - Press Enter to install ARM language server
#    - Choose GPU mode (option 1 recommended)

# 4. Launch Windsurf
windsurf --foreground
```

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Windsurf x64 Tarball (official)                            │
│  ├── Windsurf-specific resources (JS, CSS, HTML)            │
│  ├── Windsurf extension with Cascade AI                     │
│  └── x64 binaries (NOT used - replaced with ARM)            │
└─────────────────────────────────────────────────────────────┘
                        ↓
                   EXTRACT & OVERLAY
                        ↓
┌─────────────────────────────────────────────────────────────┐
│  VS Code ARM64 Base (auto-downloaded from Microsoft)        │
│  ├── ARM64 Electron binaries                                │
│  ├── ARM64 Chrome/Chromium                                  │
│  └── ARM64 Node.js runtime                                  │
└─────────────────────────────────────────────────────────────┘
                        ↓
                    COMBINE WITH
                        ↓
┌─────────────────────────────────────────────────────────────┐
│  Codeium ARM Language Server (from GitHub)                  │
│  └── Public Codeium ARM LS (NOT Windsurf custom LS)         │
└─────────────────────────────────────────────────────────────┘
                        ↓
                      RESULT
                        ↓
┌─────────────────────────────────────────────────────────────┐
│  Working Windsurf ARM Installation                          │
│  ✅ Cascade AI chat                                         │
│  ✅ Code editing & autocomplete                             │
│  ✅ Terminal integration                                    │
│  ✅ Native ARM performance                                  │
│  ❌ @file feature (see Limitations)                         │
└─────────────────────────────────────────────────────────────┘
```

### What Gets Downloaded

1. **VS Code ARM64** (~120MB compressed)
   - Auto-detects required version from Windsurf tarball
   - Downloads from: `https://update.code.visualstudio.com/{VERSION}/linux-arm64/stable`
   - Provides ARM binaries for Electron, Chromium, Node.js

2. **Codeium ARM Language Server** (~30MB)
   - Auto-detects version from Windsurf extension metadata
   - Downloads from: `https://github.com/Exafunction/codeium/releases/`
   - Public ARM language server (not Windsurf's custom version)

3. **fd helper** (~1.5MB)
   - Fast file finder for ARM
   - Downloads from: `https://github.com/sharkdp/fd/releases/`

### What Gets Copied

From the **Windsurf x64 tarball** you provide:
- `resources/app/out/` - Windsurf application code (JS, CSS)
- `resources/app/extensions/windsurf/` - Cascade AI extension
  - All `.js`, `.json`, `.mjs`, `.html`, `.txt` files
  - Including `cascade-panel.html` (critical for Cascade UI)
  - Extension assets, schemas, configurations
- Product metadata and branding
- Application resources (icons, licenses, etc.)

From **VS Code ARM**:
- All ARM64 binaries
- Electron framework
- Chrome sandbox
- Node.js runtime

---

## What Works ✅

### Core Features
- ✅ **Cascade AI Chat** - Full conversational AI functionality
- ✅ **Code Editing** - All VS Code editing features
- ✅ **Autocomplete** - Code completion working
- ✅ **Terminal Integration** - Embedded terminal works
- ✅ **Language Server** - Native ARM LS fully functional
- ✅ **Extensions** - VS Code extensions compatible
- ✅ **Syntax Highlighting** - All languages supported
- ✅ **Git Integration** - Source control working
- ✅ **Debugger** - Standard VS Code debugging
- ✅ **File Explorer** - Workspace navigation
- ✅ **Search/Replace** - Find in files working

### Performance
- ✅ **Native ARM Performance** - No emulation overhead
- ✅ **Fast Startup** - Native binaries throughout
- ✅ **Low Memory Usage** - Efficient ARM execution

---

## Known Limitations ❌

### @file Feature Does NOT Work

**Status**: ❌ **Not working**  
**Severity**: Medium (most features still work)

#### The Problem

When you type `@file` in Cascade chat:
- Returns nothing / empty results
- Browser DevTools console shows: `404 Not Found` for endpoint `/exa.language_server_pb.LanguageServerService/GetCodeMapsForRepos`

#### Root Cause

Windsurf ships with a **custom language server** that includes proprietary endpoints not available in the public Codeium language server:

```bash
# Windsurf x64 custom LS has the endpoint (78 occurrences)
strings language_server_linux_x64 | grep -c "GetCodeMapsForRepos"
# Output: 78

# Public Codeium ARM LS does NOT have it
strings language_server_linux_arm | grep -c "GetCodeMapsForRepos"
# Output: 0
```

**The @file feature requires**:
- `GetCodeMapsForRepos` endpoint
- Custom code indexing logic
- Proprietary file context retrieval

**Public Codeium LS** (what we use for ARM) **does not include these**.

#### Why We Can't Fix It

We investigated **three potential solutions**, all failed:

##### ❌ Option 1: Use x64 LS via QEMU Emulation
**Attempted**: Install x64 Windsurf LS and run via `qemu-x86_64-static`  
**Failed**: x64 LS requires x86-64 system libraries:
```
qemu-x86_64-static: Could not open '/lib64/ld-linux-x86-64.so.2': No such file or directory
```
Installing these would require `multiarch` setup (risky, could break ARM packages).

##### ❌ Option 2: Extract from macOS ARM Build
**Attempted**: Extract language server from Windsurf macOS ARM `.dmg`  
**Discovery**: **Windsurf DOES ship ARM LS for macOS!**
```bash
# macOS ARM LS exists and has GetCodeMapsForRepos!
file language_server_macos_arm
# Output: Mach-O 64-bit arm64 executable

strings language_server_macos_arm | grep -c "GetCodeMapsForRepos"
# Output: 78  ✅ It has the endpoint!

du -h language_server_macos_arm
# Output: 176M
```

**BUT**: macOS binaries use **Mach-O format**, not **Linux ELF format**. Won't run on Linux even though it's ARM64.

##### ❌ Option 3: Extract from Windows ARM Build
**Attempted**: Extract from Windows ARM `.exe` installer  
**Failed**: Windows PE format, incompatible with Linux

#### The Evidence: Windsurf CAN Support Linux ARM

**We have proof that Windsurf already supports ARM**:

1. ✅ macOS ARM version exists (`Windsurf-darwin-arm64-1.12.21.dmg`)
2. ✅ macOS ARM LS is 176M with all custom endpoints
3. ✅ macOS ARM LS has `GetCodeMapsForRepos` (78 occurrences)
4. ✅ Same ARM64 architecture as Linux

**What this means**:
- Windsurf **already has the ARM code** (macOS proves it)
- They just need to **compile for Linux** (same code, different target)
- This is a **business/product decision**, not a technical limitation

#### Impact

**What doesn't work**:
- `@file` command returns nothing
- Code map features unavailable
- File context retrieval missing

**What still works**:
- Cascade chat (without @file)
- Code editing and autocomplete
- Most Windsurf features
- Terminal integration (but see Terminal Output issue below)
- Extensions

#### Workaround

**None available**. This requires Windsurf to publish a Linux ARM language server.

**Recommendation**: Use this ARM build for development work. Contact Windsurf to request Linux ARM support (show them the macOS ARM evidence).

### Model Switching Snaps Back

**Status**: ⚠️ **Known issue**  
**Severity**: Low (workaround: switch again)  
**Affects**: Both official x64 AND this ARM build

#### The Problem

When switching AI models in Cascade:
- Selection sometimes "snaps back" to previous model
- Need to click/switch multiple times
- Eventually sticks after 2-3 attempts

#### Root Cause

**This is an upstream Windsurf bug**, not specific to ARM builds:
- Occurs on official x64 Windsurf too
- Likely related to UI state management
- Not caused by missing language server endpoints

#### Impact

Minor annoyance, doesn't affect functionality once model is selected.

### Terminal Output Not Visible to AI Agent

**Status**: ⚠️ **Suspected issue**  
**Severity**: Medium (affects agent's ability to see command results)  
**Likely Cause**: Missing language server endpoints

#### The Problem

When Cascade AI runs terminal commands:
- Commands execute successfully
- But agent may not see the output in real-time
- Agent might say "command completed" without showing results
- Output exists in terminal but not streamed to agent

#### Suspected Root Cause

**Likely related to missing LS endpoints**:
- Custom Windsurf LS may have terminal output streaming endpoints
- Public Codeium ARM LS lacks these endpoints
- Similar to @file issue (missing `GetCodeMapsForRepos`)
- No concrete evidence yet, needs more investigation

#### Current Status

**Needs investigation**:
- Not confirmed if this is ARM-specific
- Might affect official builds too
- Could be reactive streaming implementation
- Separate from @file issue but similar cause (missing endpoints)

#### Workaround

**Use foreground launch mode** to see terminal output yourself:
```bash
windsurf --foreground
```

This lets you manually verify command output even if agent doesn't see it.

---

## Technical Details

### File Structure

```
~/apps/windsurf-arm-current/
├── windsurf                      # Main executable (ARM)
├── chrome-sandbox                # Chrome sandbox (setuid root)
├── resources/
│   └── app/
│       ├── out/                  # Windsurf JS overlays (from x64 tarball)
│       ├── node_modules.asar     # Dependencies
│       ├── product.json          # Windsurf branding
│       └── extensions/
│           └── windsurf/
│               ├── bin/
│               │   ├── language_server_linux_arm  # Codeium ARM LS
│               │   └── fd                         # ARM fd helper
│               ├── dist/         # Extension bundle
│               ├── out/          # Extension output
│               ├── assets/       # Extension assets
│               └── cascade-panel.html  # Cascade UI
└── data/
    ├── userdata/                 # User settings
    │   └── User/
    │       └── settings.json
    └── extensions/               # User-installed extensions
```

### Version Detection

The script automatically detects the required VS Code version:

1. Reads `product.json` from Windsurf tarball
2. Extracts `commit` hash
3. Queries VS Code versions API: `https://raw.githubusercontent.com/Microsoft/vscode/main/build/lib/electron.ts`
4. Finds matching VS Code version for that commit
5. Downloads exact matching VS Code ARM64 build

This ensures **perfect compatibility** between Windsurf resources and VS Code base.

---

## Troubleshooting

### Windsurf Won't Start

```bash
# Launch in foreground to see errors
windsurf --foreground

# Check if chrome-sandbox has correct permissions
ls -l ~/apps/windsurf-arm-current/chrome-sandbox
# Should show: -rwsr-xr-x root root

# If not, reinstall and enter sudo password when prompted
```

### Language Server Not Connecting

```bash
# Check if LS process is running
ps aux | grep language_server

# Verify LS binary is ARM
file ~/apps/windsurf-arm-current/resources/app/extensions/windsurf/bin/language_server_linux_arm
# Should show: ELF 64-bit LSB executable, ARM aarch64
```

### Cascade Panel Doesn't Load

This was fixed in this build. If you still see issues:
- Check that `cascade-panel.html` exists:
  ```bash
  ls -lh ~/apps/windsurf-arm-current/resources/app/extensions/windsurf/cascade-panel.html
  ```
- If missing, the extraction failed. Re-run the installer.

### @file Returns Nothing

**This is expected behavior**. See "Known Limitations" section above.

---

## Comparison with Official Builds

| Feature | Official x64 | This ARM Build |
|---------|--------------|----------------|
| Cascade Chat | ✅ | ✅ |
| Code Editing | ✅ | ✅ |
| Autocomplete | ✅ | ✅ |
| Terminal | ✅ | ✅ |
| @file feature | ✅ | ❌ |
| GetCodeMapsForRepos | ✅ | ❌ |
| Performance | Fast | Fast (native ARM) |
| Stability | Stable | Experimental |

---

## Call to Action

### For Windsurf/Codeium

**We have evidence that Linux ARM support may be trivial to add**:

1. You already ship **macOS ARM** with custom language server (176M)
2. macOS ARM LS has all proprietary endpoints (`GetCodeMapsForRepos`, etc.)
3. Same ARM64 architecture as Linux ARM
4. Just needs recompilation for Linux (ELF instead of Mach-O)

**Request**: Please publish a **Linux ARM language server** with the same custom endpoints as macOS ARM.

This would:
- Enable @file feature and some other important Windsurf functionality on ARM Linux
- Complete ARM support across platforms
- Help growing ARM server/desktop market (AWS Graviton, Oracle Cloud Ampere, Raspberry Pi, etc.)

### For Community

If you benefit from this project:
- ⭐ Star this repository
- 📢 Share with others using ARM Linux
- 🔧 Submit improvements/fork it.
- 📝 Contact Windsurf requesting Linux ARM support

---

## Credits

### Original Creator
**[@rodriguezst](https://github.com/rodriguezst)** - [windsurf-arm](https://github.com/rodriguezst/windsurf-arm)

The original idea and approach for building Windsurf on ARM Linux. His Nix-based solution demonstrated that overlaying Windsurf JavaScript resources onto VS Code ARM creates a working installation:

```bash
# His core insight (from his Nix flake)
cp -R $windsurfSrc/resources/app/out $vscodeSrc/resources/app/
```

This repository provides a **standalone bash installer** implementation of the same concept, with additional features:
- No Nix dependency (works on any Linux ARM system)
- Interactive installation with auto-detection
- Comprehensive documentation of limitations
- Investigation of @file feature and ARM language server availability

**Original work**: [github.com/rodriguezst/windsurf-arm](https://github.com/rodriguezst/windsurf-arm)

### Components
- **Windsurf IDE**: [Codeium](https://windsurf.ai/)
- **VS Code**: [Microsoft](https://code.visualstudio.com/)
- **Codeium Language Server**: [Exafunction](https://github.com/Exafunction/codeium)

### Community
Thanks to everyone testing, providing feedback, and advocating for official ARM support!

---

## License

This is an installation script, not a fork of Windsurf. It downloads and assembles official components:
- Windsurf resources (official tarball - your license)
- VS Code ARM (Microsoft - MIT License)
- Codeium LS (Apache 2.0 License)

The script itself is provided as-is for educational purposes.

---

## FAQ

### Is this official?
No, this is a **community project**. Windsurf does not officially support ARM Linux today (October 2025).

### Is it safe?
The script only downloads from official sources (Microsoft, Codeium GitHub) and uses the Windsurf tarball you provide. Review the script before running.

### Will @file and other and other buggy features work?
A lot depends on the custom Linux ARM language server. We've proven it's technically feasible (macOS ARM exists). There may be unrelated bugs in this workaround, fork it and fix them if you want!

### Can I use this for production?
This is **experimental/community work**. It works for basic development but has known issues:
- @file doesn't work
- Model switching can be buggy
- Terminal output visibility issues
- Maybe other stuff!

**Use at your own risk**. For production, consider official x64 Windsurf.


### Can I help?
Yes! Test it, report issues, improve the script, fork it, and **contact Windsurf** requesting Linux ARM support.

---

## Version History

This repository represents a **community/experimental** approach to running Windsurf on ARM Linux. Key work done:

- ✅ Solved missing `cascade-panel.html` issue
- ✅ Complete file patterns for extension copying
- ✅ Direct language server integration
- ✅ Investigated @file limitation thoroughly
- ✅ Discovered macOS ARM LS as proof of feasibility
- ✅ Removed experimental QEMU approach (too complex)
- ⚠️ Known issues documented honestly (not production-ready)

---

🚀 **Hoping Windsurf will make this unnecessary by supporting ARM Linux officially.** 👀 
