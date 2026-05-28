#!/usr/bin/env bash
# Verify that the CMake build matches the autotools build byte-for-byte
# (for symbols & program outputs). Returns 0 if CMake covers everything
# autotools produces.
#
# Usage:
#   ./verify_build.sh <autotools_build_dir> <cmake_build_dir>

set -e

AUTOTOOLS="${1:-$(pwd)/build}"
CMAKE_DIR="${2:-$(pwd)/cmake_build}"

PASS=0
FAIL=0
report() {
    local result=$1
    local message=$2
    if [ "$result" = "PASS" ]; then
        echo "  [PASS] $message"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $message"
        FAIL=$((FAIL + 1))
    fi
}

echo "==================================================================="
echo "  Verifying CMake build matches autotools build"
echo "  Autotools: $AUTOTOOLS"
echo "  CMake:     $CMAKE_DIR"
echo "==================================================================="
echo

# --- TEST 1: every autotools static library is also built by CMake -------
# Only compare libraries CMake is *supposed* to build, the core (Base + src)
# plus the FTI libs that landed in the PoC's scope. FQHE/Spin/QuantumDots
# are not yet ported (deliberate, see README "What's deliberately out of scope").
echo "[1] Static library coverage (CMake PoC scope: Base + src + FTI)"
IN_SCOPE_DIRS="Base/src src FTI/src"
for autotools_lib in $(find "$AUTOTOOLS" -name "*.a" | sort); do
    # Skip libraries from out-of-scope modules
    rel=$(realpath --relative-to="$AUTOTOOLS" "$autotools_lib")
    in_scope=0
    for d in $IN_SCOPE_DIRS; do
        if [[ "$rel" == "$d"/* ]]; then
            in_scope=1
            break
        fi
    done
    if [ "$in_scope" = "0" ]; then continue; fi

    libname=$(basename "$autotools_lib")
    cmake_lib=$(find "$CMAKE_DIR" -name "$libname" | head -1)
    if [ -n "$cmake_lib" ]; then
        report PASS "CMake produces $libname"
    else
        report FAIL "CMake missing $libname"
    fi
done
echo

# --- TEST 2: same symbol count in matching libraries ---------------------
echo "[2] Symbol count parity (sampled libraries)"
for libname in libMatrix.a libVector.a libArchitecture.a libLanczosAlgorithm.a libHamiltonian.a libHilbertSpace.a; do
    a_lib=$(find "$AUTOTOOLS" -name "$libname" | head -1)
    c_lib=$(find "$CMAKE_DIR" -name "$libname" | head -1)
    if [ -n "$a_lib" ] && [ -n "$c_lib" ]; then
        # `grep -c` exits non-zero on zero matches; under `set -e` this kills the
        # script. Wrap in `|| true` so a library with no text symbols just reports 0.
        a_count=$(nm "$a_lib" 2>/dev/null | grep -c ' T ' || true)
        c_count=$(nm "$c_lib" 2>/dev/null | grep -c ' T ' || true)
        if [ "$a_count" = "$c_count" ]; then
            report PASS "$libname: $a_count text symbols in both builds"
        else
            report FAIL "$libname: autotools=$a_count cmake=$c_count"
        fi
    fi
done
echo

# --- TEST 3: each autotools binary in src/Programs has a CMake counterpart
echo "[3] Generic program coverage"
for bin in $(ls "$AUTOTOOLS/src/Programs/" 2>/dev/null | grep -v -E '\.|Makefile'); do
    if [ -f "$CMAKE_DIR/src/Programs/$bin" ]; then
        report PASS "CMake produces $bin"
    else
        report FAIL "CMake missing $bin"
    fi
done
echo

# --- TEST 4: TestDiagHamConf produces identical output --------------------
echo "[4] Runtime output identity"
if [ -x "$AUTOTOOLS/src/Programs/TestDiagHamConf" ] && [ -x "$CMAKE_DIR/src/Programs/TestDiagHamConf" ]; then
    a_out=$("$AUTOTOOLS/src/Programs/TestDiagHamConf" 2>&1)
    c_out=$("$CMAKE_DIR/src/Programs/TestDiagHamConf" 2>&1)
    if [ "$a_out" = "$c_out" ]; then
        report PASS "TestDiagHamConf output identical between builds"
    else
        report FAIL "TestDiagHamConf output differs"
        echo "    --- diff ---"
        diff <(echo "$a_out") <(echo "$c_out") | head -10 | sed 's/^/    /'
    fi
fi

echo
echo "==================================================================="
echo "  RESULTS:  $PASS passed,  $FAIL failed"
echo "==================================================================="

[ "$FAIL" = "0" ]
