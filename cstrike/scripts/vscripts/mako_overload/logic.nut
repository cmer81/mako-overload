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
