#!/usr/bin/env python3
"""Tests usr/local/lib/ollie/windows-layout on many made-up drives.

Each trial makes a sparse disk image with a random GPT layout (Ollie OS's part
among data parts, old Windows Setup parts, parts that look like Windows, gaps),
then runs wl_plan the way windows-plan does (with a made-up file system for
Ollie OS's part) and checks:
  - the part table is valid (sgdisk -v),
  - no part except Ollie OS's own (and old Windows Setup parts) was touched,
  - Ollie OS's part keeps its start, and its file system still fits in it,
  - exactly one Windows Setup part exists: 10 GiB, on a 1 MiB boundary,
  - the biggest free block is at least as big as asked for (GB),
  - when it cannot be done, it says so and Ollie OS's part is not changed.
A second kind of trial deletes some Windows parts first (wl_delete_parts) and
checks the room they left is used without making Ollie OS's part smaller.

   windows-layout-test.py [TRIALS] [SEED]      (needs sgdisk, sfdisk, bash)
"""
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "..", "profile", "airootfs", "usr", "local", "lib", "ollie", "windows-layout")
GiB = 1 << 30
MiB = 1 << 20
SS = 512
TYPE_ESP = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
TYPE_LINUX = "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
TYPE_DATA = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
TYPE_MSR = "E3C9E316-0B5C-4DB8-817D-F92DF00215AE"
TYPE_REC = "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC"


def run(*args, check=True, **kw):
    return subprocess.run(args, check=check, capture_output=True, text=True, **kw)


def table(img):
    """{num: dict(start, size, type, name, uuid)} from sfdisk -d."""
    out = run("sfdisk", "-d", img).stdout
    parts = {}
    for line in out.splitlines():
        m = re.match(re.escape(img) + r"(\d+) : (.*)", line)
        if not m:
            continue
        f = m.group(2)
        g = lambda k: (re.search(k + r"= *([^,]+)", f) or [None, None])[1]
        parts[int(m.group(1))] = dict(
            start=int(g("start")), size=int(g("size")), type=g("type").upper(),
            uuid=g("uuid"), name=(re.search(r'name="([^"]*)"', f) or [None, ""])[1])
    return parts


def free_blocks(img):
    out = run("sfdisk", "-F", img).stdout
    return [(int(a), int(c)) for a, b, c in re.findall(r"^ *(\d+) +(\d+) +(\d+) ", out, re.M)]


def make_disk(rng, path):
    """A random layout. Returns (parts spec list, root number, disk bytes)."""
    disk = rng.choice([64, 128, 256, 500, 1000, 2000, 4500]) * GiB
    with open(path, "wb") as f:
        f.truncate(disk)
    run("sgdisk", "-o", path)
    specs = []
    esp = rng.choice([256 * MiB, 512 * MiB, GiB])
    specs.append(("esp", esp, TYPE_ESP, "OLLIE_BOOT"))
    root = int(rng.uniform(0.25, 0.8) * disk) // MiB * MiB
    root = max(root, 45 * GiB)
    specs.append(("root", root, TYPE_LINUX, "OLLIE_ROOT"))
    for _ in range(rng.choice([0, 0, 1, 1, 2, 3])):
        specs.append(("data", rng.choice([10 * GiB, 40 * GiB, 100 * GiB, 5 * GiB, 500 * MiB]), TYPE_DATA, rng.choice(["", "file mail", "Basic data partition", "games"])))
    for _ in range(rng.choice([0, 0, 0, 1, 2])):
        specs.append(("oldsetup", 10 * GiB, TYPE_DATA, "OLLIE_WINSETUP"))
    if rng.random() < 0.3:
        specs.append(("msr", 16 * MiB, TYPE_MSR, "Microsoft reserved partition"))
        specs.append(("win", rng.choice([40, 60, 100]) * GiB, TYPE_DATA, "Basic data partition"))
        specs.append(("rec", 800 * MiB, TYPE_REC, ""))
    # the ESP first, the rest in random order (so parts come after Ollie OS's)
    rest = specs[1:]
    rng.shuffle(rest)
    specs = [specs[0]] + rest
    # In half of the trials Ollie OS's part fills what the others leave (a
    # drive set up by the Installer / Drive Writer, with no free room).
    gaps = [rng.choice([0, 0, 0, MiB, GiB, 5 * GiB, 20 * GiB]) if sp[0] != "esp" else 0 for sp in specs]
    if rng.random() < 0.5:
        others = sum(sp[1] for sp in specs if sp[0] != "root") + sum(gaps) + (len(specs) + 3) * MiB
        fill = (disk - others) // MiB * MiB - rng.choice([0, 0, MiB, GiB, 30 * GiB]) // MiB * MiB
        if fill < 45 * GiB:
            return None
        specs = [(k, (fill if k == "root" else z), t, nm) for k, z, t, nm in specs]
    # lay them out with the gaps; drop parts that do not fit
    cursor = MiB
    placed = []
    end_limit = disk - 2 * MiB
    for (kind, size, ptype, name), gap in zip(specs, gaps):
        start = (cursor + gap + MiB - 1) // MiB * MiB
        if start + size > end_limit:
            if kind == "root":  # shrink the root to what is left
                size = (end_limit - start) // MiB * MiB
                if size < 40 * GiB:
                    return None
            else:
                continue
        placed.append((kind, start, size, ptype, name))
        cursor = start + size
    num = 0
    rootnum = None
    args = ["sgdisk"]
    for kind, start, size, ptype, name in placed:
        num += 1
        args += ["-n", f"{num}:{start // SS}:{(start + size) // SS - 1}", "-t", f"{num}:{ptype}"]
        if name:
            args += ["-c", f"{num}:{name}"]
        if kind == "root":
            rootnum = num
    if rootnum is None:
        return None
    run(*args, path)
    return placed, rootnum, disk


BASH_HEAD = r'''
set -u
. "%s"
FS_SHRUNK=0
wl_hook_fs_shrink() { # the made-up file system: size FS_GIB, used USED_GIB
    local g="$1"
    if (( FS_GIB - USED_GIB < g + 8 )); then echo "not enough free room in the file system" >&2; return 1; fi
    echo "FS_SHRUNK=$g"
    return 0
}
'''


def plan(img, rootnum, gb, fs_gib, used_gib):
    script = BASH_HEAD % LIB + f'wl_plan "{img}" {rootnum} {gb}; rc=$?; echo "MODE=${{WL_MODE:-}} SHRINK_PART=${{WL_SHRINK_PART_GIB:-0}} SHRINK_FS=${{WL_SHRINK_FS_GIB:-0}} WS=${{WL_WS_START:-}}"; exit $rc'
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, FS_GIB=str(fs_gib), USED_GIB=str(used_gib)))
    info = dict(re.findall(r"(\w+)=(\S*)", r.stdout.splitlines()[-1])) if r.stdout.strip() else {}
    return r.returncode, info, r.stdout + r.stderr


def check(img, before, rootnum, gb, fs_gib, rc, info, log, disk):
    after = table(img)
    problems = []
    v = run("sgdisk", "-v", img, check=False).stdout
    if "No problems found" not in v:
        problems.append("sgdisk -v: " + v.strip().replace("\n", " | ")[:200])
    old_setup = {n for n, p in before.items() if p["name"] == "OLLIE_WINSETUP"}
    # nothing else touched
    for n, p in before.items():
        if n in old_setup or n == rootnum:
            continue
        if after.get(n) != p:
            problems.append(f"part {n} changed: {p} -> {after.get(n)}")
    if rc != 0:
        # not possible: Ollie OS's part must be as it was
        if after.get(rootnum) != before[rootnum]:
            problems.append("failed, but Ollie OS's part changed")
        return problems
    root_b, root_a = before[rootnum], after.get(rootnum)
    if root_a is None or root_a["start"] != root_b["start"] or root_a["type"] != root_b["type"] or root_a["uuid"] != root_b["uuid"]:
        problems.append(f"Ollie OS's part moved or lost: {root_b} -> {root_a}")
    else:
        mode = info.get("MODE")
        shrink_part = int(info.get("SHRINK_PART", "0"))
        shrink_fs = int(info.get("SHRINK_FS", "0"))
        if mode == "free" and root_a["size"] != root_b["size"]:
            problems.append("free mode but Ollie OS's part changed")
        if mode == "shrink":
            if root_b["size"] - root_a["size"] != shrink_part * GiB // SS:
                problems.append("shrink amount does not match")
            fs_after = fs_gib - shrink_fs
            if fs_after * GiB + GiB > root_a["size"] * SS:
                problems.append("the file system would not fit in the shrunk part")
            if shrink_fs != shrink_part + 1:
                problems.append("fs shrink must be the part shrink + 1 GiB")
    setups = [p for p in after.values() if p["name"] == "OLLIE_WINSETUP"]
    if len(setups) != 1:
        problems.append(f"{len(setups)} Windows Setup parts")
    else:
        s = setups[0]
        if s["size"] * SS != 10 * GiB:
            problems.append("Windows Setup part is not 10 GiB")
        if (s["start"] * SS) % MiB:
            problems.append("Windows Setup part is not on a 1 MiB boundary")
    blocks = free_blocks(img)
    biggest = max((b[1] for b in blocks), default=0) * SS
    if biggest < gb * GiB:
        problems.append(f"biggest free block {biggest / GiB:.1f} GiB < {gb} GiB")
    return problems


def trial_plan(rng, n, tmp, verbose):
    img = os.path.join(tmp, f"d{n}.img")
    made = make_disk(rng, img)
    if made is None:
        os.remove(img)
        return None
    placed, rootnum, disk = made
    before = table(img)
    root = before[rootnum]
    root_gib = root["size"] * SS // GiB
    fs_gib = root_gib  # the file system fills its part
    used_gib = int(fs_gib * rng.uniform(0.02, 0.9))
    gb = rng.choice([32, 40, 64, 64, 100, 128, 200])
    rc, info, log = plan(img, rootnum, gb, fs_gib, used_gib)
    problems = check(img, before, rootnum, gb, fs_gib, rc, info, log, disk)
    # when it failed, that must be because there really is not room
    if rc != 0 and not problems:
        free_fs = fs_gib - used_gib
        blocks = free_blocks(img)
        biggest = max((b[1] for b in blocks), default=0) * SS // GiB
        if biggest >= gb + 11 or free_fs >= (gb + 12 + 8 + 12):
            problems.append(f"gave up although there was room (free block {biggest} GiB, fs free {free_fs} GiB): {log.strip()[-160:]}")
    os.remove(img)
    return rc == 0, info.get("MODE", ""), problems, log


def trial_delete(rng, n, tmp, verbose):
    """Windows parts deleted first: their room is used, Ollie OS's part stays."""
    img = os.path.join(tmp, f"w{n}.img")
    disk = rng.choice([256, 500, 1000, 2000]) * GiB
    with open(img, "wb") as f:
        f.truncate(disk)
    run("sgdisk", "-o", img)
    cursor = MiB
    layout = []
    root = rng.choice([60, 100, 200]) * GiB
    items = [("esp", 512 * MiB, TYPE_ESP, "OLLIE_BOOT"), ("root", root, TYPE_LINUX, "OLLIE_ROOT"),
             ("msr", 16 * MiB, TYPE_MSR, "Microsoft reserved partition"),
             ("win", rng.choice([100, 150]) * GiB, TYPE_DATA, "Basic data partition"),
             ("rec", 800 * MiB, TYPE_REC, ""), ("data", 20 * GiB, TYPE_DATA, "file mail")]
    first = items[:2]
    rest = items[2:]
    rng.shuffle(rest)
    num = 0
    rootnum = None
    args = ["sgdisk"]
    for kind, size, ptype, name in first + rest:
        start = (cursor + MiB - 1) // MiB * MiB
        if start + size > disk - 2 * MiB:
            continue
        num += 1
        args += ["-n", f"{num}:{start // SS}:{(start + size) // SS - 1}", "-t", f"{num}:{ptype}"]
        if name:
            args += ["-c", f"{num}:{name}"]
        layout.append((num, kind))
        if kind == "root":
            rootnum = num
        cursor = start + size
    run(*args, img)
    before = table(img)
    to_delete = [num for num, kind in layout if kind in ("msr", "win", "rec")]
    shell = BASH_HEAD % LIB + f'wl_delete_parts "{img}" {rootnum} {" ".join(map(str, to_delete))}'
    r = subprocess.run(["bash", "-c", shell], capture_output=True, text=True, env=dict(os.environ, FS_GIB="1", USED_GIB="0"))
    problems = []
    if r.returncode != 0:
        problems.append("delete failed: " + r.stderr)
    mid = table(img)
    for k in to_delete:
        if k in mid:
            problems.append(f"part {k} still there")
    for k, p in before.items():
        if k not in to_delete and mid.get(k) != p:
            problems.append(f"part {k} changed by the delete")
    # never delete Ollie OS's own
    r2 = subprocess.run(["bash", "-c", BASH_HEAD % LIB + f'wl_delete_parts "{img}" {rootnum} {rootnum}'], capture_output=True, text=True)
    if r2.returncode == 0 or rootnum not in table(img):
        problems.append("Ollie OS's own part was deletable")
    gb = rng.choice([32, 64])
    fs_gib = root // GiB
    rc, info, log = plan(img, rootnum, gb, fs_gib, int(fs_gib * 0.1))
    after = table(img)
    problems += check(img, mid, rootnum, gb, fs_gib, rc, info, log, disk)
    if rc != 0:
        problems.append("no room made after deleting Windows: " + log.strip()[-200:])
    elif info.get("MODE") != "free" and max((b[1] for b in free_blocks(img)), default=0) * SS < gb * GiB:
        problems.append("not enough room")
    os.remove(img)
    return rc == 0, info.get("MODE", ""), problems, log


def trial_grow(rng, n, tmp, verbose):
    """wl_grow_root: Ollie OS's part gets the free room right after it, nothing else changes."""
    img = os.path.join(tmp, f"g{n}.img")
    made = make_disk(rng, img)
    if made is None:
        os.remove(img)
        return None
    placed, rootnum, disk = made
    before = table(img)
    root = before[rootnum]
    end = root["start"] + root["size"]
    adj = next((b for b in free_blocks(img) if 0 <= b[0] - end <= MiB // SS), None)
    shell = BASH_HEAD % LIB + f'wl_grow_root "{img}" {rootnum}; echo "GROWN=${{WL_GROWN_GIB:-0}}"'
    r = subprocess.run(["bash", "-c", shell], capture_output=True, text=True, env=dict(os.environ, FS_GIB="1", USED_GIB="0"))
    after = table(img)
    problems = []
    if r.returncode != 0:
        problems.append("grow failed: " + (r.stdout + r.stderr)[-200:])
    if "No problems found" not in run("sgdisk", "-v", img, check=False).stdout:
        problems.append("sgdisk -v is not happy")
    for k, p in before.items():
        if k != rootnum and after.get(k) != p:
            problems.append(f"part {k} changed")
    ra = after.get(rootnum)
    if ra is None or ra["start"] != root["start"] or ra["uuid"] != root["uuid"]:
        problems.append("Ollie OS's part moved or lost")
    elif adj is None:
        if ra["size"] != root["size"]:
            problems.append("grew although no free room follows it")
    else:
        want_end = (adj[0] + adj[1]) // (MiB // SS) * (MiB // SS)
        if ra["start"] + ra["size"] != want_end:
            problems.append(f"did not fill the free room: ends at {ra['start'] + ra['size']}, wanted {want_end}")
        if free_blocks(img) and any(0 <= b[0] - (ra["start"] + ra["size"]) <= MiB // SS and b[1] * SS >= 2 * MiB for b in free_blocks(img)):
            problems.append("free room is still right after it")
    os.remove(img)
    return True, "grow", problems, r.stdout


def one(args):
    kind, seed, n, tmp = args
    rng = random.Random(seed * 100003 + n * 2 + (1 if kind == "delete" else 0))
    if kind == "plan":
        return kind, n, trial_plan(rng, n, tmp, False)
    if kind == "grow":
        return kind, n, trial_grow(rng, n, tmp, False)
    return kind, n, trial_delete(rng, n, tmp, False)


def main():
    from concurrent.futures import ThreadPoolExecutor
    trials = int(sys.argv[1]) if len(sys.argv) > 1 else 150
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else random.randrange(1 << 30)
    print(f"windows-layout test: {trials} plan + {max(20, trials // 5)} delete + {max(20, trials // 4)} grow trials, seed {seed}")
    for tool in ("sgdisk", "sfdisk", "bash"):
        if not shutil.which(tool):
            print(f"SKIP: {tool} is not here")
            return 0
    tmp = tempfile.mkdtemp(prefix="wltest-")
    failed = done = ok = unable = 0
    modes = {"free": 0, "shrink": 0}
    jobs = ([("plan", seed, n, tmp) for n in range(trials)] + [("delete", seed, n, tmp) for n in range(max(20, trials // 5))]
            + [("grow", seed, n, tmp) for n in range(max(20, trials // 4))])
    try:
        with ThreadPoolExecutor(max_workers=24) as ex:
            for kind, n, res in ex.map(one, jobs):
                if res is None:
                    continue
                success, mode, problems, log = res
                done += 1
                if problems:
                    failed += 1
                    print(f"FAIL {kind} trial {n}: " + "; ".join(problems))
                elif success:
                    ok += 1
                    modes[mode] = modes.get(mode, 0) + 1
                else:
                    unable += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"{done} trials: {ok} made room ({modes}), {unable} correctly said there is no room, {failed} FAILED")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
