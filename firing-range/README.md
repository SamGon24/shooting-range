# Firing Range

A first-person shooter MVP set on a military-style firing range, built in Godot 4 for testing weapons and gunplay feel. The goal is realistic ballistics (simulated projectiles with gravity and drag, not hitscan) and smooth, responsive movement. Visuals are deliberately greybox.

## Status

**Built so far (Milestones 1 to 3). Milestone 3 is awaiting its play-test.**

Movement and range (Milestone 1):

- FPS controller: walk, sprint, crouch, jump and slide, with acceleration and friction rather than instant velocity changes, plus coyote time and a jump buffer.
- Camera feel: head bob, landing dip, slide camera tilt, and an FOV kick when sprinting or sliding. FOV and mouse sensitivity are adjustable and saved between runs.
- Greybox range: firing line, 5 lanes, distance signs and ground stripes at 25/50/100/200/300 m, a backstop, and a movement test area behind the line (steps, a ramp, a crouch tunnel).

Shooting core (Milestone 2):

- Two weapons: the Halberd R-5 assault rifle (full-auto, 700 rpm, 850 m/s) and the Longwatch B-9 bolt-action sniper (900 m/s, scoped).
- Simulated projectiles, not hitscan: pooled, moved under gravity every physics tick, with a swept raycast so fast bullets can't pass through thin objects.
- Weapon handling: hip fire and aim down sights (FOV zoom, lower sensitivity, sniper scope overlay), tactical and empty reloads, bolt cycling, and weapon switching with raise and lower times. Sprinting blocks firing and aiming.
- Greybox viewmodels with sway, bob, inertia and recoil kick, a muzzle flash, impact sparks and marks, and placeholder sounds generated in code.
- Minimal HUD: crosshair, weapon name and ammo counter.
- Debug overlay (FPS, frame time, speed, movement state), a command-line perf probe, and a hit logger.

Ballistics and recoil (Milestone 3):

- Quadratic air drag from each bullet's mass, diameter and drag coefficient. The rifle round slows from 850 to about 600 m/s by 300 m and drops 78 cm there; the sniper round keeps about 720 m/s and drops 63 cm.
- Damage falloff by distance: the rifle does 32, falling to 70% by 200 m; the sniper does 110, falling to 80% by 400 m. Every hit reports its damage, ready for targets.
- Per-weapon recoil patterns plus random deviation, a little lighter while aimed. The kick moves the real aim. After a short pause the view recovers, and recoil you have already pulled down is not recovered a second time.
- Spread: a hip-fire cone plus bloom that builds per shot and settles after a pause. Both weapons have zero aimed spread, so the first aimed shot from a settled weapon goes exactly where the sights point.
- A debug view of bullet paths (F4): each bullet's simulated path, coloured from yellow to red as it slows, with a cross at the impact.

**Not built yet:** targets (Milestone 4) and the full HUD (Milestone 5). Shots currently hit only the ground, walls and props. See the [Roadmap](#roadmap).

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
| Fire | Left mouse button |
| Aim down sights | Right mouse button (hold) |
| Reload | R |
| Switch weapon | 1 / 2, or mouse wheel |
| FOV down / up | `[` / `]` |
| Mouse sensitivity down / up | `-` / `=` |
| Toggle debug overlay | F3 or `\` |
| Toggle bullet paths | F4 |
| Release mouse | Esc (click the window to capture it again) |

## Development

### Tests

Unit and integration tests use [GUT](https://github.com/bitwes/Gut), which is vendored in `addons/gut/`. Run them all headless from `firing-range/`:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

The run takes about a minute and a half, because the player and weapon tests step real physics ticks. The exit code is non-zero if any test fails.

### Perf probe

The perf probe sprints the player downrange while sweeping the view, measures 10 seconds of frames, prints average fps, 1% low and the worst frame, then quits. Keep the window in front while it runs; macOS paces background windows differently.

```sh
godot -- --perf-probe                              # as played, capped at 60 fps
godot --disable-vsync --max-fps 0 -- --perf-probe  # uncapped, to see headroom
godot -- --perf-probe --perf-fire                  # walking and firing full-auto
```

The cap comes from `application/run/max_fps=60` in `project.godot`, because OpenGL on macOS doesn't enforce vsync.

### Debug arguments

These go after `--` on the command line and are mainly for Movie Maker captures and automated checks.

| Argument | Effect |
|---|---|
| `--pose=x,y,z,yaw,pitch` | Places the player (metres and degrees; yaw 0 looks downrange) |
| `--hold=action[@seconds],...` | Presses input actions and keeps them down, each from the given time |
| `--log-hits` | Prints every projectile hit: what it hit, where, flight time and speed |
| `--hide-overlay` | Starts with the debug overlay hidden |
| `--bullet-paths` | Starts with the bullet path view on |

For example, switch to the sniper, aim at the 100 m line, fire, and log the hit:

```sh
godot --quit-after 200 -- --pose=0,0,0,0,-0.96 --hold=weapon_2,aim@1.2,fire@1.8 --log-hits
```

For Movie Maker captures, add `--always-on-top`. macOS throttles a Godot window that isn't in front, and Movie Maker then writes the same frame over and over.

### Tuning values

| What | Where |
|---|---|
| Movement: speeds, acceleration, friction, jump, slide, crouch, capsule size | `player/data/movement_default.tres` (fields documented in `player/movement_settings.gd`) |
| Camera feel: head bob, landing dip, slide tilt, FOV kick | Exported properties on the `CameraFeel` node in `player/player.tscn` |
| View settings: FOV, mouse sensitivity, invert Y, bob and FOV-kick scale | Defaults in `player/view_settings.gd`; the player's changes are saved to `user://settings.cfg` |
| Weapon stats: fire rate, magazine, reload times, recoil pattern and recovery, spread and bloom, ADS time, FOV and sensitivity, bolt cycle, raise and lower times, viewmodel poses and kick | `weapons/data/halberd_rifle.tres` and `weapons/data/longwatch_sniper.tres` (fields documented in `weapons/weapon_data.gd`) |
| Bullet stats: muzzle velocity, damage and falloff, mass, diameter, drag coefficient | The `projectile` sub-resource inside each weapon `.tres` (fields documented in `ballistics/projectile_spec.gd`) |
| Air density | Exported on the `Projectiles` node in `range/range.tscn` |
| Bullet path view: paths kept, colours, impact cross size | Exported properties on the `BulletPaths` node in `range/range.tscn` |
| Viewmodel motion: sway, bob, inertia, kick spring, sprint and reload poses, muzzle flash | Exported properties on the `WeaponView` node in `player/player.tscn` |
| Impact effects: mark size and count, sparks, impact volume | Exported properties on the `ImpactEffects` node in `range/range.tscn` |
| Weapon sound volumes | Exported properties on the `Weapons/Audio` node in `player/player.tscn` |
| Range layout: lanes, marker distances, sign sizes, colours | Exported properties on the root node of `range/range.tscn` (`range/range_builder.gd`) |

### Project structure

```
firing-range/
├── addons/gut/       GUT test framework (vendored, third-party)
├── ballistics/       Projectile spec, integration math and the pooled projectile system
├── debug/            Debug overlay, perf probe, pose and hold helper, hit logger, bullet paths
├── docs/             DECISIONS.md: design and tuning decisions with evidence
├── player/           FPS controller, movement math, camera feel, view settings
│   └── data/         Movement tuning resource (.tres)
├── range/            Greybox range builder, grid shader, main scene
├── targets/          Dummies, steel plates, moving targets (Milestone 4, empty)
├── tests/            GUT tests
├── ui/               HUD, crosshair and scope overlay
└── weapons/          Weapon stats, state machine, recoil and spread, controller and viewmodel
    ├── data/         One stat resource per weapon (.tres)
    ├── effects/      Impact effects, generated sounds, weapon audio
    └── viewmodels/   Greybox first-person weapon models
```

The main scene is `range/range.tscn`. Every scene and resource is text-based (`.tscn`, `.tres`, `.gd`).

## Architecture in brief

- **Fixed 60 Hz physics.** All gameplay runs in `_physics_process` at 60 ticks per second and never depends on frame rate. Physics interpolation smooths rendering between ticks.
- **Pure movement math.** `player/movement_math.gd` holds static, node-free functions for friction, acceleration, slide decay and jump velocity. They're deterministic and unit-tested headless, and `player_controller.gd` calls them.
- **Simulated, pooled projectiles.** `ballistics/projectile_system.gd` keeps every bullet as a row in packed arrays, not a node. Each tick it integrates gravity and drag (one RK4 step, in `ballistics/projectile_math.gd`), raycasts from the old position to the new one, then emits `projectile_hit` with the damage after falloff.
- **Node-free weapon logic.** `weapons/weapon_logic.gd` is a state machine that takes a `WeaponInput` and a time step, so fire rate, reloads and aim timing are tested to the tick. `weapons/recoil_logic.gd` does the same for recoil pattern, recovery and spread. `weapon_controller.gd` feeds both from the input map and applies the kick to the player's recoil offset.
- **Feel never feeds back into gameplay.** `CameraFeel` and `WeaponView` only read gameplay state. Bullets leave from `PlayerController.get_eye_position()` along `get_aim_basis()` (look angles plus recoil, then spread), which ignore head bob, viewmodel kick and every other effect.
- **Data-driven tuning.** Numbers live in `Resource` files and exported properties, not in code. Each weapon is one `.tres` in `weapons/data/`.
- **Signals over node paths.** The player, weapon controller and projectile system emit signals (`landed`, `shot_fired`, `projectile_hit` and so on), and effects, audio and the HUD listen to them.

## Roadmap

- [x] **1. Movement:** FPS controller (walk, sprint, crouch, jump, slide), head bob, FOV and sensitivity settings, greybox range with distance markers.
- [x] **2. Shooting core:** assault rifle and scoped bolt-action sniper, hip fire and ADS, reloads, weapon switching, viewmodel sway and bob, muzzle flash and impact effects.
- [x] **3. Ballistics and recoil:** simulated projectiles with gravity and drag, damage falloff, recoil patterns and recovery, a debug view of bullet paths. Built; play-test pending.
- [ ] **4. Targets:** humanoid dummies with hit zones and armor plates, pop-down and reset, moving targets on rails, swinging steel plates.
- [ ] **5. Feedback and HUD:** hitmarkers, damage numbers, dynamic crosshair, ammo counter, range stats panel, placeholder sounds.
- [ ] **6. Polish:** physics props, ragdolls, pause and settings menu, performance pass.

## Further reading

- [docs/DECISIONS.md](docs/DECISIONS.md): why things are the way they are (renderer, movement model, tuning, measured performance).
- [CREDITS.md](CREDITS.md): third-party assets and tools.

## License

TBD.
