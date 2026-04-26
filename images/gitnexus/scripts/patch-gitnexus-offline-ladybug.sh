#!/usr/bin/env bash
# images/gitnexus/scripts/patch-gitnexus-offline-ladybug.sh
# Patches lbug-adapter.js for local-first, offline-aware LadybugDB extension loading.
#
# LOAD EXTENSION 'name' requires the extension to be registered in the catalog
# via a prior INSTALL (which downloads from the internet).  LOAD EXTENSION
# '/absolute/path/to/file.lbug_extension' bypasses that catalog check entirely
# and loads directly from the local file.  The patch uses the path-based form
# first, searching the staged extension directories.  INSTALL+LOAD remains as
# an online fallback for non-offline runs.
#
# Fails the build loudly if any required patch target is not found.

set -euo pipefail

LBUG_ADAPTER="/usr/local/lib/node_modules/gitnexus/dist/core/lbug/lbug-adapter.js"

if [[ ! -f "${LBUG_ADAPTER}" ]]; then
    printf 'PATCH ERROR: target not found: %s\n' "${LBUG_ADAPTER}" >&2
    printf 'PATCH ERROR: gitnexus npm package may have changed its dist layout\n' >&2
    exit 1
fi

cp "${LBUG_ADAPTER}" "${LBUG_ADAPTER}.orig"

python3 - "${LBUG_ADAPTER}" <<'PYEOF'
import sys

file = sys.argv[1]
with open(file, encoding='utf-8') as f:
    src = f.read()

# ---------------------------------------------------------------------------
# Patch 1: Vector
# Old: single try block goes straight to INSTALL VECTOR (network) then LOAD.
#      LOAD EXTENSION 'name' requires a catalog entry created by INSTALL, so
#      the name-based LOAD alone cannot work offline even with local files.
# New: try LOAD EXTENSION '/absolute/path' first (bypasses catalog check);
#      fall back to INSTALL+LOAD only when not in offline mode.
# ---------------------------------------------------------------------------

VECTOR_OLD = """\
    try {
        await conn.query('INSTALL VECTOR');
        await conn.query('LOAD EXTENSION VECTOR');
        vectorExtensionLoaded = true;
    }
    catch (err) {
        const msg = err?.message || '';
        if (msg.includes('already loaded') ||
            msg.includes('already installed') ||
            msg.includes('already exists')) {
            vectorExtensionLoaded = true;
        }
        else {
            console.error('GitNexus: VECTOR extension load failed:', msg);
        }
    }"""

# fs and path are already imported at the top of lbug-adapter.js.
# The path-based LOAD EXTENSION bypasses the LadybugDB catalog registration
# check that causes "Binder exception: has not been installed".
VECTOR_NEW = """\
    // SPT offline patch: path-based load bypasses catalog registration requirement.
    // LOAD EXTENSION '/path' skips the catalog check; LOAD EXTENSION 'name'
    // requires a prior INSTALL to register in the catalog.
    const spt_offline = process.env.GITNEXUS_OFFLINE === '1' || process.env.SPT_OFFLINE === '1';
    const spt_home = process.env.HOME || '';
    const spt_extDir = process.env.GITNEXUS_LADYBUG_EXTENSIONS_DIR || '';
    const spt_tryVecLoad = async (fp) => {
        try {
            await fs.access(fp);
            await conn.query(`LOAD EXTENSION '${fp}'`);
            vectorExtensionLoaded = true;
            return true;
        }
        catch { return false; }
    };
    // Try staged cache directories (populated by run-gitnexus wrapper before launch)
    for (const spt_base of [
        spt_home && path.join(spt_home, '.ladybug', 'extensions'),
        spt_home && path.join(spt_home, '.kuzu', 'extensions'),
        spt_home && path.join(spt_home, '.lbug', 'extensions'),
    ].filter(Boolean)) {
        if (await spt_tryVecLoad(path.join(spt_base, 'vector', 'libvector.lbug_extension'))) return;
        if (await spt_tryVecLoad(path.join(spt_base, 'libvector.lbug_extension'))) return;
    }
    // Recursive search of the mounted extensions volume
    if (spt_extDir) {
        const spt_findVec = async (d) => {
            try {
                for (const e of await fs.readdir(d, { withFileTypes: true })) {
                    const spt_fp = path.join(d, e.name);
                    if (e.isFile() && e.name === 'libvector.lbug_extension') {
                        if (await spt_tryVecLoad(spt_fp)) return true;
                    }
                    if (e.isDirectory()) { if (await spt_findVec(spt_fp)) return true; }
                }
            } catch {}
            return false;
        };
        if (await spt_findVec(spt_extDir)) return;
    }
    if (spt_offline) {
        console.error('GitNexus: VECTOR local extension load failed in offline mode: extension not found or not loadable from staged paths');
        return;
    }
    // Online fallback: original INSTALL then LOAD
    try {
        await conn.query('INSTALL vector');
        await conn.query('LOAD EXTENSION vector');
        vectorExtensionLoaded = true;
    }
    catch (err) {
        const msg = err?.message || '';
        if (msg.includes('already loaded') ||
            msg.includes('already installed') ||
            msg.includes('already exists')) {
            vectorExtensionLoaded = true;
        }
        else {
            console.error('GitNexus: VECTOR extension load failed:', msg);
        }
    }"""

if VECTOR_OLD not in src:
    print('PATCH ERROR: vector try/catch block not found in ' + file, file=sys.stderr)
    print('  Expected to find (first few chars): ' + repr(VECTOR_OLD[:60]), file=sys.stderr)
    sys.exit(1)

src = src.replace(VECTOR_OLD, VECTOR_NEW, 1)
print('[PATCH] Vector path-based offline patch applied.')

# ---------------------------------------------------------------------------
# Patch 2: FTS
# Old: outer catch has no variable and goes straight into INSTALL fts fallback.
# New: outer catch adds offline guard before the INSTALL fts fallback.
#      FTS appears to be bundled in LadybugDB and loads successfully with
#      LOAD EXTENSION 'fts' (name-based) without a prior INSTALL.  This patch
#      is a safety net: if the name-based LOAD ever fails in offline mode, we
#      stop instead of attempting a network INSTALL.
# ---------------------------------------------------------------------------

FTS_CATCH_OLD = """\
    catch {
        // Fall back to install + load (requires network)
        try {
            await c.query('INSTALL fts');
            await c.query('LOAD EXTENSION fts');
            return markLoaded();
        }
        catch (err) {
            const msg = err?.message || '';
            if (msg.includes('already loaded') ||
                msg.includes('already installed') ||
                msg.includes('already exists')) {
                return markLoaded();
            }
            console.error('GitNexus: FTS extension load failed:', msg);
            return false;
        }
    }"""

FTS_CATCH_NEW = """\
    catch (spt_ftsLoadErr) {
        const spt_ftsMsg = spt_ftsLoadErr?.message || '';
        const spt_ftsOffline = process.env.GITNEXUS_OFFLINE === '1' || process.env.SPT_OFFLINE === '1';
        if (spt_ftsOffline) {
            console.error('GitNexus: FTS local extension load failed in offline mode:', spt_ftsMsg);
            return false;
        }
        // Fall back to install + load (requires network)
        try {
            await c.query('INSTALL fts');
            await c.query('LOAD EXTENSION fts');
            return markLoaded();
        }
        catch (err) {
            const msg = err?.message || '';
            if (msg.includes('already loaded') ||
                msg.includes('already installed') ||
                msg.includes('already exists')) {
                return markLoaded();
            }
            console.error('GitNexus: FTS extension load failed:', msg);
            return false;
        }
    }"""

if FTS_CATCH_OLD not in src:
    print('PATCH ERROR: FTS catch block not found in ' + file, file=sys.stderr)
    print('  Expected to find (first few chars): ' + repr(FTS_CATCH_OLD[:60]), file=sys.stderr)
    sys.exit(1)

src = src.replace(FTS_CATCH_OLD, FTS_CATCH_NEW, 1)
print('[PATCH] FTS offline guard patch applied.')

# ---------------------------------------------------------------------------
# Verify both patches landed
# ---------------------------------------------------------------------------

if "await conn.query('INSTALL VECTOR')" in src:
    print('PATCH ERROR: INSTALL VECTOR still present after vector patch', file=sys.stderr)
    sys.exit(1)

if 'spt_tryVecLoad' not in src:
    print('PATCH ERROR: vector path-based loader not found after patch', file=sys.stderr)
    sys.exit(1)

if 'spt_ftsOffline' not in src:
    print('PATCH ERROR: FTS offline guard not found after FTS patch', file=sys.stderr)
    sys.exit(1)

with open(file, 'w', encoding='utf-8') as f:
    f.write(src)

print('[PATCH OK] Offline LadybugDB extension patch written to ' + file)
PYEOF

printf '[PATCH OK] gitnexus offline LadybugDB extension patch complete.\n'
