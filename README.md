# Preemptive Peril

[![CI](https://github.com/Quesadius/preemptive-peril/actions/workflows/ci.yml/badge.svg)](https://github.com/Quesadius/preemptive-peril/actions/workflows/ci.yml)

A turn-based grid tactics game built in Godot 4 with GDScript. Command an army of infantry, tanks, artillery and transports, capture cities for income, build reinforcements at factories, and break the enemy commander before they break you.

**Status:** playable against the computer on one map, *Crossroads*, with pixel art from Kenney's Tiny Battle pack. There is no audio yet.

![The Crossroads map at the start of a match: red's army and base on the left, blue's on the right, neutral cities in between](docs/screenshots/crossroads.png)

## Running the game

You need [Godot](https://godotengine.org/) 4.6 or newer (CI uses 4.7).

- **From the editor:** open `project.godot` and press **F5**.
- **From a terminal**, in the repository root:

  ```bash
  godot --path .
  ```

- **The small code-built demo map** instead of Crossroads:

  ```bash
  godot --path . -s tools/preview_battle.gd ++ demo
  ```

## How to play

You command red (CO Vale). The computer commands blue (CO Rook) and plays its turn automatically after you end yours.

![A red medium tank selected: its movement range is shaded and a blue arrow traces its route to the crossroads](docs/screenshots/crossroads_move.png)

*Moving a unit: the shaded tiles are its range and the arrow is the route you've traced. The blue infantry's "6" badge shows a damaged unit's HP; full-strength units show no badge.*

| Key | Action |
|---|---|
| Arrow keys | Move the cursor; while choosing a target, cycle between targets |
| Enter / Space | Confirm |
| Esc | Back out one step |
| D | Show or hide the enemy danger map |
| + / − or mouse wheel | Zoom |

What **Enter** does depends on what is under the cursor:

- **One of your units** shows where it can move (blue). Trace a route with the cursor, then confirm a destination to open its orders: Wait, Attack, Capture, Load, Unload, Supply or Join, whichever apply there. Attacking snaps the cursor to a target and shows the damage forecast. A unit turns grey once it has acted.
- **An enemy unit** shows where it can move (blue) and everything it could hit next turn (red).
- **An empty factory you own** opens the build menu.
- **Any other empty tile** opens the system menu: **End Turn**, plus your CO power once its meter is full.

**Economy and capture.** Each property you own pays 1,000 funds at the start of your turn, and your units standing on your properties are repaired and resupplied. Infantry and mechs capture cities, factories and HQs. A property needs 20 capture points, and each turn adds the capturing unit's displayed HP, so healthy units capture faster.

**Winning.** Each side has an HQ, the gold tile in its home base. Capture the enemy HQ and you win on the spot. A player is also eliminated when they have no units left and no factory to rebuild from. When the match ends, a Victory or Defeat message appears; press **Enter** to play again.

## Development

The project follows a strict split between rules and presentation:

```
input -> Action -> Rules.validate() -> Rules.apply() -> Array[GameEvent] -> animation
```

- `core/`, `ai/` and `data/` are **pure**: no nodes, signals, scenes or rendering, so the whole game runs headless. A purity check enforces this.
- `ActionGenerator` is the single source of what is legal. The UI menus and the AI both use it.
- The game is **deterministic**. All randomness comes from one seeded generator in the game state, so a save is just the starting setup plus the list of actions, and replaying it reproduces the match exactly.
- Balance values live in `.tres` resources under `data/`, not in code.

| Directory | Contents |
|---|---|
| `core/` | Game state, actions, events, and the rules modules (movement, combat, fog, economy, …) |
| `ai/` | The computer opponent and its scoring maps |
| `data/` | Resource schemas plus the unit, terrain, CO, ruleset and map data |
| `persistence/` | JSON saves and deterministic replay |
| `presentation/`, `ui/` | Rendering, input, animation, HUD and menus |
| `autoload/` | Settings, audio and scene routing |
| `tools/` | Test runner, purity check, map-editing helpers, preview boot script |
| `tests/` | gdUnit4 tests, mirroring `core/` |
| `docs/` | Architecture outline, Godot notes, exporting guide |

[`docs/architecture.md`](docs/architecture.md) is the authoritative design document.

### Running the tests

```bash
./tools/run_tests.sh
```

This runs the purity check, `gdlint`, a parse check of every script, and the full gdUnit4 suite headless. gdUnit4 is included under `addons/`. Linting needs [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit):

```bash
pip install "gdtoolkit==4.*"
```

If `godot` isn't on your `PATH`, point the script at it with `GODOT_BIN=/path/to/godot`. CI runs the same script on every push, then builds Linux, Windows and Web exports. See [`docs/exporting.md`](docs/exporting.md) for exporting locally.

## License

Preemptive Peril is released under the [MIT License](LICENSE), copyright Quesadius. The bundled [gdUnit4](addons/gdUnit4) test framework keeps its own MIT license.

Art: [Tiny Battle](https://kenney.nl/assets/tiny-battle) by [Kenney](https://www.kenney.nl), released under [CC0](assets/tiny_battle/License.txt). Medium tanks and rockets borrow the tank and artillery sprites for now, marked *MD* and *RK*.
