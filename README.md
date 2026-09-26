# MAKO OVERLOAD

Experimental stage for the CS:S Zombie Escape map `ze_ffvii_mako_reactor_v5_3` (NiDE **test server** only).

The reactor is unstable: an **instability gauge** rises with time and progress, **Sephiroth's lasers track the human group**
(always announced: `!! JUMP !!` / `!! CROUCH !!`), random **Mako surges** change the rules (low gravity, blackout,
bridge flip, laser barrage, zombie rage), then the **reactor overload**: a 150 s escape under fire and Sephiroth's last stand.

- Design: [`docs/superpowers/specs/2026-09-26-mako-overload-design.md`](docs/superpowers/specs/2026-09-26-mako-overload-design.md)
- Implementation plan: [`docs/superpowers/plans/2026-09-26-mako-overload.md`](docs/superpowers/plans/2026-09-26-mako-overload.md)

## Layout

| Path | Content |
|---|---|
| `cstrike/scripts/vscripts/mako_overload/logic.nut` | pure gameplay rules (no engine API) |
| `cstrike/scripts/vscripts/mako_overload/overload.nut` | VScript engine glue, loaded by the `MakoOverloadScript` logic_script |
| `cstrike/addons/sourcemod/configs/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg` | full Mako stripper (all stages + `MODE: MAKO OVERLOAD`), SourceMod Stripper path |
| `cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg` | same file, Metamod Stripper path |
| `cstrike/addons/sourcemod/configs/adminroom/maps/ze_ffvii_mako_reactor_v5_3.cfg` | AdminRoom config (stage `overload` / `14`) |
| `tests/overload/` | logic tests, fake-engine glue tests, stripper wiring checks |
| `tools/check_stripper.py` | stripper checker (braces, unresolved targets, Case > 16, commas in RunScriptCode) |

## Requirements

CS:S **with VScript**, SourceMod, Zombie:Reloaded, Stripper, AdminRoom, and the ZEDDYS cmer / RMZS cmer stages
(MAKO OVERLOAD reuses their laser templates and bridge rotator). Music `sound/music/zeddy/the_qemists_no_more.mp3` on the FastDL.

## Tests

```bash
# build a local Squirrel interpreter once
git clone --depth 1 https://github.com/albertodemichelis/squirrel.git /tmp/squirrel && make -C /tmp/squirrel
SQ=/tmp/squirrel/bin/sq tests/overload/run.sh
python3 tools/check_stripper.py cstrike/addons/stripper/maps/ze_ffvii_mako_reactor_v5_3.cfg "; MODE: MAKO OVERLOAD"
```

## In game

```
sm_rcon changelevel ze_ffvii_mako_reactor_v5_3
sm_stage overload
sm_rcon mp_restartgame 1
```

Console tools: `script Overload_Debug()`, `script Overload_SetGauge(80)`, `script Overload_Surge("lowgrav")`
(`blackout`, `bridge`, `barrage`, `rage`), `script Overload_Laser()`, `script Overload_SetOffsets(36, 66)`, `script Overload_Stop()`.

## Status

Deployed on the test server; in-game validation and laser height calibration in progress.
