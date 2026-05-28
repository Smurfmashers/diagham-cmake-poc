#!/usr/bin/env python3
"""
extract_autotools.py: generate CMakeLists.txt files from upstream Makefile.am

This is part of the DiagHam CMake migration proof-of-concept. It reads every
Makefile.am in the upstream source tree, extracts the libFOO_a_SOURCES lists,
and emits the equivalent CMakeLists.txt files.

The point of a generator script (rather than hand-writing every CMakeLists.txt)
is reproducibility: the migration is not a one-shot manual port. Whenever
upstream changes a Makefile.am (e.g., adds new source files), re-running this
script gives an updated CMake snapshot. The CMake migration thus stays in sync
with upstream until it is adopted there.

Usage:
    python3 scripts_cmake/extract_autotools.py [SOURCE_ROOT]

If SOURCE_ROOT is omitted, defaults to the parent directory of this script.

Limitations:
- Handles core (Base/src + src) plus FQHE and FTI. Spin and QuantumDots
  follow the same pattern and are left as future work.
- Strips comment lines before parsing (autotools allows `# foo.cc` to
  comment out a source from a SOURCES list, e.g. LaguerreFunction.cc in
  src/MathTools/Makefile.am).
- Programs/ subdirectories use file-glob auto-discovery in CMake rather
  than explicit enumeration; the diagham_add_programs_in_directory()
  helper finds every .cc in the directory at build time.
"""
import re
import sys
from pathlib import Path


def parse_makefile_am(path: Path) -> tuple:
    """Extract library targets and SUBDIRS list from a Makefile.am.

    Returns (libs_dict, subdirs_list) where libs_dict maps library name -> [sources]
    and subdirs_list is the list of subdirectories declared via SUBDIRS=.
    """
    text = path.read_text()
    # Strip comment lines so commented-out sources don't get picked up
    text = re.sub(r'#[^\n]*', '', text)
    libs = {}
    subdirs = []

    # Parse the SUBDIRS=X Y Z line (horizontal whitespace only; \s* would match
    # newlines and consume the next statement).
    sm = re.search(r'^SUBDIRS[ \t]*=[ \t]*(.*?)$', text, re.MULTILINE)
    if sm:
        raw = sm.group(1).replace('\\\n', ' ').strip()
        subdirs = [s for s in raw.split() if s]

    m = re.search(r'noinst_LIBRARIES\s*=\s*(.+)', text)
    if not m:
        return libs, subdirs

    for lib in m.group(1).strip().split():
        if not (lib.startswith('lib') and lib.endswith('.a')):
            continue
        target = lib[3:-2]
        var = f'lib{target}_a_SOURCES'
        # Match until the next variable assignment or EOF
        pat = re.compile(r'^' + re.escape(var) + r'\s*=\s*(.+?)(?=^[A-Za-z_]+\s*=|\Z)',
                         re.MULTILINE | re.DOTALL)
        match = pat.search(text)
        if not match:
            continue
        # Join continued lines, then split
        raw = match.group(1).replace('\\\n', ' ').replace('\\', ' ')
        sources = [s.strip() for s in raw.split() if s.strip().endswith('.cc')]
        # De-duplicate while preserving order. Some upstream Makefile.am files
        # list the same source twice (e.g. TightBindingModelOFLSquareLattice.cc
        # appears twice in FTI/src/Tools/FTITightBinding/Makefile.am); a repeated
        # source in a CMake target is an error, so collapse to first occurrence.
        seen = set()
        deduped = []
        for s in sources:
            if s not in seen:
                seen.add(s)
                deduped.append(s)
        libs[target] = deduped

    # Orphaned-source recovery.
    #
    # Some upstream Makefile.am files omit a .cc that nonetheless has a matching
    # .h and is required by programs in the tree. The canonical example is
    # FTI/src/Tools/FTITightBinding/TightBindingModelDiceLattice.cc, which is
    # never listed in libFTITightBinding_a_SOURCES even though its sibling
    # TightBindingModelChern2DiceLattice.cc is, and FCIDiceLatticeModel.cc
    # depends on it. The autotools build silently never compiled it (so the
    # program never linked); CMake would inherit the same gap.
    #
    # IMPORTANT: not every orphaned .cc is an accidental omission. Some are
    # deliberately excluded because they no longer compile (e.g.
    # TightBindingModelKapitMueller.cc references an old HofstadterSquare API
    # with members Range/NbrLayers/EncodeQuantumNumber that no longer exist).
    # We therefore recover only from an explicit allowlist of files that have
    # been verified to compile and are needed by a program. A blanket "add
    # any orphan with a header" rule would pull in known-broken files.
    ORPHAN_RECOVERY_ALLOWLIST = {
        'TightBindingModelDiceLattice.cc',
        'ParticleOnLatticeDiceLatticeSingleBandHamiltonian.cc',
        'ParticleOnLatticeDiceLatticeTwoBandHamiltonian.cc',
    }
    if len(libs) == 1:
        (only_target,) = list(libs.keys())
        listed = set(libs[only_target])
        directory = path.parent
        for cc in sorted(directory.glob('*.cc')):
            if cc.name in listed:
                continue
            if cc.name not in ORPHAN_RECOVERY_ALLOWLIST:
                continue
            header = cc.with_suffix('.h')
            if header.exists():
                libs[only_target].append(cc.name)

    return libs, subdirs


def emit_cmakelists(directory: Path, libs: dict, subdirs: list,
                    is_programs: bool = False) -> str:
    """Emit the text of a CMakeLists.txt for one directory."""
    rel = directory
    lines = [f'# Auto-generated CMakeLists.txt for {rel}',
             '# Regenerate with: python3 scripts_cmake/extract_autotools.py',
             '']

    # Preserve the order from autotools SUBDIRS, which is meaningful: DiagHam
    # puts Programs/ near the end so all libraries are built first.
    for sd in subdirs:
        lines.append(f'add_subdirectory({sd})')

    if subdirs and libs:
        lines.append('')

    for target, sources in libs.items():
        lines.append(f'diagham_add_library({target}')
        lines.append('    SOURCES')
        for s in sources:
            lines.append(f'        {s}')
        lines.append(')')
        lines.append('')

    if is_programs:
        lines.append('# Auto-discover every .cc as a separate executable.')
        lines.append('diagham_add_programs_in_directory()')

    return '\n'.join(lines)


def main(source_root: Path):
    in_scope = ('Base/src', 'src', 'FQHE/src', 'FTI/src')

    # Walk every Makefile.am in scope, recording both library targets and SUBDIRS
    # children per directory. Both are required: SUBDIRS-only intermediates (with
    # no libraries of their own) still need to appear in the generated CMake tree.
    libs_by_dir = {}
    subdirs_by_dir = {}
    for makefile in source_root.rglob('Makefile.am'):
        rel = makefile.relative_to(source_root)
        rel_dir = str(rel.parent)
        if not any(rel_dir == p or rel_dir.startswith(p + '/') for p in in_scope):
            continue
        libs, subdirs = parse_makefile_am(makefile)
        if libs:
            libs_by_dir[rel_dir] = libs
        if subdirs:
            subdirs_by_dir[rel_dir] = subdirs

    # Build the directory tree from SUBDIRS declarations (the authoritative source)
    # plus any directories that declare libraries directly.
    directories = set(libs_by_dir.keys()) | set(subdirs_by_dir.keys()) | set(in_scope)

    # Also include any directory referenced by a SUBDIRS in scope. Autotools
    # treats `SUBDIRS=Foo` as "Foo exists and is valid", so CMake must too,
    # even when Foo itself is empty (has no libraries and no further subdirs).
    for parent, children in list(subdirs_by_dir.items()):
        for child in children:
            child_path = str(Path(parent) / child)
            if (source_root / child_path).is_dir():
                directories.add(child_path)

    # Use SUBDIRS as the source of truth for parent->child relationships.
    direct_children = {d: list(subdirs_by_dir.get(d, [])) for d in directories}

    # Emit
    n_written = 0
    for d in sorted(directories):
        # Preserve SUBDIRS declaration order; only deduplicate.
        seen = set()
        children = []
        for c in direct_children.get(d, []):
            if c not in seen:
                children.append(c)
                seen.add(c)
        # A directory is a "programs leaf" if it sits under any /Programs/
        # ancestor, declares no libraries, and contains .cc files. This covers
        # src/Programs/, FTI/src/Programs/HubbardModels/, FTI/src/Programs/FCI/
        # and FTI/src/Programs/FTI/ uniformly, without hardcoding their names.
        is_programs_leaf = False
        path_parts = d.split('/')
        if 'Programs' in path_parts and d not in libs_by_dir:
            cc_files = list((source_root / d).glob('*.cc'))
            if cc_files:
                is_programs_leaf = True
        libs = libs_by_dir.get(d, {})

        content = emit_cmakelists(d, libs, children, is_programs=is_programs_leaf)
        out_path = source_root / d / 'CMakeLists.txt'
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(content)
        n_written += 1

    print(f'Wrote {n_written} CMakeLists.txt files under {source_root}')


if __name__ == '__main__':
    if len(sys.argv) > 1:
        root = Path(sys.argv[1])
    else:
        root = Path(__file__).resolve().parent.parent
    main(root)
