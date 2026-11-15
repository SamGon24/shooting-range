# Firing Range

A first-person shooter MVP set on a military-style firing range, built in Godot 4 for testing weapons and gunplay feel. The goal is realistic ballistics (simulated projectiles with gravity and drag, not hitscan) and smooth, responsive movement. Visuals are deliberately greybox.

## Status

**Working now (Milestone 1: movement and greybox range):**

- FPS controller: walk, sprint, crouch, jump and slide, with acceleration and friction rather than instant velocity changes, plus coyote time and a jump buffer.
- Camera feel: head bob, landing dip, slide camera tilt, and an FOV kick when sprinting or sliding. FOV and mouse sensitivity are adjustable and saved between runs.
- Greybox range: firing line, 5 lanes, distance signs and ground stripes at 25/50/100/200/300 m, a backstop, and a movement test area behind the line (steps, a ramp, a crouch tunnel).
- Debug overlay (FPS, frame time, speed, movement state) and a command-line perf probe.

**Not built yet:** weapons, shooting, ballistics, targets, HUD and sound. Next up is Milestone 2 (shooting core). See the [Roadmap](#roadmap).

## Requirements

- **Godot 4.7.2 stable**, the standard build (not .NET). Everything is GDScript.
- **Tested on:** MacBook Pro, Intel i5-8259U, 8 GB RAM, Intel Iris Plus Graphics 655, macOS Sequoia. The target is 60 fps at 1280x720 on this machine.
- **Renderer: Compatibility (OpenGL).** On the target Intel GPU, the Mobile renderer logs shader errors and can't draw a sky or stable sun shadows.

Physics uses Jolt, which is built into Godot 4.4 and later, so nothing extra needs installing.

## Quick start

The commands below assume `godot` points to the Godot binary. On macOS:

```sh
alias godot=/Applications/Godot.app/Contents/MacOS/Godot
```

Clone the repo. The Godot project lives in the `firing-range/` subfolder:

```sh
git clone https://github.com/SamGon24/shooting-range.git
cd shooting-range/firing-range
```

Import once after cloning. This builds the `.godot/` cache, which isn't committed:

```sh
godot --headless --import
```

Run the game:

```sh
godot
```

You can also open `project.godot` in the editor and press F5.

## Controls

| Action | Key |
|---|---|
| Move | W A S D |
| Look | Mouse |
| Sprint | Shift (hold; forward only) |
| Crouch | Ctrl or C (hold) |
| Slide | Crouch while sprinting |
| Jump | Space |
| FOV down / up | `[` / `]` |
| Mouse sensitivity down / up | `-` / `=` |
| Toggle debug overlay | F3 or `\` |
| Release mouse | Esc (click the window to capture it again) |

## Development

### Tests

Unit and integration tests use [GUT](https://github.com/bitwes/Gut), which is vendored in `addons/gut/`. Run them all headless from `firing-range/`:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

The run takes about 50 seconds, because the player tests step real physics ticks. The exit code is non-zero if any test fails.

### Perf probe

The perf probe sprints the player downrange while sweeping the view, measures 10 seconds of frames, prints average fps, 1% low and the worst frame, then quits. Keep the window in front while it runs; macOS paces background windows differently.

```sh
godot -- --perf-probe                              # as played, capped at 60 fps
godot --disable-vsync --max-fps 0 -- --perf-probe  # uncapped, to see headroom
```

The cap comes from `application/run/max_fps=60` in `project.godot`, because OpenGL on macOS doesn't enforce vsync.

### Tuning values

| What | Where |
|---|---|
| Movement: speeds, acceleration, friction, jump, slide, crouch, capsule size | `player/data/movement_default.tres` (fields documented in `player/movement_settings.gd`) |
| Camera feel: head bob, landing dip, slide tilt, FOV kick | Exported properties on the `CameraFeel` node in `player/player.tscn` |
| View settings: FOV, mouse sensitivity, invert Y, bob and FOV-kick scale | Defaults in `player/view_settings.gd`; the player's changes are saved to `user://settings.cfg` |
| Range layout: lanes, marker distances, sign sizes, colours | Exported properties on the root node of `range/range.tscn` (`range/range_builder.gd`) |

### Project structure

```
firing-range/
├── addons/gut/     GUT test framework (vendored, third-party)
├── ballistics/     Projectile simulation (Milestone 3, empty for now)
├── debug/          Debug overlay, perf probe, screenshot pose helper
├── docs/           DECISIONS.md: design and tuning decisions with evidence
├── player/         FPS controller, movement math, camera feel, view settings
│   └── data/       Movement tuning resource (.tres)
├── range/          Greybox range builder, grid shader, main scene
├── targets/        Dummies, steel plates, moving targets (Milestone 4, empty)
├── tests/          GUT tests
├── ui/             HUD and menus (Milestone 5, empty)
└── weapons/        Weapon logic (Milestone 2, empty)
    └── data/       Weapon stat resources (empty)
```

The main scene is `range/range.tscn`. Every scene and resource is text-based (`.tscn`, `.tres`, `.gd`).

## Architecture in brief

- **Fixed 60 Hz physics.** All gameplay runs in `_physics_process` at 60 ticks per second and never depends on frame rate. Physics interpolation smooths rendering between ticks.
- **Pure movement math.** `player/movement_math.gd` holds static, node-free functions for friction, acceleration, slide decay and jump velocity. They're deterministic and unit-tested headless, and `player_controller.gd` calls them.
- **Feel never feeds back into gameplay.** `CameraFeel` only reads player state and moves the camera. Aim and future bullets use `PlayerController.get_eye_position()` and `get_aim_basis()`, which ignore every camera effect.
- **Data-driven tuning.** Numbers live in `Resource` files and exported properties, not in code. Weapon stats will follow the same pattern in `weapons/data/`.
- **Signals over node paths.** The player emits `jumped`, `landed`, `slide_started` and similar signals, and other systems listen to them.

## Roadmap

- [x] **1. Movement:** FPS controller (walk, sprint, crouch, jump, slide), head bob, FOV and sensitivity settings, greybox range with distance markers.
- [ ] **2. Shooting core:** assault rifle and scoped bolt-action sniper, hip fire and ADS, reloads, weapon switching, viewmodel sway and bob, muzzle flash and impact effects.
- [ ] **3. Ballistics and recoil:** simulated projectiles with gravity and drag, damage falloff, recoil patterns and recovery, a debug view of bullet paths.
- [ ] **4. Targets:** humanoid dummies with hit zones and armor plates, pop-down and reset, moving targets on rails, swinging steel plates.
- [ ] **5. Feedback and HUD:** hitmarkers, damage numbers, dynamic crosshair, ammo counter, range stats panel, placeholder sounds.
- [ ] **6. Polish:** physics props, ragdolls, pause and settings menu, performance pass.

## Further reading

- [docs/DECISIONS.md](docs/DECISIONS.md): why things are the way they are (renderer, movement model, tuning, measured performance).
- [CREDITS.md](CREDITS.md): third-party assets and tools.

## License

TBD.
