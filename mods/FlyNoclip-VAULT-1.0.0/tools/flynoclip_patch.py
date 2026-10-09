#!/usr/bin/env python3
"""FlyNoclip-VAULT 1.0.0 — single-line additive patcher for shared Survival files.

Why this exists: Survival has no mod loader. A new part must be listed in
shapesets.json, its recipe must sit in a craftbot recipe file, and it must be
unlocked in RecipeManager.lua. Those files are already shipped by ItemPump-VAULT.
Shipping full copies ("MapViewer-style overlay") would fight ItemPump in Vortex.
So this tool adds exactly ONE line per file to whatever is live right now, and
can take exactly that line back out. Nothing else in those files changes.

Usage (game must be fully closed):
  python flynoclip_patch.py check  --game "F:\\...\\Scrap Mechanic"
  python flynoclip_patch.py add    --game "F:\\...\\Scrap Mechanic"
  python flynoclip_patch.py remove --game "F:\\...\\Scrap Mechanic"
Options:
  --dry-run               compute + verify, write nothing
  --allow-md5-mismatch    proceed even if ItemPump.lua / ItemFilter.lua MD5 differ from expected
Exit code 0 = OK, non-zero = aborted (nothing written on abort).
"""
import argparse, hashlib, json, os, re, shutil, sys

UUID = "36d35110-c0db-4564-910d-1f221ce85943"
TAG = "FlyNoclip-VAULT"
BAK = ".bak-flynoclip-1.0.0"
ITEMPUMP_UUID = "b7e4a201-9c58-4f2d-8a61-0d3e5f7a9124"
METAL1 = "8aedf6c2-94e1-4506-89d4-a0227c552f1e"  # same ingredient ItemPump uses

SS = "Survival/Objects/Database/shapesets.json"
RM = "Survival/Scripts/game/managers/RecipeManager.lua"
CB = "Survival/CraftingRecipes/craftbot/craftbot_small_pipes.json"
INV = "Survival/Gui/Language/English/inventoryDescriptions.json"
UNIQUE = [
    "Survival/Objects/Database/ShapeSets/flynoclip_vault.shapeset",
    "Survival/Scripts/game/interactables/FlyNoclipVault.lua",
]
GUARDS = {  # read-only; never opened for write
    "Survival/Scripts/game/interactables/ItemPump.lua": "9171e16adb9e5cfd8a119cf93e47caa4",
    "Survival/Scripts/game/interactables/ItemFilter.lua": "cd864de817040f1227c957b84913b589",  # ItemFilter id-fix 2026-10-09
}

SS_ENTRY = '"$SURVIVAL_DATA/Objects/Database/ShapeSets/flynoclip_vault.shapeset",'
RM_ENTRY = 'sm.uuid.new( "%s" ), -- obj_interactive_flynoclip_vault (%s)' % (UUID, TAG)
CB_OBJ = {"itemId": UUID, "quantity": 1, "craftTime": 2,
          "ingredientList": [{"quantity": 3, "itemId": METAL1}]}
CB_ENTRY = json.dumps(CB_OBJ, ensure_ascii=False) + ","
INV_VAL = {"title": "Fly Beacon",
           "description": "Place it, press E: Off -> Fly -> Fly + Noclip (push into a wall with Shift). U/Tinker: speed. Double-tap Ctrl anywhere: off.",
           "keywords": ["fly", "flight", "noclip", "ucus", "beacon"]}
INV_ENTRY = json.dumps(UUID) + ": " + json.dumps(INV_VAL, ensure_ascii=False) + ","


class Abort(Exception):
    pass


def md5(path):
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()


def split(raw):
    bom = raw.startswith(b"\xef\xbb\xbf")
    body = raw[3:] if bom else raw
    text = body.decode("utf-8")
    nl = "\r\n" if "\r\n" in text else "\n"
    return bom, nl, text


def join(bom, text):
    data = text.encode("utf-8")
    return (b"\xef\xbb\xbf" + data) if bom else data


def jparse(text):
    stripped = "\n".join("" if ln.strip().startswith("//") else ln for ln in text.splitlines())
    return json.loads(stripped)


def indent_of(line):
    return line[: len(line) - len(line.lstrip())]


def lines_of(text, nl):
    return text.split(nl)


# ---------- per-file insert planners (return new text) ----------

def plan_ss(text, nl):
    ls = lines_of(text, nl)
    entry_idx = [i for i, l in enumerate(ls) if re.match(r'^\s*"\$[A-Z_]+/.*\.shapeset"\s*,?\s*$', l)]
    if not entry_idx:
        raise Abort("shapesets.json: no shapeset entries found")
    pump = [i for i in entry_idx if "itempump.shapeset" in ls[i]]
    if pump and ls[pump[0]].rstrip().endswith(","):
        at = pump[0] + 1
        ind = indent_of(ls[pump[0]])
    else:
        at = entry_idx[0]  # before first entry; our line ends with ',' so list stays valid
        ind = indent_of(ls[at])
    ls.insert(at, ind + SS_ENTRY)
    return nl.join(ls)


def plan_rm(text, nl):
    ls = lines_of(text, nl)
    start = next((i for i, l in enumerate(ls) if re.match(r"^\s*local\s+DefaultUnlockedItems\s*=\s*\{\s*$", l)), None)
    if start is None:
        raise Abort("RecipeManager.lua: 'local DefaultUnlockedItems = {' not found")
    end = next((i for i in range(start + 1, len(ls)) if re.match(r"^\}\s*$", ls[i])), None)
    if end is None:
        raise Abort("RecipeManager.lua: end of DefaultUnlockedItems not found")
    pump = next((i for i in range(start + 1, end) if ITEMPUMP_UUID in ls[i]), None)
    if pump is not None:
        at, ind = pump + 1, indent_of(ls[pump]) or "\t"
    else:
        at, ind = start + 1, "\t"
    ls.insert(at, ind + RM_ENTRY)
    return nl.join(ls)


def plan_cb(text, nl):
    ls = lines_of(text, nl)
    at = next((i for i, l in enumerate(ls) if l.strip() == "["), None)
    if at is None:
        raise Abort("craftbot_small_pipes.json: opening '[' line not found")
    ind = "\t"
    nxt = next((l for l in ls[at + 1:] if l.strip()), "")
    if nxt.strip().startswith("{"):
        ind = indent_of(nxt) or "\t"
    ls.insert(at + 1, ind + CB_ENTRY)
    return nl.join(ls)


def plan_inv(text, nl):
    ls = lines_of(text, nl)
    at = next((i for i, l in enumerate(ls) if l.strip() == "{"), None)
    if at is None:
        raise Abort("inventoryDescriptions.json: opening '{' line not found")
    nxt = next((l for l in ls[at + 1:] if l.strip()), "")
    ind = indent_of(nxt) or "\t"
    ls.insert(at + 1, ind + INV_ENTRY)
    return nl.join(ls)


# ---------- verifiers ----------

def verify_ss(old, new):
    a, b = jparse(old)["shapeSetList"], jparse(new)["shapeSetList"]
    ours = SS_ENTRY.rstrip(",").strip('"')
    if ours in a:
        raise Abort("shapesets.json: already had entry")
    if [x for x in b if x != ours] != a or b.count(ours) != 1:
        raise Abort("shapesets.json: verify failed")


def verify_cb(old, new):
    a, b = jparse(old), jparse(new)
    if [x for x in b if x.get("itemId") != UUID] != a or sum(1 for x in b if x.get("itemId") == UUID) != 1:
        raise Abort("craftbot_small_pipes.json: verify failed")


def verify_inv(old, new):
    a, b = jparse(old), jparse(new)
    bb = dict(b)
    bb.pop(UUID, None)
    if UUID in a or bb != a or UUID not in b:
        raise Abort("inventoryDescriptions.json: verify failed")


def verify_rm(old, new, nl):
    a, b = lines_of(old, nl), lines_of(new, nl)
    if len(b) != len(a) + 1:
        raise Abort("RecipeManager.lua: line count verify failed")
    if [l for l in b if UUID not in l] != a or sum(1 for l in b if UUID in l) != 1:
        raise Abort("RecipeManager.lua: verify failed")
    i = next(i for i, l in enumerate(b) if UUID in l)
    start = max(j for j in range(i) if "DefaultUnlockedItems" in b[j] and "{" in b[j])
    if any(re.match(r"^\}\s*$", b[j]) for j in range(start, i)):
        raise Abort("RecipeManager.lua: entry not inside DefaultUnlockedItems")


def verify_removed(rel, old, new, nl):
    a, b = lines_of(old, nl), lines_of(new, nl)
    if [l for l in a if mark(rel) not in l] != b or len(a) - len(b) != 1:
        raise Abort(rel + ": remove verify failed (expected exactly one marked line)")
    if rel.endswith(".json"):
        jparse(new)  # must still parse


def mark(rel):
    """Text that identifies our single line in a given shared file."""
    return "flynoclip_vault.shapeset" if rel == SS else UUID


PLANS = {SS: (plan_ss, verify_ss), RM: (plan_rm, None), CB: (plan_cb, verify_cb), INV: (plan_inv, verify_inv)}


def write_inplace(path, data):
    # r+b + truncate keeps the same file (preserves Vortex hardlinks if any)
    with open(path, "r+b") as f:
        f.seek(0)
        f.write(data)
        f.truncate()


def guards(game, allow):
    out = {}
    for rel, exp in GUARDS.items():
        p = os.path.join(game, rel)
        got = md5(p) if os.path.exists(p) else None
        out[rel] = got
        status = "OK" if got == exp else ("MISSING" if got is None else "MISMATCH")
        print("GUARD %-8s %s %s (expected %s)" % (status, rel, got, exp))
        if status != "OK" and not allow:
            raise Abort("guard %s for %s; rerun with --allow-md5-mismatch only if intended" % (status, rel))
    return out


def cmd_check(game):
    for rel in UNIQUE:
        p = os.path.join(game, rel)
        print("UNIQUE  %-7s %s" % ("present" if os.path.exists(p) else "absent", rel))
    for rel in PLANS:
        p = os.path.join(game, rel)
        if not os.path.exists(p):
            print("SHARED  MISSING %s" % rel)
            continue
        _, nl, t = split(open(p, "rb").read())
        n = sum(1 for l in lines_of(t, nl) if mark(rel) in l)
        print("SHARED  %s lines=%d %s" % ("patched" if n else "clean", n, rel))


def cmd_add(game, dry, allow):
    before = guards(game, allow)
    for rel in UNIQUE:
        if not os.path.exists(os.path.join(game, rel)):
            raise Abort("unique file missing in game dir (copy it first): " + rel)
    plans = []
    for rel, (plan, verify) in PLANS.items():
        p = os.path.join(game, rel)
        if not os.path.exists(p):
            raise Abort("shared file missing: " + rel)
        raw = open(p, "rb").read()
        bom, nl, old = split(raw)
        if mark(rel) in old:
            print("SKIP already patched: " + rel)
            continue
        new = plan(old, nl)
        if verify is None:
            verify_rm(old, new, nl)
        else:
            verify(old, new)
        plans.append((rel, p, raw, join(bom, new)))
        print("PLAN +1 line: " + rel)
    if dry:
        print("DRY RUN: nothing written")
        return
    for rel, p, raw, data in plans:  # all verified before any write
        b = p + BAK
        if not os.path.exists(b):
            shutil.copy2(p, b)
            print("BACKUP " + b)
    for rel, p, raw, data in plans:
        write_inplace(p, data)
        print("WROTE  %s (%d -> %d bytes)" % (rel, len(raw), len(data)))
    after = guards(game, True)
    if after != before:
        raise Abort("guard files changed during patch (should be impossible)")
    print("ADD OK")


def cmd_remove(game, dry, allow):
    before = guards(game, True)
    plans = []
    for rel in PLANS:
        p = os.path.join(game, rel)
        if not os.path.exists(p):
            print("SKIP missing: " + rel)
            continue
        raw = open(p, "rb").read()
        bom, nl, old = split(raw)
        if mark(rel) not in old:
            print("SKIP clean: " + rel)
            continue
        new = nl.join(l for l in lines_of(old, nl) if mark(rel) not in l)
        verify_removed(rel, old, new, nl)
        plans.append((rel, p, raw, join(bom, new)))
        print("PLAN -%d line(s): %s" % (len(lines_of(old, nl)) - len(lines_of(new, nl)), rel))
    if dry:
        print("DRY RUN: nothing written")
        return
    for rel, p, raw, data in plans:
        write_inplace(p, data)
        print("WROTE  %s (%d -> %d bytes)" % (rel, len(raw), len(data)))
    if guards(game, True) != before:
        raise Abort("guard files changed during remove (should be impossible)")
    print("REMOVE OK (unique files are deleted by the PS1 after this)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["check", "add", "remove"])
    ap.add_argument("--game", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--allow-md5-mismatch", action="store_true")
    a = ap.parse_args()
    try:
        if a.command == "check":
            cmd_check(a.game)
        elif a.command == "add":
            cmd_add(a.game, a.dry_run, a.allow_md5_mismatch)
        else:
            cmd_remove(a.game, a.dry_run, a.allow_md5_mismatch)
    except Abort as e:
        print("ABORT: %s" % e)
        sys.exit(2)


if __name__ == "__main__":
    main()
