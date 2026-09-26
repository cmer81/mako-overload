# MAKO OVERLOAD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the MAKO OVERLOAD stage (instability gauge, player-tracking Sephiroth lasers, Mako surges, 150 s overload escape, Sephiroth last stand) to `ze_ffvii_mako_reactor_v5_3` on the CS:S **test server only**.

**Architecture:** Pure gameplay rules live in `mako_overload/logic.nut` (no engine calls, unit-tested with a local Squirrel interpreter). Engine glue lives in `mako_overload/overload.nut`, loaded by a `logic_script` added by the stripper; it stays inert until the stage relay calls `Overload_Start()`. The stripper section wires map events (doors, bridge, core, boss, escape, ending) to the script and reuses entities already proven in ZEDDYS cmer / RMZS cmer.

**Tech Stack:** Stripper:Source (SourceMod edition) config, CS:S VScript (Squirrel, TF2-style API), AdminRoom config, Python 3 (stripper checker), Squirrel 3.2 `sq` interpreter (local tests only).

**Spec:** `docs/superpowers/specs/2026-09-26-mako-overload-design.md`

## Global Constraints

- Map: `ze_ffvii_mako_reactor_v5_3`; humans = team **3**, zombies = team **2**.
- All in-game text in **English**.
- Stage ids: LevelCounter **case 17**, admin room button hammerid **100012** at `-4472 -3333 1396`, AdminRoom stage `"Mako Overload"` with triggers `14`, `overload`, `makooverload`.
- Gauge: +1 % every **4 s**; bonds: superior door +5, bridge +5, core +10, Bahamut entry +10, Bahamut killed +15; capped at **95** before escape; **100** at escape start.
- Tiers: STABLE 0–33 (surge 90 s / laser 20 s), UNSTABLE 34–66 (60 s / 15 s), CRITICAL 67–95 (40 s / 10 s), OVERLOAD 100 (laser 5 s).
- Respites: first **45 s**; **25 s** from the elevator (`ascensort`) first start; **10 s** after `bahamut_entry`.
- Lasers: telegraph **1.5 s**, lethal to humans only (existing `humanos` filter), spawned **400–700 units** behind the main cluster (radius **600**), fallback ±90°, retry in **3 s** when no room.
- Surges: 2 s alert, never the same twice in a row; LOW GRAVITY 0.35 for 10 s, BLACKOUT 8 s, BRIDGE FLIP 15 s (no human within **800** of the bridge `-9355 4864`, never during escape), BARRAGE 3 lasers 1.5 s apart, MAKO RAGE ×1.3 speed for 6 s (CRITICAL+).
- Escape: **150 s** (`MakoOverloadEscape` replaces `huida_e`), lasers every 5 s, `explosion_mako_random` every 12 s, no LOW GRAVITY / BLACKOUT.
- Deploy to test server volume `fe4451bc-1b56-46eb-8b64-b717c6ebda8c` only; back up every overwritten file as `*.bak-overload`; one SSH connection per deploy (the host rate-limits SSH).
- Existing stages must not change behaviour.

**Deviations from the spec (to confirm with the user when presenting this plan):**
1. "Bahamut at 50 %" (+10) is replaced by "Bahamut entry" (+10): `math_counter` values are not exposed as a readable netprop, so 50 % cannot be detected reliably.
2. HUD/center texts use ASCII (`MAKO [######----] 62% UNSTABLE`, `!! JUMP !!`, `MAKO SURGE: LOW GRAVITY`, `REACTOR OVERLOAD`) instead of `☢ ⚠ ⚡`, which the CS:S HUD font may render as boxes.
3. The last stand lasts ~16 s (3 waves at 0 / 4.5 / 9 s, each wave = 2 lasers) instead of 10 s, so the waves do not overlap.
4. The BOMB TIMER display (max 2m 25s) starts 5 s after the 150 s escape begins so it matches the remaining time.

## Review Focus

- A laser fired in a tight corridor or at a corner must never spawn inside a wall — the `TraceLine` clearance (≥ 400) and ±90° fallback decide; no shot is better than a broken one.
- A player who dies, respawns or gets infected during LOW GRAVITY or MAKO RAGE must end with normal gravity/speed; the round after an OVERLOAD round must have no residual effect.
- Other stages (Normal … RMZS cmer) must be untouched: the `logic_script` exists every round but must do nothing unless `Overload_Start()` was called.
- Humans split into two groups: the main cluster must be the larger one, never a lone player.
- The escape must still end even if the script errors: `MakoOverloadEscape` → `finalf` is pure stripper and does not depend on the script.

---

## File Structure

| File | Responsibility |
|---|---|
| `cstrike/scripts/vscripts/mako_overload/logic.nut` (create) | Pure rules: tiers, gauge clamp, HUD text, main cluster, shot directions/placement, surge & laser pickers, bridge check. No engine API. |
| `cstrike/scripts/vscripts/mako_overload/overload.nut` (create) | Engine glue: state, think loop, HUD entity, lasers, surges, overload, ending, debug console functions. |
| `tests/overload/test_logic.nut` (create) | Unit tests for `logic.nut`, run with `sq`. |
| `tests/overload/run.sh` (create) | Runs the tests and compiles `overload.nut` (syntax check). |
| `tools/check_stripper.py` (create) | Brace balance, unresolved targets in a stripper section, commas inside `RunScriptCode` parameters. |
| `cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg` (modify) | New `MODE: MAKO OVERLOAD` section, LevelCounter case 17, admin room button. |
| `cstrike/addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg` (copy) | Same file for the SourceMod Stripper plugin. |
| `cstrike/addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg` (modify) | AdminRoom stage 15 "Mako Overload". |

---

### Task 1: Pure rules (`logic.nut`) with local tests

**Files:**
- Create: `cstrike/scripts/vscripts/mako_overload/logic.nut`
- Create: `tests/overload/test_logic.nut`
- Create: `tests/overload/run.sh`

**Interfaces:**
- Produces (root table, used by Task 2):
  - `MOL_TIERS` — array of 4 tables `{ name, surge, laser, color }`
  - `MOL_OFFSETS` — table `{ jump = 36.0, crouch = 66.0 }` (mutable, calibration)
  - `MOL_MAKER_LEAD` — `182.0`
  - `MOL_TierIndex(gauge, overload) -> int 0..3`
  - `MOL_ClampGauge(gauge, overload) -> number`
  - `MOL_HudText(gauge, tierIdx, stabilized) -> string`
  - `MOL_MainCluster(points, radius) -> null | { count, cx, cy, floorZ, dirx, diry }` where `points` = array of `{ x, y, z, vx, vy, yaw }`
  - `MOL_ShotDirections(dirx, diry) -> array of { x, y }` (behind, left, right order)
  - `MOL_LaserPlacement(cluster, d, clear, type) -> null | { x, y, z, yaw, sephx, sephy }`
  - `MOL_SURGES`, `MOL_SurgeByName(name) -> table | null`
  - `MOL_PickSurge(tierIdx, last, escape, bridgeAllowed, randInt) -> string | null`
  - `MOL_PickLaserType(tierIdx, lastType, randInt) -> "jump" | "crouch"`
  - `MOL_IsDoubleShot(tierIdx, rand01) -> bool`
  - `MOL_BridgeAllowed(points, escape) -> bool`

- [ ] **Step 1: Build a local Squirrel interpreter (tests only, not deployed)**

```bash
S=/tmp/claude-1000/-home-cmer-Documents-git-NiDE-mako-v5-extra-stages/bdd48f5d-01ea-4d22-83c7-c18fe93a4163/scratchpad
cd $S && [ -d squirrel ] || git clone -q --depth 1 https://github.com/albertodemichelis/squirrel.git
cd $S/squirrel && make -s 2>&1 | tail -3 && ls bin/sq
```
Expected: `bin/sq` exists.

- [ ] **Step 2: Write the failing tests**

`tests/overload/test_logic.nut`:
```squirrel
local failures = 0, total = 0;
function check(name, cond) {
	total++;
	if (!cond) { failures++; print("FAIL " + name + "\n"); }
}
function near(a, b) { return fabs(a - b) < 0.01; }

dofile("cstrike/scripts/vscripts/mako_overload/logic.nut");

// tiers
check("tier stable", MOL_TierIndex(0, false) == 0);
check("tier stable 33", MOL_TierIndex(33, false) == 0);
check("tier unstable 34", MOL_TierIndex(34, false) == 1);
check("tier critical 67", MOL_TierIndex(67, false) == 2);
check("tier critical 95", MOL_TierIndex(95, false) == 2);
check("tier overload", MOL_TierIndex(10, true) == 3);

// gauge clamp
check("cap 95 before escape", MOL_ClampGauge(120, false) == 95);
check("cap 100 in overload", MOL_ClampGauge(120, true) == 100);
check("no negative", MOL_ClampGauge(-5, false) == 0);

// hud
check("hud text", MOL_HudText(62.7, 1, false) == "MAKO  [######----]  62%  UNSTABLE");
check("hud stabilized", MOL_HudText(100, 3, true) == "MAKO  [##########]  STABILIZED");

// cluster: 3 players together + 1 isolated -> the group of 3 wins
local pts = [
	{ x = 0, y = 0, z = 10, vx = 200, vy = 0, yaw = 0 },
	{ x = 100, y = 0, z = 12, vx = 200, vy = 0, yaw = 0 },
	{ x = 0, y = 100, z = 8, vx = 200, vy = 0, yaw = 0 },
	{ x = 5000, y = 5000, z = 0, vx = 0, vy = 0, yaw = 90 }
];
local c = MOL_MainCluster(pts, 600.0);
check("cluster count", c.count == 3);
check("cluster center x", near(c.cx, 33.33));
check("cluster floor", c.floorZ == 8);
check("cluster dir from velocity", near(c.dirx, 1.0) && near(c.diry, 0.0));
check("no players -> null", MOL_MainCluster([], 600.0) == null);

// standing still -> direction from eye yaw (90 deg = +y)
local still = MOL_MainCluster([{ x = 0, y = 0, z = 0, vx = 0, vy = 0, yaw = 90 }], 600.0);
check("dir from yaw", near(still.dirx, 0.0) && near(still.diry, 1.0));

// shot directions: behind (same as travel dir), then left, then right
local ds = MOL_ShotDirections(1.0, 0.0);
check("3 directions", ds.len() == 3);
check("left", near(ds[1].x, 0.0) && near(ds[1].y, 1.0));
check("right", near(ds[2].x, 0.0) && near(ds[2].y, -1.0));

// placement
check("no room -> null", MOL_LaserPlacement(c, ds[0], 399.0, "jump") == null);
local shot = MOL_LaserPlacement(c, ds[0], 1000.0, "jump");
check("placement max 700 + lead", near(shot.x, c.cx - (700 + MOL_MAKER_LEAD)));
check("placement jump height", near(shot.z, c.floorZ + MOL_OFFSETS.jump));
check("placement yaw", near(shot.yaw, 0.0));
check("sephiroth at laser start", near(shot.sephx, c.cx - 700));
local shot2 = MOL_LaserPlacement(c, ds[0], 500.0, "crouch");
check("placement uses clearance - 32", near(shot2.sephx, c.cx - 468));
check("placement crouch height", near(shot2.z, c.floorZ + MOL_OFFSETS.crouch));

// surge picker (randInt always 0 -> first eligible)
local first = function(n) { return 0; };
check("stable pool starts with lowgrav", MOL_PickSurge(0, null, false, true, first) == "lowgrav");
check("never twice in a row", MOL_PickSurge(0, "lowgrav", false, true, first) == "blackout");
check("rage needs critical", MOL_PickSurge(1, null, false, true, function(n) { return n - 1; }) == "barrage");
check("rage at critical", MOL_PickSurge(2, null, false, true, function(n) { return n - 1; }) == "rage");
check("bridge skipped when not allowed", MOL_PickSurge(1, "blackout", false, false, function(n) { return 1; }) == "barrage");
check("escape: only barrage/rage", MOL_PickSurge(2, null, true, true, first) == "barrage");
check("unknown surge", MOL_SurgeByName("nope") == null);
check("surge label", MOL_SurgeByName("lowgrav").label == "LOW GRAVITY");

// laser type
check("stable = jump", MOL_PickLaserType(0, "jump", function(n) { return 1; }) == "jump");
check("overload alternates", MOL_PickLaserType(3, "jump", first) == "crouch");
check("overload alternates back", MOL_PickLaserType(3, "crouch", first) == "jump");
check("unstable random", MOL_PickLaserType(1, null, function(n) { return 1; }) == "crouch");
check("double only critical", MOL_IsDoubleShot(2, 0.1) && !MOL_IsDoubleShot(1, 0.1) && !MOL_IsDoubleShot(2, 0.5));

// bridge
check("bridge ok far away", MOL_BridgeAllowed([{ x = 0, y = 0, z = 0, vx = 0, vy = 0, yaw = 0 }], false));
check("bridge refused near", !MOL_BridgeAllowed([{ x = -9355, y = 5200, z = 0, vx = 0, vy = 0, yaw = 0 }], false));
check("bridge refused in escape", !MOL_BridgeAllowed([], true));

print(total + " tests, " + failures + " failures\n");
if (failures > 0) throw "tests failed";
```

`tests/overload/run.sh`:
```bash
#!/usr/bin/env bash
# Runs MAKO OVERLOAD logic tests and syntax-checks the engine glue.
set -euo pipefail
cd "$(dirname "$0")/../.."
SQ="${SQ:-/tmp/claude-1000/-home-cmer-Documents-git-NiDE-mako-v5-extra-stages/bdd48f5d-01ea-4d22-83c7-c18fe93a4163/scratchpad/squirrel/bin/sq}"
"$SQ" tests/overload/test_logic.nut
if [ -f cstrike/scripts/vscripts/mako_overload/overload.nut ]; then
	"$SQ" -c -o /dev/null cstrike/scripts/vscripts/mako_overload/overload.nut && echo "overload.nut compiles"
fi
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `chmod +x tests/overload/run.sh && tests/overload/run.sh`
Expected: FAIL (`dofile` cannot open `logic.nut`).

- [ ] **Step 4: Write `logic.nut`**

`cstrike/scripts/vscripts/mako_overload/logic.nut`:
```squirrel
// MAKO OVERLOAD - pure rules (no engine API). Tested locally: tests/overload/run.sh

::MOL_TIERS <- [
	{ name = "STABLE",   surge = 90.0, laser = 20.0, color = "0 255 0" },
	{ name = "UNSTABLE", surge = 60.0, laser = 15.0, color = "255 160 0" },
	{ name = "CRITICAL", surge = 40.0, laser = 10.0, color = "255 0 0" },
	{ name = "OVERLOAD", surge = 0.0,  laser = 5.0,  color = "255 0 255" }
];
::MOL_CAP_BEFORE_ESCAPE <- 95;
// laser height above the group's floor (player origin = feet), calibrated in game
::MOL_OFFSETS <- { jump = 36.0, crouch = 66.0 };
// the laser brush of EX4ZeddysLaserTemp starts 182 units in front of EX4ZeddysLaserMaker
::MOL_MAKER_LEAD <- 182.0;
::MOL_BRIDGE <- { x = -9355.0, y = 4864.0, radius = 800.0 };

::MOL_TierIndex <- function(gauge, overload) {
	if (overload) return 3;
	if (gauge >= 67) return 2;
	if (gauge >= 34) return 1;
	return 0;
}

::MOL_ClampGauge <- function(gauge, overload) {
	local cap = overload ? 100 : MOL_CAP_BEFORE_ESCAPE;
	if (gauge > cap) return cap;
	if (gauge < 0) return 0;
	return gauge;
}

::MOL_HudText <- function(gauge, tierIdx, stabilized) {
	if (stabilized) return "MAKO  [##########]  STABILIZED";
	local g = gauge.tointeger();
	local filled = g / 10;
	local bar = "";
	for (local i = 0; i < 10; i++) bar += (i < filled) ? "#" : "-";
	return "MAKO  [" + bar + "]  " + g + "%  " + MOL_TIERS[tierIdx].name;
}

// points: array of { x, y, z, vx, vy, yaw }. The main cluster is the largest group
// of players within `radius` (2D) and 200 units of height of one of them.
::MOL_MainCluster <- function(points, radius) {
	if (points.len() == 0) return null;
	local r2 = radius * radius, best = null;
	foreach (p in points) {
		local members = [];
		foreach (q in points) {
			local dx = q.x - p.x, dy = q.y - p.y;
			if (dx * dx + dy * dy <= r2 && fabs(q.z - p.z) <= 200) members.push(q);
		}
		if (best == null || members.len() > best.len()) best = members;
	}
	local cx = 0.0, cy = 0.0, vx = 0.0, vy = 0.0, sx = 0.0, sy = 0.0, fz = best[0].z;
	foreach (m in best) {
		cx += m.x; cy += m.y; vx += m.vx; vy += m.vy;
		sx += cos(m.yaw * PI / 180.0); sy += sin(m.yaw * PI / 180.0);
		if (m.z < fz) fz = m.z;
	}
	local n = best.len().tofloat();
	cx /= n; cy /= n; vx /= n; vy /= n;
	local speed = sqrt(vx * vx + vy * vy), dx = 1.0, dy = 0.0;
	if (speed >= 50.0) { dx = vx / speed; dy = vy / speed; }
	else {
		local l = sqrt(sx * sx + sy * sy);
		if (l > 0.001) { dx = sx / l; dy = sy / l; }
	}
	return { count = best.len(), cx = cx, cy = cy, floorZ = fz, dirx = dx, diry = dy };
}

// Direction the laser travels (it comes from behind and sweeps through the group):
// the group's direction first, then 90 degrees left, then 90 degrees right.
::MOL_ShotDirections <- function(dirx, diry) {
	return [ { x = dirx, y = diry }, { x = -diry, y = dirx }, { x = diry, y = -dirx } ];
}

// clear = free distance measured from the group backwards along -d (TraceLine).
::MOL_LaserPlacement <- function(cluster, d, clear, type) {
	if (clear < 400) return null;
	local dist = clear - 32;
	if (dist > 700) dist = 700;
	return {
		x = cluster.cx - d.x * (dist + MOL_MAKER_LEAD),
		y = cluster.cy - d.y * (dist + MOL_MAKER_LEAD),
		z = cluster.floorZ + MOL_OFFSETS[type],
		yaw = atan2(d.y, d.x) * 180.0 / PI,
		sephx = cluster.cx - d.x * dist,
		sephy = cluster.cy - d.y * dist
	};
}

::MOL_SURGES <- [
	{ name = "lowgrav",  label = "LOW GRAVITY", minTier = 0, escapeOk = false },
	{ name = "blackout", label = "BLACKOUT",    minTier = 0, escapeOk = false },
	{ name = "bridge",   label = "BRIDGE FLIP", minTier = 1, escapeOk = false },
	{ name = "barrage",  label = "BARRAGE",     minTier = 1, escapeOk = true },
	{ name = "rage",     label = "MAKO RAGE",   minTier = 2, escapeOk = true }
];

::MOL_SurgeByName <- function(name) {
	foreach (s in MOL_SURGES) if (s.name == name) return s;
	return null;
}

// randInt(n) -> integer in [0, n)
::MOL_PickSurge <- function(tierIdx, last, escape, bridgeAllowed, randInt) {
	local pool = [];
	foreach (s in MOL_SURGES) {
		if (s.minTier > tierIdx || s.name == last) continue;
		if (escape && !s.escapeOk) continue;
		if (s.name == "bridge" && !bridgeAllowed) continue;
		pool.push(s.name);
	}
	if (pool.len() == 0) return null;
	return pool[randInt(pool.len())];
}

::MOL_PickLaserType <- function(tierIdx, lastType, randInt) {
	if (tierIdx == 0) return "jump";
	if (tierIdx == 3) return (lastType == "jump") ? "crouch" : "jump";
	return (randInt(2) == 0) ? "jump" : "crouch";
}

::MOL_IsDoubleShot <- function(tierIdx, rand01) {
	return tierIdx == 2 && rand01 < 0.3;
}

::MOL_BridgeAllowed <- function(points, escape) {
	if (escape) return false;
	local r2 = MOL_BRIDGE.radius * MOL_BRIDGE.radius;
	foreach (p in points) {
		local dx = p.x - MOL_BRIDGE.x, dy = p.y - MOL_BRIDGE.y;
		if (dx * dx + dy * dy < r2) return false;
	}
	return true;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `tests/overload/run.sh`
Expected: `44 tests, 0 failures` (exact count printed by the runner; 0 failures is what matters).

- [ ] **Step 6: Commit**

```bash
git add cstrike/scripts/vscripts/mako_overload/logic.nut tests/overload/test_logic.nut tests/overload/run.sh
git commit -m "feat(overload): pure gameplay rules with local tests"
```

---

### Task 2: Engine glue (`overload.nut`)

**Files:**
- Create: `cstrike/scripts/vscripts/mako_overload/overload.nut`

**Interfaces:**
- Consumes: everything produced by Task 1.
- Produces (called by the stripper through `MakoOverloadScript,RunScriptCode,...` — no commas allowed in parameters):
  - `Overload_Start()`, `Overload_Add(n)`, `Overload_Respite(seconds)`, `Overload_EscapeStart()`, `Overload_Ending()`, `Overload_Victory()`
- Produces (console, root table): `Overload_Debug()`, `Overload_SetGauge(n)`, `Overload_Surge(name)`, `Overload_Laser()`, `Overload_Stop()`, `Overload_SetOffsets(jump, crouch)`
- Uses entities (from Task 3 / existing): `MakoOverloadHud` (game_text), `MakoOverloadAlarm`, `MakoOverloadMusic` (ambient_generic), `EX4ZeddysLaserMaker`, `seph_modelo2_ex2`, `espad`, `puente_1`, `EX3RMZSCmerRotRelay`, `explosion_mako_random`, `cancion*`.

- [ ] **Step 1: Write `overload.nut`**

```squirrel
// MAKO OVERLOAD - engine glue, loaded by logic_script "MakoOverloadScript".
// Inert until the stage relay calls Overload_Start(). Recreated every round.
IncludeScript("mako_overload/logic.nut");

MO_THINK <- 0.25;
MO_TEAM_HUMAN <- 3;
MO_TEAM_ZOMBIE <- 2;
MO_HUD_PRINTCENTER <- 4;
MO_FFADE_IN <- 1;
MO_FFADE_OUT <- 2;
MO_FFADE_STAYOUT <- 8;
MO_FFADE_PURGE <- 16;
MO_WORLD <- Vector(0, 0, 0);

active <- false;
overload <- false;
stabilized <- false;
gauge <- 0.0;
gaugeAcc <- 0.0;
lastThink <- 0.0;
nextHud <- 0.0;
respiteUntil <- 0.0;
nextLaser <- 0.0;
nextSurge <- 0.0;
nextExplosion <- 0.0;
nextPulse <- 0.0;
lastSurge <- null;
lastLaserType <- null;
surge <- null;
surgeEnd <- 0.0;
rageSaved <- {};

function Tier() { return MOL_TierIndex(gauge, overload); }
function RandInt(n) { return RandomInt(0, n - 1); }
function Center(msg) { ClientPrint(null, MO_HUD_PRINTCENTER, msg); }

function Humans() {
	local list = [], p = null;
	while ((p = Entities.FindByClassname(p, "player")) != null)
		if (p.GetTeam() == MO_TEAM_HUMAN && p.IsAlive()) list.push(p);
	return list;
}

function Points(players) {
	local pts = [];
	foreach (p in players) {
		local o = p.GetOrigin(), v = p.GetVelocity(), a = p.EyeAngles();
		pts.push({ x = o.x, y = o.y, z = o.z, vx = v.x, vy = v.y, yaw = a.y });
	}
	return pts;
}

function UpdateHud() {
	if (!active && !stabilized) return;
	local hud = Entities.FindByName(null, "MakoOverloadHud");
	if (hud == null) return;
	hud.KeyValueFromString("message", MOL_HudText(gauge, Tier(), stabilized));
	hud.KeyValueFromString("color", stabilized ? "0 200 255" : MOL_TIERS[Tier()].color);
	EntFireByHandle(hud, "Display", "", 0, null, null);
}

// ---------- API called by the stripper ----------

function Overload_Start() {
	if (active) return;
	active = true;
	local t = Time();
	lastThink = t;
	respiteUntil = t + 45.0;
	nextLaser = respiteUntil + MOL_TIERS[0].laser;
	nextSurge = respiteUntil + MOL_TIERS[0].surge;
	AddThinkToEnt(self, "Overload_Think");
	UpdateHud();
}

function Overload_Add(n) {
	if (!active || overload || stabilized) return;
	gauge = MOL_ClampGauge(gauge + n, false);
	UpdateHud();
}

function Overload_Respite(seconds) {
	if (!active) return;
	local until = Time() + seconds;
	if (until > respiteUntil) respiteUntil = until;
}

function Overload_EscapeStart() {
	if (!active || overload) return;
	if (surge != null) EndSurge();
	overload = true;
	gauge = 100.0;
	respiteUntil = 0.0;
	local t = Time();
	nextLaser = t + 3.0;
	nextExplosion = t + 6.0;
	nextPulse = t + 2.0;
	Center("REACTOR OVERLOAD");
	ScreenFade(null, 255, 255, 255, 200, 1.0, 0.2, MO_FFADE_IN);
	ScreenShake(MO_WORLD, 16.0, 60.0, 3.0, 50000.0, 0, true);
	EntFire("cancion*", "Volume", "0", 0, null);
	EntFire("MakoOverloadMusic", "PlaySound", "", 0.5, null);
	UpdateHud();
}

function Overload_Ending() {
	if (surge != null) EndSurge();
	stabilized = true;
	UpdateHud();
}

function Overload_Victory() {
	ScreenFade(null, 255, 255, 255, 255, 1.5, 0.5, MO_FFADE_IN);
	EntFire("MakoOverloadMusic", "Volume", "0", 0, null);
}

// ---------- loop ----------

function Overload_Think() {
	if (!active) return MO_THINK;
	local t = Time(), dt = t - lastThink;
	lastThink = t;

	if (!overload && !stabilized) {
		gaugeAcc += dt;
		while (gaugeAcc >= 4.0) { gaugeAcc -= 4.0; gauge = MOL_ClampGauge(gauge + 1, false); }
	}
	if (t >= nextHud) { nextHud = t + 1.0; UpdateHud(); }
	if (surge != null && t >= surgeEnd) EndSurge();
	if (surge == "lowgrav") ApplyGravity(0.35); // players who respawned during the effect

	if (stabilized || t < respiteUntil) return MO_THINK;

	if (t >= nextLaser) nextLaser = t + (Overload_Laser() ? MOL_TIERS[Tier()].laser : 3.0);

	if (overload) {
		if (t >= nextExplosion) { nextExplosion = t + 12.0; EntFire("explosion_mako_random", "PickRandom", "", 0, null); }
		if (t >= nextPulse) { nextPulse = t + 3.0; ScreenFade(null, 255, 0, 0, 40, 1.5, 0, MO_FFADE_IN); }
	} else if (surge == null && t >= nextSurge) {
		nextSurge = t + MOL_TIERS[Tier()].surge;
		local picked = MOL_PickSurge(Tier(), lastSurge, false, MOL_BridgeAllowed(Points(Humans()), false), RandInt);
		if (picked != null) Overload_Surge(picked);
	}
	return MO_THINK;
}

// ---------- tracking lasers ----------

function Overload_Laser(allowDouble = true) {
	local c = MOL_MainCluster(Points(Humans()), 600.0);
	if (c == null) return false;
	local type = MOL_PickLaserType(Tier(), lastLaserType, RandInt);
	foreach (d in MOL_ShotDirections(c.dirx, c.diry)) {
		local start = Vector(c.cx, c.cy, c.floorZ + 40);
		local end = Vector(c.cx - d.x * 700, c.cy - d.y * 700, c.floorZ + 40);
		local shot = MOL_LaserPlacement(c, d, TraceLine(start, end, null) * 700.0, type);
		if (shot == null) continue;
		FireLaser(shot, type);
		lastLaserType = type;
		if (allowDouble && MOL_IsDoubleShot(Tier(), RandomFloat(0, 1)))
			EntFireByHandle(self, "RunScriptCode", "Overload_Laser(false)", 1.2, null, null);
		return true;
	}
	return false;
}

function FireLaser(shot, type) {
	Center(type == "jump" ? "!! JUMP !!" : "!! CROUCH !!");
	local floor = shot.z - MOL_OFFSETS[type];
	EntFire("seph_modelo2_ex2", "AddOutput", "origin " + shot.sephx + " " + shot.sephy + " " + floor, 0, null);
	EntFire("seph_modelo2_ex2", "AddOutput", "angles 0 " + shot.yaw + " 0", 0, null);
	EntFire("seph_modelo2_ex2", "Enable", "", 0.03, null);
	EntFire("seph_modelo2_ex2", "Disable", "", 2.5, null);
	EntFire("espad", "PlaySound", "", 0, null);
	EntFire("EX4ZeddysLaserMaker", "AddOutput", "angles 0 " + shot.yaw + " 0", 1.45, null);
	EntFire("EX4ZeddysLaserMaker", "AddOutput", "origin " + shot.x + " " + shot.y + " " + shot.z, 1.45, null);
	EntFire("EX4ZeddysLaserMaker", "ForceSpawn", "", 1.5, null);
}

// ---------- surges ----------

function Overload_Surge(name) {
	local s = MOL_SurgeByName(name);
	if (s == null) { printl("[MAKO OVERLOAD] unknown surge: " + name); return; }
	lastSurge = name;
	ScreenFade(null, 0, 255, 0, 120, 0.5, 0.3, MO_FFADE_IN);
	ScreenShake(MO_WORLD, 8.0, 40.0, 2.0, 50000.0, 0, true);
	EntFire("MakoOverloadAlarm", "PlaySound", "", 0, null);
	Center("MAKO SURGE: " + s.label);
	EntFireByHandle(self, "RunScriptCode", "BeginSurge(\"" + name + "\")", 2.0, null, null);
}

function BeginSurge(name) {
	if (!active || stabilized) return;
	if (surge != null) EndSurge();
	local t = Time();
	if (name == "lowgrav") { surge = name; surgeEnd = t + 10.0; ApplyGravity(0.35); }
	else if (name == "blackout") { surge = name; surgeEnd = t + 8.0; ScreenFade(null, 0, 0, 0, 235, 0.5, 8.0, MO_FFADE_OUT | MO_FFADE_STAYOUT); }
	else if (name == "bridge") { EntFire("puente_1", "FireUser2", "", 0, null); EntFire("EX3RMZSCmerRotRelay", "Trigger", "", 15.0, null); }
	else if (name == "barrage") { for (local i = 0; i < 3; i++) EntFireByHandle(self, "RunScriptCode", "Overload_Laser(false)", i * 1.5, null, null); }
	else if (name == "rage") { surge = name; surgeEnd = t + 6.0; SetRage(true); }
}

function EndSurge() {
	if (surge == "lowgrav") ApplyGravity(1.0);
	else if (surge == "blackout") ScreenFade(null, 0, 0, 0, 235, 1.0, 0, MO_FFADE_IN | MO_FFADE_PURGE);
	else if (surge == "rage") SetRage(false);
	surge = null;
}

function ApplyGravity(g) {
	local p = null;
	while ((p = Entities.FindByClassname(p, "player")) != null) p.SetGravity(g);
}

function SetRage(on) {
	local p = null;
	while ((p = Entities.FindByClassname(p, "player")) != null) {
		local key = p.entindex();
		if (on) {
			if (p.GetTeam() != MO_TEAM_ZOMBIE || !p.IsAlive()) continue;
			local speed = NetProps.GetPropFloat(p, "m_flLaggedMovementValue");
			rageSaved[key] <- speed;
			NetProps.SetPropFloat(p, "m_flLaggedMovementValue", speed * 1.3);
			EntFireByHandle(p, "Color", "255 0 0", 0, null, null);
		} else if (key in rageSaved) {
			NetProps.SetPropFloat(p, "m_flLaggedMovementValue", rageSaved[key]);
			EntFireByHandle(p, "Color", "255 255 255", 0, null, null);
		}
	}
	if (!on) rageSaved = {};
}

// ---------- debug / console ----------

function Overload_Debug() {
	local t = Time();
	printl("[MAKO OVERLOAD] active=" + active + " overload=" + overload + " stabilized=" + stabilized
		+ " gauge=" + gauge + " tier=" + MOL_TIERS[Tier()].name + " surge=" + surge
		+ " respite=" + (respiteUntil - t) + "s nextLaser=" + (nextLaser - t) + "s nextSurge=" + (nextSurge - t) + "s");
	local c = MOL_MainCluster(Points(Humans()), 600.0);
	if (c == null) printl("[MAKO OVERLOAD] no living human");
	else printl("[MAKO OVERLOAD] cluster=" + c.count + " at " + c.cx + " " + c.cy + " floor=" + c.floorZ + " dir=" + c.dirx + " " + c.diry);
	printl("[MAKO OVERLOAD] offsets jump=" + MOL_OFFSETS.jump + " crouch=" + MOL_OFFSETS.crouch);
}

function Overload_SetGauge(n) { gauge = MOL_ClampGauge(n.tofloat(), overload); UpdateHud(); }

function Overload_SetOffsets(jump, crouch) { MOL_OFFSETS.jump = jump.tofloat(); MOL_OFFSETS.crouch = crouch.tofloat(); }

function Overload_Stop() {
	if (surge != null) EndSurge();
	ApplyGravity(1.0);
	SetRage(false);
	ScreenFade(null, 0, 0, 0, 0, 0.1, 0, MO_FFADE_IN | MO_FFADE_PURGE);
	stabilized = true;
	UpdateHud();
	active = false;
}

// console access: "script Overload_Debug()" runs in the root table
foreach (fn in ["Overload_Debug", "Overload_SetGauge", "Overload_Surge", "Overload_Laser",
	"Overload_Stop", "Overload_SetOffsets", "Overload_Start", "Overload_EscapeStart"])
	getroottable()[fn] <- this[fn].bindenv(this);
```

- [ ] **Step 2: Syntax check + logic tests**

Run: `tests/overload/run.sh`
Expected: logic tests `0 failures`, then `overload.nut compiles`.

- [ ] **Step 3: Commit**

```bash
git add cstrike/scripts/vscripts/mako_overload/overload.nut
git commit -m "feat(overload): VScript engine glue (gauge, lasers, surges, overload)"
```

---

### Task 3: Stripper section, AdminRoom stage and checker

**Files:**
- Create: `tools/check_stripper.py`
- Modify: `cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg` (LevelCounter add, LevelCase add, admin room buttons, new section before `;       MISC`)
- Copy: `cstrike/addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg`
- Modify: `cstrike/addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg`

**Interfaces:**
- Consumes: script API of Task 2 (`Overload_Start()`, `Overload_Add(n)`, `Overload_Respite(s)`, `Overload_EscapeStart()`, `Overload_Ending()`, `Overload_Victory()`); existing entities `EX4ZeddysLaserMaker`, `EX4EndLaserTemp`, `EX3RMZSCmerRotRelay`, `puente_1` VScript logic, `seph_modelo2_ex2`, `BombTimer1/2`, `Score100`, `victoria`, `boom`, `finalf`, `comienza_huida`, `CoreTrigger`, `ascensort`, `bahamut_entry`, `bahamut_vida`.
- Produces: entities `MakoOverloadScript`, `MakoOverloadHud`, `MakoOverloadAlarm`, `MakoOverloadMusic`, `LevelRelayMakoOverload`, `MakoOverloadDoorRelay`, `MakoOverloadBridgeTrig`, `MakoOverloadEscape`, `MakoOverloadCheck`, `MakoOverloadEnding`, `MakoOverloadEndingCase`, `MakoOverloadWin`; LevelCounter value 17; button hammerid 100012.

- [ ] **Step 1: Write the checker**

`tools/check_stripper.py`:
```python
#!/usr/bin/env python3
"""Checks a Mako stripper: brace balance, unresolved targets in one section,
commas inside RunScriptCode parameters. Usage: check_stripper.py <cfg> <section marker>"""
import re
import sys


def blocks(text):
    out, action, i, lines = [], None, 0, text.split("\n")
    while i < len(lines):
        s = lines[i].strip()
        m = re.match(r"^(add|filter|modify|remove):", s)
        if m:
            action = m.group(1)
            i += 1
            continue
        if s == "{" and action:
            start, depth, i, kv = i + 1, 1, i + 1, []
            while i < len(lines) and depth > 0:
                t = lines[i].strip()
                if not t.startswith(";"):
                    depth += t.count("{") - t.count("}")
                    kv += re.findall(r'"([^"]*)"\s+"([^"]*)"', t)
                i += 1
            out.append((start, kv))
            continue
        i += 1
    return out


def main(path, marker):
    text = open(path, encoding="latin1").read()
    errors = []
    depth = 0
    for n, line in enumerate(text.split("\n"), 1):
        s = line.strip()
        if not s.startswith(";"):
            depth += s.count("{") - s.count("}")
            if depth < 0:
                errors.append(f"line {n}: negative brace depth")
                depth = 0
    if depth != 0:
        errors.append(f"brace depth at end = {depth}")

    start = text.find(marker)
    if start < 0:
        errors.append(f"section marker not found: {marker}")
        start_line = end_line = 0
    else:
        start_line = text[:start].count("\n") + 1
        nxt = re.search(r"\n; MODE: |\n;       MISC", text[start + len(marker):])
        end_line = text[: start + len(marker) + (nxt.start() if nxt else len(text))].count("\n") + 1

    bl = blocks(text)
    known = {v.lower() for _, kv in bl for k, v in kv if k == "targetname"}
    referenced = set()
    for ln, kv in bl:
        if start_line <= ln <= end_line:
            continue
        for k, v in kv:
            if k.startswith("On"):
                referenced.add(v.split(",")[0].lower())
    for ln, kv in bl:
        if not (start_line <= ln <= end_line):
            continue
        for k, v in kv:
            if not k.startswith("On"):
                continue
            parts = v.split(",")
            if len(parts) != 5:
                errors.append(f"line ~{ln}: output needs 5 fields: {v}")
                continue
            targets = [parts[0]]
            if parts[1].lower() == "addoutput" and ":" in parts[2]:
                targets.append(parts[2].split(" ", 1)[1].split(":")[0])
            if parts[1].lower() == "runscriptcode" or "RunScriptCode" in parts[2]:
                pass  # commas already rejected by the 5-field check
            for t in targets:
                tl = t.lower()
                if tl.startswith("!"):
                    continue
                base = tl.rstrip("*")
                if tl in known or tl in referenced or (tl.endswith("*") and any(x.startswith(base) for x in known)):
                    continue
                errors.append(f"line ~{ln}: unresolved target {t}")
    for e in errors:
        print("ERROR", e)
    print("OK" if not errors else f"{len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
```

- [ ] **Step 2: Run the checker to verify it fails (section missing)**

Run: `python3 tools/check_stripper.py cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg "; MODE: MAKO OVERLOAD"`
Expected: `ERROR section marker not found` and exit code 1.

- [ ] **Step 3: Add LevelCounter case 17, admin room button and the section**

Apply with this script (exact anchors verified to be unique):
```bash
python3 - <<'PYEOF'
p = "cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg"
s = open(p).read()
def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a)
    s = s.replace(a, b)

rep('\t"min" "1"\n\t"max" "16"', '\t"min" "1"\n\t"max" "17"')
rep('\t"Case16" "16"\n', '\t"Case16" "16"\n\t"Case17" "17"\n')
rep('\t"OnCase16" "ItemSpawnerRelayAlt,FireUser3,,35,1"\n',
    '\t"OnCase16" "ItemSpawnerRelayAlt,FireUser3,,35,1"\n\n'
    '\t; MAKO OVERLOAD\n'
    '\t"OnCase17" "UnlozeSettings_FallDamage_OFF,Trigger,,0,1"\n'
    '\t"OnCase17" "LevelRelayMakoOverload,Trigger,,0,1"\n'
    '\t"OnCase17" "ItemSpawnerRelay,FireUser1,,32,1"\n'
    '\t"OnCase17" "ItemSpawnerAltZone,FireUser1,,47,1"\n'
    '\t"OnCase17" "ItemSpawnerRelayAlt,FireUser3,,35,1"\n')

button = '''add:
{
	"model" "*280"
	"hammerid" "100012"
	"spawnflags" "1025"
	"classname" "func_button"
	"targetname" "ButtonMakoOverload"
	"origin" "-4472 -3333 1396"
	"angles" "90 270 0"
	"wait" "1"
	"OnPressed" "!self,Lock,,0,-1"
	"OnPressed" "AdminRoomText,AddOutput,message Mako Overload - Press again to confirm. (5s),0,-1"
	"OnPressed" "AdminRoomText,Display,,0.05,-1"
	"OnPressed" "!self,Unlock,,5,-1"
	"OnUseLocked" "!self,FireUser1,,-1"
	"OnUseLocked" "AdminRoomText,AddOutput,message Mako Overload - set for next round.,0,-1"
	"OnUseLocked" "AdminRoomText,Display,,0.05,-1"
	"OnUser1" "LevelCounter,SetValue,17,0,-1"
}
'''
anchor = '\t"OnUser1" "LevelCounter,SetValue,16,0,-1"\n}\n'
rep(anchor, anchor + button)

section = open("/tmp/claude-1000/-home-cmer-Documents-git-NiDE-mako-v5-extra-stages/bdd48f5d-01ea-4d22-83c7-c18fe93a4163/scratchpad/overload_section.cfg").read()
rep(';=========================\n;       MISC\n;=========================', section + ';=========================\n;       MISC\n;=========================')
open(p, "w").write(s)
PYEOF
```

with `/tmp/claude-1000/-home-cmer-Documents-git-NiDE-mako-v5-extra-stages/bdd48f5d-01ea-4d22-83c7-c18fe93a4163/scratchpad/overload_section.cfg` containing:

```text
;-------------------------
; MODE: MAKO OVERLOAD
; Instability gauge, player-tracking Sephiroth lasers, Mako surges,
; 150s overload escape, Sephiroth last stand.
; Logic: scripts/vscripts/mako_overload/overload.nut (MakoOverloadScript)
;-------------------------

add:
{
	"classname" "logic_script"
	"targetname" "MakoOverloadScript"
	"origin" "-3584 -3584 1088"
	"vscripts" "mako_overload/overload.nut"
}
add:
{
	"spawnflags" "1"
	"classname" "game_text"
	"targetname" "MakoOverloadHud"
	"origin" "-3584 -3584 1088"
	"channel" "1"
	"color" "0 255 0"
	"color2" "0 0 0"
	"fadein" "0"
	"fadeout" "0.1"
	"holdtime" "1.2"
	"message" "MAKO"
	"x" "-1"
	"y" ".14"
}
add:
{
	"classname" "ambient_generic"
	"targetname" "MakoOverloadAlarm"
	"origin" "-3584 -3584 1088"
	"message" "ambient/alarms/klaxon1.wav"
	"health" "10"
	"pitch" "100"
	"pitchstart" "100"
	"radius" "1250"
	"spawnflags" "49"
}
add:
{
	"classname" "ambient_generic"
	"targetname" "MakoOverloadMusic"
	"origin" "-3584 -3584 1088"
	"message" "#music/zeddy/the_qemists_no_more.mp3"
	"health" "10"
	"pitch" "100"
	"pitchstart" "100"
	"radius" "1250"
	"spawnflags" "49"
}

add:
{
	"classname" "logic_relay"
	"targetname" "LevelRelayMakoOverload"
	"origin" "-3584 -3584 1088"
	"OnTrigger" "LevelText,AddOutput,message > MAKO OVERLOAD <,0,1"
	"OnTrigger" "LevelText,AddOutput,color 255 0 255,0,1"
	"OnTrigger" "consola,Command,zr_infect_mzombie_countdown 1,0,1"
	"OnTrigger" "consola,Command,zr_infect_spawntime_min 29.9,0,1"
	"OnTrigger" "consola,Command,zr_infect_spawntime_max 29.9,0,1"
	"OnTrigger" "consola,Command,zr_ztele_zombie 1,0,1"
	"OnTrigger" "consola,Command,say ** CURRENT DIFFICULTY ** >> MAKO OVERLOAD << **,10,1"
	"OnTrigger" "consola,Command,say ** THE REACTOR IS UNSTABLE - STAY TOGETHER AND WATCH FOR SEPHIROTH **,11,1"
	"OnTrigger" "AvisoExt2,Toggle,,0,1"
	"OnTrigger" "azul,Disable,,0,1"
	"OnTrigger" "baha_tr,Enable,,0,1"
	"OnTrigger" "bahamut_entry,Enable,,0,1"
	"OnTrigger" "bahamut_2,Kill,,0,1"
	"OnTrigger" "bahamut_3,Kill,,0,1"
	"OnTrigger" "bahamut_fulgor,Kill,,0,1"
	"OnTrigger" "calcVidaM,Kill,,0,1"
	"OnTrigger" "ss_only,AddOutput,message ze_random_labyrinth/vulcan.mp3,0,1"
	"OnTrigger" "cancion_1_extra,Kill,,0,1"
	"OnTrigger" "cancion_1_extra2,Kill,,0,1"
	"OnTrigger" "canciones_extreme2_1,PickRandom,,0,1"
	"OnTrigger" "canciones_extreme2_2,PickRandom,,0,1"
	"OnTrigger" "cancion_3,AddOutput,message #mako_reactor/ffvii_e2_selfvsself.mp3,0,1"
	"OnTrigger" "cancion_3_extra,AddOutput,message #mako_reactor/ffvii_tempest.mp3,0,1"
	"OnTrigger" "cancion_3_extra_2,Kill,,0,1"
	"OnTrigger" "dificil_props,Kill,,0,1"
	"OnTrigger" "dificil_trigger,Enable,,0,1"
	"OnTrigger" "extreme2,Enable,,0,1"
	"OnTrigger" "extreme2_particula1,Start,,5,1"
	"OnTrigger" "extreme_2_particula3,Enable,,5,1"
	"OnTrigger" "extreme2_triggers,Enable,,1,1"
	"OnTrigger" "extreme2_trigger2,Enable,,1,1"
	"OnTrigger" "extreme2_trigger3,Enable,,1,1"
	"OnTrigger" "extreme2_trigger5,Enable,,1,1"
	"OnTrigger" "extreme2_trigger6,Enable,,1,1"
	"OnTrigger" "extreme2_trigger7,Enable,,1,1"
	"OnTrigger" "extreme2_trigger8,Enable,,1,1"
	"OnTrigger" "extreme2_trigger9,Enable,,0,1"
	"OnTrigger" "extreme2_trigger10,Enable,,1,1"
	"OnTrigger" "extreme2_trigger11,Enable,,1,1"
	"OnTrigger" "extreme2_trigger12,Enable,,1,1"
	"OnTrigger" "extreme2_trigger13,Enable,,0,1"
	"OnTrigger" "extreme_props,Enable,,0,1"
	"OnTrigger" "extreme_props,EnableCollision,,0,1"
	"OnTrigger" "extremedanyo,Enable,,0,1"
	"OnTrigger" "extremedanyo,Trigger,,2,1"
	"OnTrigger" "huida2_d,Enable,,0,1"
	"OnTrigger" "medio_breakable,Break,,0,1"
	"OnTrigger" "nubes_secundarias,TurnOn,,0,1"
	"OnTrigger" "nubes_secundarias,Color,0 255 100,0,1"
	"OnTrigger" "puerta_1x,FireUser2,,0,1"
	"OnTrigger" "puerta_admin,Enable,,0,1"
	"OnTrigger" "puerta_asc1,Kill,,0,1"
	"OnTrigger" "puerta_dasc1,Kill,,0,1"
	"OnTrigger" "rojo2,Enable,,0,1"
	"OnTrigger" "sephiroth_fx,Kill,,0,1"
	"OnTrigger" "tele_Ex,Enable,,0,1"
	"OnTrigger" "trigger_extreme,Enable,,0,1"
	"OnTrigger" "trigger_extreme2_ex,Enable,,0,1"
	"OnTrigger" "trigger_extreme2_ex,FireUser1,,0,1"
	"OnTrigger" "trigger_n_d,Kill,,0,1"
	"OnTrigger" "trigger_n_e,Kill,,0,1"
	"OnTrigger" "trigger_n_m,Kill,,0,1"
	"OnTrigger" "trigger_n_e2,Kill,,0,-1"
	"OnTrigger" "trigger_n_d3,Kill,,0,1"
	"OnTrigger" "EX3HellzWin,Kill,,0,1"
	"OnTrigger" "materias_3,Trigger,,11,1"
	"OnTrigger" "zm_prop3,Toggle,,3,1"
	"OnTrigger" "ButtonExt3Lasers,Kill,,0,1"
	"OnTrigger" "xb_gravedad,FireUser3,,5,1"

	; script
	"OnTrigger" "MakoOverloadScript,RunScriptCode,Overload_Start(),0,1"

	; gauge bonds and respites (only in this mode)
	"OnTrigger" "MakoOverloadDoorRelay,Enable,,0,1"
	"OnTrigger" "MakoOverloadBridgeTrig,Enable,,0,1"
	"OnTrigger" "CoreTrigger,AddOutput,OnStartTouch MakoOverloadScript:RunScriptCode:Overload_Add(10):0:1,5,1"
	"OnTrigger" "ascensort,AddOutput,OnStart MakoOverloadScript:RunScriptCode:Overload_Respite(25):0:1,5,1"
	"OnTrigger" "bahamut_entry,AddOutput,OnTrigger MakoOverloadScript:RunScriptCode:Overload_Add(10):0:1,5,1"
	"OnTrigger" "bahamut_entry,AddOutput,OnTrigger MakoOverloadScript:RunScriptCode:Overload_Respite(10):0:1,5,1"
	"OnTrigger" "bahamut_vida,AddOutput,OnHitMin MakoOverloadScript:RunScriptCode:Overload_Add(15):0:1,5,1"

	; escape: 150s instead of 130s (MakoOverloadEscape replaces huida_e)
	"OnTrigger" "comienza_huida,AddOutput,OnStartTouch MakoOverloadEscape:Trigger::0.50:1,0,1"
	"OnTrigger" "comienza_huida,AddOutput,OnStartTouch MakoOverloadScript:RunScriptCode:Overload_EscapeStart():0.50:1,0,1"

	; ending
	"OnTrigger" "finalf,AddOutput,OnTrigger MakoOverloadCheck:Enable::0.00:1,5,1"
	"OnTrigger" "finalf,AddOutput,OnTrigger MakoOverloadCheck:TouchTest::0.25:1,5,1"
}

; superior door button (hammerid 1754 - the other "boton" is the door before the bridge)
add:
{
	"classname" "logic_relay"
	"targetname" "MakoOverloadDoorRelay"
	"origin" "-3584 -3584 1088"
	"StartDisabled" "1"
	"OnTrigger" "MakoOverloadScript,RunScriptCode,Overload_Add(5),0,1"
}
modify:
{
	match:
	{
		"hammerid" "1754"
		"classname" "func_button"
	}
	insert:
	{
		"OnPressed" "MakoOverloadDoorRelay,Trigger,,0,1"
	}
}
; bridge crossed (same zone as trigger_n_d3)
add:
{
	"model" "*124"
	"spawnflags" "1"
	"classname" "trigger_once"
	"targetname" "MakoOverloadBridgeTrig"
	"origin" "-9348 5354.39 120"
	"StartDisabled" "1"
	"filtername" "humanos"
	"OnStartTouch" "MakoOverloadScript,RunScriptCode,Overload_Add(5),0,1"
}

; copy of the map's huida_e (hammerid 2326) with 150s. BombTimer display (max 2m25s) starts at +5s.
add:
{
	"classname" "logic_relay"
	"targetname" "MakoOverloadEscape"
	"origin" "-3584 -3584 1088"
	"OnTrigger" "consola,Command,say ** EXPLOSION IN 150 SECONDS **,0,1"
	"OnTrigger" "consola,Command,say ** 140 SECONDS LEFT **,10,1"
	"OnTrigger" "consola,Command,say ** 130 SECONDS LEFT **,20,1"
	"OnTrigger" "consola,Command,say ** 120 SECONDS LEFT **,30,1"
	"OnTrigger" "consola,Command,say ** 110 SECONDS LEFT **,40,1"
	"OnTrigger" "consola,Command,say ** 100 SECONDS LEFT **,50,1"
	"OnTrigger" "consola,Command,say ** 90 SECONDS LEFT **,60,1"
	"OnTrigger" "consola,Command,say ** 80 SECONDS LEFT **,70,1"
	"OnTrigger" "consola,Command,say ** 70 SECONDS LEFT **,80,1"
	"OnTrigger" "consola,Command,say ** 60 SECONDS LEFT **,90,1"
	"OnTrigger" "consola,Command,say ** 50 SECONDS LEFT **,100,1"
	"OnTrigger" "consola,Command,say ** 40 SECONDS LEFT **,110,1"
	"OnTrigger" "consola,Command,say ** 30 SECONDS LEFT **,120,1"
	"OnTrigger" "consola,Command,say ** 20 SECONDS LEFT **,130,1"
	"OnTrigger" "consola,Command,say ** 10 SECONDS LEFT **,140,1"
	"OnTrigger" "BombTimer1,FireUser1,,5,1"
	"OnTrigger" "BombTimer2,FireUser1,,5,1"
	"OnTrigger" "puertaZM,Disable,,2.5,1"
	"OnTrigger" "props_extreme,Toggle,,2.5,1"
	"OnTrigger" "puertas_1,Lock,,0,1"
	"OnTrigger" "puertas_2,Lock,,0,1"
	"OnTrigger" "xix,StartForward,,140,1"
	"OnTrigger" "sin_zombis,Enable,,149,1"
	"OnTrigger" "finalf,Trigger,,149.5,1"
}
modify:
{
	match:
	{
		"hammerid" "883420"
		"classname" "logic_relay"
		"targetname" "finalf"
	}
	insert:
	{
		"OnTrigger" "MakoOverloadEscape,CancelPending,,0.25,-1"
	}
}

; ending: Sephiroth's last stand (3 waves), then win
add:
{
	"model" "*213"
	"spawnflags" "1"
	"classname" "trigger_multiple"
	"targetname" "MakoOverloadCheck"
	"origin" "-10880 4410 128"
	"StartDisabled" "1"
	"filtername" "humanos"
	"OnTouching" "MakoOverloadEnding,Trigger,,0,1"
	"OnTouching" "BombTimer*,Kill,,0,1"
	"OnTouching" "boom,Disable,,0,1"
	"OnTouching" "MakoOverloadScript,RunScriptCode,Overload_Ending(),0,1"
	"OnNotTouching" "consola,Command,say ** NO ONE HAS ESCAPED! **,0,1"
}
add:
{
	"spawnflags" "1"
	"classname" "logic_relay"
	"targetname" "MakoOverloadEnding"
	"origin" "-3584 -3584 1088"
	"OnTrigger" "consola,Command,say ** SEPHIROTH'S LAST STAND! **,0,1"
	"OnTrigger" "ss_seeyou,PlaySound,,0,1"
	"OnTrigger" "seph_modelox1,Enable,,0,1"
	"OnTrigger" "cortefatal,Break,,3.35,1"
	"OnTrigger" "espad,PlaySound,,3.35,1"
	"OnTrigger" "sephiroth_c,StartForward,,2.9,1"
	"OnTrigger" "corte2,PickRandom,,1,1"
	"OnTrigger" "MakoOverloadEndingCase,PickRandom,,0,1"
	"OnTrigger" "MakoOverloadEndingCase,PickRandom,,4.5,1"
	"OnTrigger" "MakoOverloadEndingCase,PickRandom,,9,1"
	"OnTrigger" "MakoOverloadWin,Enable,,16,1"
	"OnTrigger" "MakoOverloadWin,TouchTest,,16.5,1"
}
add:
{
	"classname" "logic_case"
	"targetname" "MakoOverloadEndingCase"
	"origin" "-3584 -3584 1088"
	;c j c
	"OnCase01" "EX4EndLaserTemp,AddOutput,origin -9862 4010.99 129,0,-1"
	"OnCase01" "EX4EndLaserTemp,ForceSpawn,,2.5,-1"
	"OnCase01" "EX4EndLaserTemp,AddOutput,origin -9562 4010.99 129,3.5,-1"
	"OnCase01" "EX4EndLaserTemp,ForceSpawn,,4.2,-1"
	;j j j
	"OnCase02" "EX4EndLaserTemp,AddOutput,origin -9862 4009.2 108,0,-1"
	"OnCase02" "EX4EndLaserTemp,ForceSpawn,,2.5,-1"
	"OnCase02" "EX4EndLaserTemp,AddOutput,origin -9562 4009.2 108,3.5,-1"
	"OnCase02" "EX4EndLaserTemp,ForceSpawn,,4.2,-1"
	;c j j
	"OnCase03" "EX4EndLaserTemp,AddOutput,origin -9862 4010.99 129,0,-1"
	"OnCase03" "EX4EndLaserTemp,ForceSpawn,,2.5,-1"
	"OnCase03" "EX4EndLaserTemp,AddOutput,origin -9562 4010.99 108,3.5,-1"
	"OnCase03" "EX4EndLaserTemp,ForceSpawn,,4.2,-1"
	;j j c
	"OnCase04" "EX4EndLaserTemp,AddOutput,origin -9862 4009.2 108,0,-1"
	"OnCase04" "EX4EndLaserTemp,ForceSpawn,,2.5,-1"
	"OnCase04" "EX4EndLaserTemp,AddOutput,origin -9562 4010.99 129,3.5,-1"
	"OnCase04" "EX4EndLaserTemp,ForceSpawn,,4.2,-1"
}
add:
{
	"model" "*213"
	"spawnflags" "1"
	"classname" "trigger_multiple"
	"targetname" "MakoOverloadWin"
	"origin" "-10880 4410 128"
	"StartDisabled" "1"
	"filtername" "humanos"
	"OnTouching" "cancion*,Volume,0,0,1"
	"OnTouching" "MakoOverloadScript,RunScriptCode,Overload_Victory(),0,1"
	"OnTouching" "consola,Command,say ** YOU SURVIVED THE MAKO OVERLOAD! **,0,1"
	"OnTouching" "victoria,PlaySound,,0,1"
	"OnTouching" "LevelCounter,SetValue,6,0,1"
	"OnTouching" "consola,command,sm_makovote,0,1"
	"OnTouching" "boom,Enable,,0,1"
	"OnTouching" "boom,Trigger,,0.05,1"
	"OnNotTouching" "consola,Command,say ** NO ONE HAS ESCAPED! **,0,1"
	"OnNotTouching" "boom,Enable,,0,1"
	"OnNotTouching" "boom,Trigger,,0.05,1"
	; rewards for every human in the zone (same as EX3HellzWin)
	"OnStartTouch" "Score100,FireUser1,,0,-1"
	"OnStartTouch" "!activator,AddOutput,OnUser3 !self:AddOutput:rendercolor 255 0 0:0.00:1,0,-1"
	"OnStartTouch" "!activator,AddOutput,OnUser3 !self:AddOutput:health 30000:0.00:1,0,-1"
	"OnStartTouch" "!activator,AddOutput,OnUser3 speed:ModifySpeed:1.3:0.00:1,0,-1"
}

```

Note: the section must be written to the scratchpad file first (Write tool), then the Python script above run from the repo root.

- [ ] **Step 4: Copy to the SourceMod Stripper path and run the checker**

```bash
cp cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg cstrike/addons/sourcemod/configs/stripper/maps/
python3 tools/check_stripper.py cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg "; MODE: MAKO OVERLOAD"
grep -c '"hammerid" "100012"' cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg
```
Expected: `OK`, exit 0, and `1`.

- [ ] **Step 5: AdminRoom stage**

```bash
python3 - <<'PYEOF'
p = "cstrike/addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg"
s = open(p).read()
a = '\t\t\t\t"0"     "#100011:FireUser1"\n\t\t\t}\n\t\t}\n'
assert s.count(a) == 1
s = s.replace(a, a + '''		"15"
		{
			"name"      "Mako Overload"
			"triggers"
			{
				"0"     "14"
				"1"     "overload"
				"2"     "makooverload"
			}
			"actions"
			{
				"0"     "#100012:FireUser1"
			}
		}
''')
open(p, "w").write(s)
PYEOF
grep -n 'Mako Overload\|#100012' cstrike/addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg
```
Expected: the name line and the `#100012:FireUser1` line.

- [ ] **Step 6: Commit**

```bash
git add tools/check_stripper.py cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg \
  cstrike/addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg \
  cstrike/addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg
git commit -m "feat(overload): stripper section, LevelCounter 17, AdminRoom stage"
```

---

### Task 4: Deploy to the test server and validate in game

**Files:**
- Deploy only (no repo change unless calibration values change `logic.nut`).

**Interfaces:**
- Consumes: Tasks 1–3 files.

- [ ] **Step 1: Deploy in one SSH connection (test server only)**

```bash
S=/tmp/claude-1000/-home-cmer-Documents-git-NiDE-mako-v5-extra-stages/bdd48f5d-01ea-4d22-83c7-c18fe93a4163/scratchpad/stage_overload
rm -rf $S && mkdir -p $S/addons/sourcemod/configs/stripper/maps $S/addons/sourcemod/configs/adminroom/maps $S/scripts/vscripts/mako_overload
cp cstrike/addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg $S/addons/sourcemod/configs/stripper/maps/
cp cstrike/addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg $S/addons/sourcemod/configs/adminroom/maps/
cp cstrike/scripts/vscripts/mako_overload/*.nut $S/scripts/vscripts/mako_overload/
C=/home/container/pterodactyl/volumes/fe4451bc-1b56-46eb-8b64-b717c6ebda8c/cstrike
tar -C $S -cf - . | timeout 300 ssh -o BatchMode=yes -o ConnectTimeout=20 root@100.64.98.58 "set -e; cd $C; \
  for f in addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg; do cp -p \$f \$f.bak-overload; done; \
  tar -xf - --no-same-owner; rm -f scripts/vscripts/cmer_probe.nut; \
  chown -R pterodactyl:pterodactyl addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg scripts/vscripts/mako_overload; \
  md5sum addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg scripts/vscripts/mako_overload/*.nut"
(cd $S && md5sum addons/sourcemod/configs/stripper/maps/*.cfg addons/sourcemod/configs/adminroom/maps/*.cfg scripts/vscripts/mako_overload/*.nut)
```
Expected: remote and local md5 identical.

- [ ] **Step 2: In-game validation (user runs; report results)**

1. `changelevel ze_ffvii_mako_reactor_v5_3`, then `sm_adminroom_reloadcfg`, `sm_stage overload`, end the round.
2. HUD shows `MAKO  [----------]  0%  STABLE`; `script Overload_Debug()` prints `active=true`.
3. After 45 s: a laser every ~20 s with `!! JUMP !!`; Sephiroth appears behind the group. Test in the train yard (open) and in a corridor.
4. Calibration: if lasers pass over/under players, adjust live with `script Overload_SetOffsets(36, 66)` (try ±8), then report the values.
5. Force each surge: `script Overload_Surge("lowgrav")`, `"blackout"`, `"bridge"`, `"barrage"`, `"rage"`; verify gravity/speed/colour return to normal.
6. `script Overload_SetGauge(80)` → CRITICAL, faster lasers, doubles.
7. Play to the escape: `REACTOR OVERLOAD`, `EXPLOSION IN 150 SECONDS`, lasers every 5 s, explosions; BOMB TIMER starts at +5 s.
8. Ending with humans in the zone: last stand (3 waves) then `YOU SURVIVED THE MAKO OVERLOAD!`; without humans: `NO ONE HAS ESCAPED!`.
9. Next round (any other stage, e.g. `sm_stage ex2`): no HUD, no lasers, normal gravity.

- [ ] **Step 3: Apply calibration (if changed)**

If step 2.4 found better offsets `J`/`C`, set them in `logic.nut`:
```squirrel
::MOL_OFFSETS <- { jump = J, crouch = C };
```
update the expected values in `tests/overload/test_logic.nut` (they use `MOL_OFFSETS`, so no change needed), run `tests/overload/run.sh`, redeploy with Step 1, and commit:
```bash
git add cstrike/scripts/vscripts/mako_overload/logic.nut
git commit -m "fix(overload): calibrate laser heights"
```
