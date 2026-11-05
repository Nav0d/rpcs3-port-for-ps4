#!/bin/bash
# BUILDING.md steps 4-7 on a macOS host (Apple Silicon or Intel), with the same PowerShell scripts as on Windows.
#
# Needs: Homebrew llvm@18 (18.1.8, clang + ld.lld, the version llvm-mingw 20240619 ships), cmake, ninja, python@3.12+,
# PowerShell 7 (pwsh) and Rosetta 2 on Apple Silicon (the SDK's macOS packaging tools are x86_64).
#
#   SDK=<OpenOrbis PS4Toolchain>  ps4-port/build-macos.sh        (run from rpcs3-ps4/)
#
# Optional: LLVM_BIN (default: Homebrew llvm@18 bin), PWSH (default: pwsh on PATH), JOBS (default: all cores),
# STEPS (default "4 5 6 7").
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
: "${SDK:?set SDK to the OpenOrbis PS4Toolchain directory}"
LLVM_BIN="${LLVM_BIN:-$(brew --prefix llvm@18)/bin}"
PWSH="${PWSH:-$(command -v pwsh || true)}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
STEPS="${STEPS:-4 5 6 7}"
PYTHON="$(command -v python3)"

[ -x "$PWSH" ] || { echo "PowerShell 7 (pwsh) not found; set PWSH" >&2; exit 1; }
for tool in clang clang++ ld.lld llvm-ar llvm-nm llvm-objdump llvm-objcopy; do
    [ -x "$LLVM_BIN/$tool" ] || { echo "missing $LLVM_BIN/$tool (brew install llvm@18)" >&2; exit 1; }
done
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 12))' || { echo "Python 3.12+ needed first on PATH (brew install python)" >&2; exit 1; }
command -v cmake >/dev/null && command -v ninja >/dev/null || { echo "brew install cmake ninja" >&2; exit 1; }
# ffmpeg.cmake starts build-ffmpeg.ps1 through pwsh found on PATH
export PATH="$(dirname "$PWSH"):$PATH"

VERSION="$(sed -n 's/.*ps4_build_version\[\] *= *"\([0-9]*\.[0-9][0-9]\)".*/\1/p' rpcs3/util/ps4_build_version.hpp)"
echo "RPCS3 PS4 $VERSION on $(uname -m) macOS: SDK=$SDK LLVM=$LLVM_BIN ($("$LLVM_BIN/clang" --version | head -1)) jobs=$JOBS"

for step in $STEPS; do
    case "$step" in
    4)  echo "== step 4: Abseil (GNU make: the system make)"
        "$PWSH" -NoProfile -File ps4-port/prepare-abseil.ps1 ;;
    5)  echo "== step 5: console LLVM"
        mkdir -p ps4-port/.build-native-package
        "$PWSH" -NoProfile -File ps4-port/build-llvm.ps1 -Sdk "$SDK" -CompilerBin "$LLVM_BIN" -Jobs "$JOBS" -Python "$PYTHON" ;;
    6)  echo "== step 6: configure and build the native ELF"
        cmake -S . -B ps4-port/.build-abi -G Ninja \
            "-DRPCS3_PS4_PORT=ON" \
            "-DCMAKE_TOOLCHAIN_FILE=ps4-port/toolchain.cmake" \
            "-DRPCS3_PS4_SDK=$SDK" "-DRPCS3_PS4_LLVM_BIN=$LLVM_BIN" \
            "-DRPCS3_PS4_WITH_LLVM=ON"
        cmake --build ps4-port/.build-abi --target rpcs3_ps4_elf -j "$JOBS" ;;
    7)  echo "== step 7: EBOOT and PKG"
        "$PWSH" -NoProfile -File ps4-port/package-native.ps1 -Sdk "$SDK" -LlvmTools "$LLVM_BIN" -Version "$VERSION" -Python "$PYTHON"
        ls -l ps4-port/dist ;;
    *)  echo "unknown step $step" >&2; exit 1 ;;
    esac
done
