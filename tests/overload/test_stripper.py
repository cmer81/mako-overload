#!/usr/bin/env python3
"""Checks the MAKO OVERLOAD wiring in the stripper (semantic checks the generic checker cannot do)."""
import re
import sys

S = open("cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg", encoding="latin1").read()


def block(targetname):
    m = re.search(r'\{[^{}]*"targetname" "%s"[^{}]*\}' % re.escape(targetname), S)
    return m.group(0) if m else ""


failures = []
relay, ex2 = block("LevelRelayMakoOverload"), block("LevelRelayExtreme2")
# the final Bahamut chase must be the Extreme II one (spec 6.2)
for line in re.findall(r'"OnTrigger" "((?:ffsaf|sephi2),[^"]*)"', ex2):
    if line not in relay:
        failures.append("EX2 chase setup missing in LevelRelayMakoOverload: " + line)
# value 17 is routed through LevelCase2 (logic_case has 16 cases max)
case2 = block("LevelCase2")
if '"Case01" "17"' not in case2 or "LevelRelayMakoOverload,Trigger" not in case2:
    failures.append("LevelCase2 does not route 17 to LevelRelayMakoOverload")
if '"OnDefault" "LevelCase2,InValue,,0,-1"' not in block("LevelCase"):
    failures.append("LevelCase does not forward unknown values to LevelCase2")
# the map's 130 s escape must not run in this stage
if "huida_e,Enable" in relay:
    failures.append("huida_e enabled in MAKO OVERLOAD (150 s escape expected)")

for f in failures:
    print("FAIL", f)
print(f"stripper checks: {len(failures)} failures")
sys.exit(1 if failures else 0)
