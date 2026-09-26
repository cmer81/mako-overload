// Runs overload.nut against a fake engine to catch runtime errors (undefined names,
// wrong calls) and to check that effects are always restored.
local failures = 0, total = 0;
function check(name, cond) {
	total++;
	if (!cond) { failures++; print("FAIL " + name + "\n"); }
}

// ---------- fake engine ----------
::NOW <- 100.0;
::LOG <- [];
function log(s) { ::LOG.push(s); }
function logged(prefix) { foreach (l in ::LOG) if (l.find(prefix) == 0) return true; return false; }

class Vec { x = 0.0; y = 0.0; z = 0.0; constructor(a, b, c) { x = a; y = b; z = c; } }
::Vector <- function(a, b, c) { return Vec(a.tofloat(), b.tofloat(), c.tofloat()); }

class FakePlayer {
	team = 3; alive = true; pos = null; vel = null; yaw = 0.0; gravity = 1.0; lagged = 1.0; idx = 0;
	constructor(i, t, x, y, z, vx, vy) { idx = i; team = t; pos = Vector(x, y, z); vel = Vector(vx, vy, 0); }
	function GetTeam() { return team; }
	function IsAlive() { return alive; }
	function GetOrigin() { return pos; }
	function GetVelocity() { return vel; }
	function EyeAngles() { return { x = 0.0, y = yaw, z = 0.0 }; }
	function SetGravity(g) { gravity = g; }
	function entindex() { return idx; }
}
class FakeEnt {
	name = ""; kv = null;
	constructor(n) { name = n; kv = {}; }
	function KeyValueFromString(k, v) { kv[k] <- v; }
}
::PLAYERS <- [
	FakePlayer(1, 3, 0, 0, 10, 250, 0),
	FakePlayer(2, 3, 80, 40, 10, 250, 0),
	FakePlayer(3, 2, -2000, 0, 10, 0, 0)
];
::HUD <- FakeEnt("MakoOverloadHud");

::Entities <- {
	function FindByClassname(prev, cls) {
		if (cls != "player") return null;
		local i = (prev == null) ? 0 : ::PLAYERS.find(prev) + 1;
		return i < ::PLAYERS.len() ? ::PLAYERS[i] : null;
	}
	function FindByName(prev, n) { return (prev == null && n == "MakoOverloadHud") ? ::HUD : null; }
};
::NetProps <- {
	function GetPropFloat(e, p) { return e.lagged; }
	function SetPropFloat(e, p, v) { e.lagged = v; }
};
::Time <- function() { return ::NOW; };
::RandomInt <- function(a, b) { return a; };
::RandomFloat <- function(a, b) { return 0.5; };
::TraceLine <- function(a, b, ign) { return 1.0; };
::ClientPrint <- function(p, dest, msg) { log("center:" + msg); };
::ScreenFade <- function(p, r, g, b, a, t, h, f) { log("fade:" + r + " " + g + " " + b + " " + a + " " + f); };
::ScreenShake <- function(c, amp, freq, dur, rad, cmd, air) { log("shake"); };
::EntFire <- function(t, i, v, d, act) { log("fire:" + t + ":" + i + ":" + v + ":" + d); };
::EntFireByHandle <- function(e, i, v, d, a, c) { log("firebyhandle:" + i + ":" + v + ":" + d); };
::AddThinkToEnt <- function(e, f) { log("think:" + f); };
::printl <- function(s) { log("printl:" + s); };
::IncludeScript <- function(n) { dofile("cstrike/scripts/vscripts/" + n); };
::self <- FakeEnt("MakoOverloadScript");

dofile("cstrike/scripts/vscripts/mako_overload/overload.nut");

// ---------- inert until started ----------
Overload_Think();
check("inert before start: no hud", !("message" in ::HUD.kv));
check("console alias exists", "Overload_Debug" in getroottable());

// ---------- start ----------
Overload_Start();
check("think registered", logged("think:Overload_Think"));
check("hud stable", ::HUD.kv.message == "MAKO  [----------]  0%  STABLE");

// respite: no laser during the first 45 s
::LOG.clear();
::NOW += 30.0; Overload_Think();
check("no laser in respite", !logged("fire:EX4ZeddysLaserMaker"));

// gauge grows +1 every 4 s (30 s -> 7)
check("gauge grows with time", gauge == 7);

// after the respite + laser interval a laser is fired behind the group, toward +x
::NOW += 40.0; Overload_Think();
check("laser spawn queued", logged("firebyhandle:RunScriptCode:Overload_Spawn("));
check("jump warning", logged("center:!! JUMP !!"));
::LOG.clear();
Overload_Spawn(-800, 0, 46, 0);
check("laser fired", logged("fire:EX4ZeddysLaserMaker:ForceSpawn"));
check("maker yaw toward group", logged("fire:EX4ZeddysLaserMaker:AddOutput:angles 0 0 0"));

// bonds and cap
Overload_Add(200);
check("cap 95 before escape", gauge == 95);

// surges and restoration
Overload_Surge("lowgrav");
check("surge alert", logged("center:MAKO SURGE: LOW GRAVITY"));
BeginSurge("lowgrav");
check("low gravity applied", ::PLAYERS[0].gravity == 0.35);
::NOW += 11.0; Overload_Think();
check("gravity restored", ::PLAYERS[0].gravity == 1.0 && ::PLAYERS[2].gravity == 1.0);

BeginSurge("rage");
check("zombie faster", ::PLAYERS[2].lagged > 1.29 && ::PLAYERS[0].lagged == 1.0);
::NOW += 7.0; Overload_Think();
check("zombie speed restored", ::PLAYERS[2].lagged == 1.0);

::LOG.clear();
BeginSurge("blackout");
check("blackout fade", logged("fade:0 0 0 235 2"));
EndSurge();
check("blackout purged", logged("fade:0 0 0 235 17"));

::LOG.clear();
BeginSurge("bridge");
check("bridge flipped", logged("fire:puente_1:FireUser2"));
check("bridge restored later", logged("fire:EX3RMZSCmerRotRelay:Trigger::15"));

::LOG.clear();
BeginSurge("barrage");
check("barrage 3 lasers", logged("firebyhandle:RunScriptCode:Overload_Laser(false):3"));

Overload_Surge("nope");
check("unknown surge reported", logged("printl:[MAKO OVERLOAD] unknown surge: nope"));

// death during rage: restoring a zombie that became dead is still safe
BeginSurge("rage");
::PLAYERS[2].alive = false;
Overload_Stop();
check("stop restores speed", ::PLAYERS[2].lagged == 1.0);
check("stop restores gravity", ::PLAYERS[0].gravity == 1.0);
check("stop hud stabilized", ::HUD.kv.message == "MAKO  [##########]  STABILIZED");
::PLAYERS[2].alive = true;

// fresh running instance for the review checks below
active = false; stabilized = false; overload = false; gauge = 0.0; surge = null;
Overload_Start();
respiteUntil = 0.0;

// review 2: rage must not restore a stale speed changed by an item meanwhile
::PLAYERS[2].lagged = 0.0;           // frozen by the ice materia when rage starts
BeginSurge("rage");
::PLAYERS[2].lagged = 1.13;          // ice lifted by the map during rage
EndSurge();
check("rage keeps speed changed by an item", ::PLAYERS[2].lagged == 1.13);
::PLAYERS[2].lagged = 1.0;

// review 3: blackout ends by itself (no stay-out flag)
::LOG.clear();
BeginSurge("blackout");
check("blackout self-ending fade", logged("fade:0 0 0 235 2"));
// review 3: no living human -> effects stop in the think loop
BeginSurge("lowgrav");
foreach (p in ::PLAYERS) if (p.team == 3) p.alive = false;
::NOW += 0.5; Overload_Think();
check("effects end when no human is alive", surge == null && ::PLAYERS[2].gravity == 1.0);
foreach (p in ::PLAYERS) p.alive = true;

// review 1: no surge effect during a respite, or near the bridge for BRIDGE FLIP
respiteUntil = ::NOW + 30.0;
BeginSurge("lowgrav");
check("no surge during respite", surge == null && ::PLAYERS[0].gravity == 1.0);
respiteUntil = 0.0;
::PLAYERS[0].pos = Vector(-9355, 5000, 50);
::LOG.clear();
BeginSurge("bridge");
check("bridge refused when a human is near it", !logged("fire:puente_1:FireUser2"));
::PLAYERS[0].pos = Vector(0, 0, 10);

// ---------- escape (fresh instance) ----------
active = false; stabilized = false; overload = false; gauge = 0.0; surge = null;
Overload_Start();
::LOG.clear();
Overload_EscapeStart();
check("overload gauge 100", gauge == 100.0 && overload);
check("overload message", logged("center:REACTOR OVERLOAD"));
check("overload music", logged("fire:MakoOverloadMusic:PlaySound"));
::LOG.clear();
::NOW += 13.0; Overload_Think();
check("overload laser", logged("firebyhandle:RunScriptCode:Overload_Spawn("));
check("overload explosion", logged("fire:explosion_mako_random:PickRandom"));
check("no surge during escape", !logged("center:MAKO SURGE"));
// review 1: a surge rolled just before the escape must not start during it
BeginSurge("lowgrav");
check("no surge effect after escape start", surge == null && ::PLAYERS[0].gravity == 1.0);

// ---------- no humans: no laser, no crash ----------
foreach (p in ::PLAYERS) if (p.team == 3) p.alive = false;
check("no human -> no laser", Overload_Laser() == false);

// ---------- ending ----------
foreach (p in ::PLAYERS) if (p.team == 3) p.alive = true;
Overload_Laser();                     // warned, spawn queued 1.5 s later
Overload_Ending();
::LOG.clear();
Overload_Spawn(0, 0, 0, 0);           // the queued spawn runs after the ending
check("queued laser cancelled by the ending", !logged("fire:EX4ZeddysLaserMaker:ForceSpawn"));
check("no new laser after ending", Overload_Laser() == false);
::LOG.clear();
::NOW += 10.0; Overload_Think();
check("no laser after ending", !logged("fire:EX4ZeddysLaserMaker"));
Overload_Victory();
Overload_Debug();
check("debug prints", logged("printl:[MAKO OVERLOAD] active="));

print(total + " glue tests, " + failures + " failures\n");
if (failures > 0) throw "glue tests failed";
