#!/usr/bin/env python3
"""When Sephiroth (bahamutend1) dies, the ending lasers must stop for good.

The lasers are enabled by puertafinal -> extreme2_trigger13 -> EX3LaserMode Test, which can
happen AFTER Sephiroth was killed from range. A Disable sent before that Enable is lost, so the
timers and the EX3LaserMode trigger must be killed. Usage: test_sephiroth_lasers.py <stripper.cfg>"""
import re
import sys

text = open(sys.argv[1], encoding="latin1").read()
on_break = []
for block in re.findall(r"modify:\s*\{(.*?)\n\}", text, re.S):
    if re.search(r'"targetname" "bahamutend1"', block) and '"hammerid" "3666"' in block:
        on_break += re.findall(r'"OnBreak" "([^"]*)"', block)

required = ["EX3LaserMode,Kill", "EX3LaserTimer,Kill", "EX3RMZSLaserTimer,Kill",
            "EX3SephirothLocationTimer,Kill", "cortes2,Kill"]
failures = [r for r in required if not any(o.startswith(r + ",") for o in on_break)]
for f in failures:
    print("FAIL bahamutend1 OnBreak missing", f)
print(f"sephiroth lasers: {len(failures)} failures")
sys.exit(1 if failures else 0)
