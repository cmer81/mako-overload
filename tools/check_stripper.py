#!/usr/bin/env python3
"""Checks a Mako stripper: brace balance, unresolved targets in one section,
commas inside RunScriptCode parameters. Usage: check_stripper.py <cfg> <section marker>"""
import re
import sys

# Map entities verified in the BSP (outputs of the map's huida_e, hammerid 2326)
# that the stripper only references from the escape relays.
KNOWN_MAP_ENTITIES = {"puertas_1", "puertas_2", "xix", "sin_zombis", "puertazm", "props_extreme"}


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
    known |= KNOWN_MAP_ENTITIES
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
