# Firing Range

A first-person shooter MVP set on a military-style firing range, built in Godot 4 for testing weapons and gunplay feel. The goal is realistic ballistics (simulated projectiles with gravity and drag, not hitscan) and smooth, responsive movement. Visuals are deliberately greybox.

## Status

**Built so far (Milestones 1 to 5). Feedback and HUD are ready for play-testing.**

Movement and range (Milestone 1):

- FPS controller: walk, sprint, crouch, jump and slide, with acceleration and friction rather than instant velocity changes, plus coyote time and a jump buffer.
- Camera feel: head bob, landing dip, slide camera tilt, and an FOV kick when sprinting or sliding. FOV and mouse sensitivity are adjustable and saved between runs.
- Greybox range: firing line, 5 lanes, distance signs and ground stripes at 25/50/100/200/300 m, a backstop, and a movement test area behind the line (steps, a ramp, a crouch tunnel).

Shooting core (Milestone 2):

- Two weapons: the Halberd R-5 assault rifle (full-auto, 700 rpm, 850 m/s) and the Longwatch B-9 bolt-action sniper (900 m/s, scoped).
- Simulated projectiles, not hitscan: pooled, moved under gravity every physics tick, with a swept raycast so fast bullets can't pass through thin objects.
- Weapon handling: hip fire and aim down sights (FOV zoom, lower sensitivity, sniper scope overlay), tactical and empty reloads, bolt cycling, and weapon switching with raise and lower times. Sprinting blocks firing and aiming.
- Greybox viewmodels with sway, bob, inertia and recoil kick, a muzzle flash, impact sparks and marks, and placeholder sounds generated in code.
- Weapon name, ammo counter and scope overlay, extended by the Milestone 5 HUD below.
- Debug overlay (FPS, frame time, speed, movement state), a command-line perf probe, and a hit logger.

Ballistics and recoil (Milestone 3):

- Quadratic air drag from each bullet's mass, diameter and drag coefficient. The rifle round slows from 850 to about 600 m/s by 300 m and drops 78 cm there; the sniper round keeps about 720 m/s and drops 63 cm.
- Damage falloff by distance: the rifle does 32, falling to 70% by 200 m; the sniper does 110, falling to 80% by 400 m. Every hit reports its damage, ready for targets.
- Per-weapon recoil patterns plus random deviation, a little lighter while aimed. The kick moves the real aim. After a short pause the view recovers, and recoil you have already pulled down is not recovered a second time.
- Spread: a hip-fire cone plus bloom that builds per shot and settles after a pause. Both weapons have zero aimed spread, so the first aimed shot from a settled weapon follows its calibrated bore direction without spread. Both weapons are zeroed at 100 m.
- A debug view of bullet paths (F4): each bullet's simulated path, coloured from yellow to red as it slows, with a cross at the impact.

Targets (Milestone 4):

- Six solid humanoid hit zones: head, torso, two arms and two legs. Head damage is 1.5× (2× for the sniper), torso 1×, limbs 0.8×.
- 100 health and 0–3 armor plates of 50 each. Armor absorbs damage first, with overflow reaching health. A killed dummy folds down, ignores shots and returns fully restored after 3 seconds.
- Stationary dummies at 25/50/100/200/300 m, staggered from left to right. Their armor counts are 0/1/2/3/0 respectively.
- Walk (1.5 m/s, left) and sprint (6 m/s, right) movers at both 50 and 100 m on 4 m rails. Movers are unarmored and keep travelling while down.
- Hinged steel at 100/200/300 m swings from bullet momentum and plays a generated placeholder ring.

Feedback and HUD (Milestone 5):

- White hitmarkers, blue markers when any armor plate breaks, and a red X on kills. Kill feedback takes priority over an armor break in the same hit.
- Floating damage numbers anchored at the hit point: white for body / limb hits and amber for headshots. Values include zone multipliers and overkill, rounded to the nearest whole point.
- A crosshair that projects the current spread cone, including bloom, through the active camera FOV. It hides when ADS passes halfway; hitmarkers remain visible while aiming and scoped.
- An always-visible gameplay FPS readout and ammo counter. F3 still controls only the separate diagnostic overlay.
- A range stats panel with shots, target hits, accuracy, headshot percentage and time to kill on the last killed dummy. **T** resets stats and clears hitmarkers and damage numbers.
- Distinct original placeholder hit, armor-break and kill confirmation chirps, synthesized before play and credited in `CREDITS.md`.

**Not built yet:** Milestone 6 polish. See the [Roadmap](#roadmap).

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
| Reset range stats, hitmarkers and damage numbers | T |
| Release mouse | Esc (click the window to capture it again) |

## Development

### Tests

Unit and integration tests use [GUT](https://github.com/bitwes/Gut), which is vendored in `addons/gut/`. Run them all headless from `firing-range/`:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

The run takes about two minutes, because the player and weapon tests step real physics ticks. The exit code is non-zero if any test fails.

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
| Weapon stats: sight zero distance and height, fire rate, magazine, reload times, recoil pattern and recovery, spread and bloom, ADS time, FOV and sensitivity, bolt cycle, raise and lower times, viewmodel poses and kick | `weapons/data/halberd_rifle.tres` and `weapons/data/longwatch_sniper.tres` (fields documented in `weapons/weapon_data.gd`) |
| Bullet stats: muzzle velocity, damage and falloff, mass, diameter, drag coefficient | The `projectile` sub-resource inside each weapon `.tres` (fields documented in `ballistics/projectile_spec.gd`) |
| Dummy health, plate strength, default armor, zone multipliers, pop-down and reset times | `targets/data/dummy_default.tres` (`targets/target_settings.gd`) |
| Target layout, armor by distance, rail length and speeds | Target exports and `_build_targets()` in `range/range_builder.gd` |
| Steel size, mass, impulse scale, hinge limits and ring volume / attenuation | Exported properties in `targets/steel_plate.gd` |
| Projectile weapon class (sniper head multiplier) | `weapon_class` in the weapon's projectile sub-resource |
| Air density | Exported on the `Projectiles` node in `range/range.tscn` |
| Bullet path view: paths kept, colours, impact cross size | Exported properties on the `BulletPaths` node in `range/range.tscn` |
| Viewmodel motion: sway, bob, inertia, kick spring, sprint and reload poses, muzzle flash | Exported properties on the `WeaponView` node in `player/player.tscn` |
| Impact effects: mark size and count, sparks, impact volume | Exported properties on the `ImpactEffects` node in `range/range.tscn` |
| HUD: ADS hide threshold, FPS and stats refresh intervals | Root exports in `ui/hud.gd` / `ui/hud.tscn` |
| Crosshair: base gap, line / dot size, colors; spread source | Exports in `ui/crosshair.gd`; weapon spread / bloom in `weapons/data/*.tres` |
| Hitmarkers: timing, geometry, colors; damage numbers: pool, lifetime, rise, font and colors | Exports in `ui/feedback_view.gd` (the `FeedbackView` child in `ui/hud.tscn`) |
| Confirmation audio: volumes, pitches, durations, polyphony | Exports in `ui/feedback_audio.gd` (the `FeedbackAudio` child in `ui/hud.tscn`); synthesis in `weapons/effects/sfx_factory.gd` |
| HUD layout, fonts, panel background and margins | `ui/hud.tscn` |
| Stats reset binding | `range_stats_reset` in `project.godot` (T) |
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
├── targets/          Dummy health, hit zones, rail carriers, hinged steel and tuning
├── tests/            GUT tests
├── ui/               HUD, pooled feedback, confirmation audio, range stats, crosshair and scope overlay
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
- **Feel never feeds back into gameplay.** `CameraFeel` and `WeaponView` only read gameplay state. Bullets leave a fixed sight height below `PlayerController.get_eye_position()`, along `get_aim_basis()` plus the equipped weapon’s numerical zero angle and spread, which ignore head bob, viewmodel kick and every other effect.
- **Data-driven tuning.** Numbers live in `Resource` files and exported properties, not in code. Each weapon is one `.tres` in `weapons/data/`.
- **Signals over node paths.** The player, weapon controller and projectile system emit signals (`landed`, `shot_fired`, `projectile_hit` and so on), and effects, audio and the HUD listen to them.

## Roadmap

- [x] **1. Movement:** FPS controller (walk, sprint, crouch, jump, slide), head bob, FOV and sensitivity settings, greybox range with distance markers.
- [x] **2. Shooting core:** assault rifle and scoped bolt-action sniper, hip fire and ADS, reloads, weapon switching, viewmodel sway and bob, muzzle flash and impact effects.
- [x] **3. Ballistics and recoil:** simulated projectiles with gravity and drag, damage falloff, recoil patterns and recovery, a debug view of bullet paths. Built; play-test pending.
- [x] **4. Targets:** humanoid dummies with hit zones and armor plates, pop-down and reset, moving targets on rails, swinging steel plates. Built; play-test pending.
- [x] **5. Feedback and HUD:** hitmarkers, damage numbers, dynamic crosshair, ammo counter and FPS, resettable range stats, placeholder sounds. Built; play-test pending.
- [ ] **6. Polish:** physics props, ragdolls, pause and settings menu, performance pass.

## Range stats definitions

A shot counts when a projectile actually launches. A hit counts once when that projectile damages a dummy or rings steel; walls, ground and shots through a down dummy are misses. Accuracy is target hits / shots × 100. Headshot percentage is dummy head hits / all target hits × 100, so steel hits are included in the denominator. Empty percentages read 0.0%.

Time to kill is measured in physics time from the first damaging hit on each dummy life to its killing hit. Interleaved targets keep separate timers. One-shot kills read 0.000 s; the panel holds the last completed kill until the next kill or reset. Steel has no TTK. Reset clears active timers and excludes already-flying rounds from the new stats session, while still showing their real damage feedback. It does not refill ammo or restore targets. Counters record immediately; the panel refreshes at 5 Hz, with reset displayed immediately.

## Feedback and HUD play-test

1. Run the game. Confirm the top-right FPS and stats panel, bottom-right weapon and ammo, and hip crosshair. Toggle F3; the gameplay HUD should remain visible.
2. Press T. Fire one shot into the ground: shots should become 1, hits 0, accuracy 0.0%.
3. Line up with the unarmored 25 m dummy in the leftmost lane (x = -13.2 m). Use rifle torso taps: expect white markers and white numbers. Aim at the head: numbers should be amber. On a kill, expect a red X and updated TTK.
4. Shoot the armored 50 m dummy in the next lane (x = -7.2 m). Break its 50-point plate: expect a blue marker and descending break chirp. A hit that both breaks armor and kills should show the red X and kill chirp.
5. Hold rifle fire from the hip, then release it. The crosshair should expand with bloom and settle again. ADS should hide it; hitmarkers and damage numbers should still appear. Repeat scoped with the sniper.
6. Reset and make an unarmored sniper one-shot kill: shots 1, hits 1, accuracy 100.0%, headshots 100.0% if aimed at the head, last TTK 0.000 s. Wait for the dummy reset and repeat; the previous life must not extend the next TTK.
7. Shoot steel. Expect a white marker, the physical ring plus a hit chirp, one target hit, no damage number and no change to the last TTK.
8. Press T while a long shot is flying. The old round can still cause feedback, but it must not add a hit to the freshly reset counters. Confirm ammo and target state remain unchanged by T.
9. Run `godot --always-on-top -- --perf-probe --perf-fire`. Check the full HUD remains active and the capped average stays near 60 fps.

## Target play-test

- Walk across the firing stalls to line up with the staggered stationary dummies. Check head, torso and limb hits with both weapons; the 25 m and 300 m stationary dummies are unarmored.
- Shoot armored dummies until they fold down. Check that shots pass through during the 3 s downtime and that armor and health return together.
- Track the movers at 50 and 100 m, watching the end reversals and resets while moving.
- Shoot steel at 100/200/300 m and check swing direction, settling and ring audibility. Bullet drop still applies; F4 helps inspect misses.
- Judge silhouette readability, armor durability, pop-down feel and distant ring volume. Hitmarkers, damage numbers and confirmation sounds are now available for this check.

## Further reading

- [docs/DECISIONS.md](docs/DECISIONS.md): why things are the way they are (renderer, movement model, tuning, measured performance).
- [CREDITS.md](CREDITS.md): third-party assets and tools.

## License

TBD.
