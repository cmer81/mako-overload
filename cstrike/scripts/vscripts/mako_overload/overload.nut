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
