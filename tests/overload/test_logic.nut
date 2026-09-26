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
check("anchor is the member nearest the centre", c.ax == 0 && c.ay == 0);

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
check("placement from anchor, max 700 + lead", near(shot.x, c.ax - (700 + MOL_MAKER_LEAD)));
check("placement jump height", near(shot.z, c.floorZ + MOL_OFFSETS.jump));
check("placement yaw", near(shot.yaw, 0.0));
check("sephiroth at laser start", near(shot.sephx, c.ax - 700));
local shot2 = MOL_LaserPlacement(c, ds[0], 500.0, "crouch");
check("placement uses clearance - 32", near(shot2.sephx, c.ax - 468));
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
