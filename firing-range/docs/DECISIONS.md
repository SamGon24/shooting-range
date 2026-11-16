# Decisions

Non-obvious choices, newest milestone last. Each entry says what was chosen, why, and what would make us revisit it.

Target machine for every measurement below: MacBook Pro, Intel i5-8259U, 8 GB, Intel Iris Plus Graphics 655, macOS Sequoia, Godot 4.7.2 stable.

## Project setup

### Renderer: Mobile, with three restrictions on this GPU (superseded)

**Superseded:** the project now uses Compatibility. See "Renderer switch to Compatibility" at the end of this file. This entry is kept as the evidence for that switch.

Mobile holds 60 fps with a wide margin (see Performance), so the rule in `CLAUDE.md` at the time said stay on it. On this Intel GPU it runs through Vulkan on MoltenVK, and three things do not work:

| Problem | Evidence | What we do |
|---|---|---|
| 8 engine compute pipelines fail to compile at startup (`Compute pipeline compile failed ... AIR builtin function was called but no definition was found`) | Happens with an empty scene, before any project code runs | Nothing we can fix. They are logged on every windowed boot. Avoid engine features that need compute shaders. |
| A `Sky` background triggers 14 more errors on the first frame, and sky-based ambient light renders black or blocky | Reproduced in a 3-node test scene; gone with a colour background | Background is a flat colour, ambient light is a fixed colour, reflections are off. No `Sky` resource anywhere. |
| Sun shadows misrender while the camera turns upward: the far shadow cascade marks the whole ground as shadowed for those frames | Scripted jerky-camera capture: 2 splits about 40% of the lower frame dark, 4 splits about 20%, single cascade about 90%. A still camera is fine. Not caused by physics interpolation (same result with it off). | The sun's `shadow_enabled` is off. Shapes are read from direct light plus ambient only. |

The Compatibility renderer has none of these problems on this machine: zero startup errors and clean sun shadows in the same jerky-camera test. It is slower here (about 174 fps with shadows, against about 300 fps for Mobile without) but still nearly three times the budget.

**Outcome:** the project owner approved the switch after Milestone 1.

### HiDPI off

`display/window/dpi/allow_hidpi=false`. The built-in display is Retina, so with HiDPI on a 1280x720 window renders 2560x1440 pixels, four times the fill cost. The perf probe prints the real window pixel size to confirm 1280x720.

### Physics interpolation on

`physics/common/physics_interpolation=true`. Gameplay runs only at the 60 Hz tick. Interpolation keeps the camera smooth when a rendered frame does not line up with a tick. The camera rig is `top_level` with interpolation off and follows the body's interpolated transform each frame, so mouse look has no added latency.

### Static typing enforced

`debug/gdscript/warnings/untyped_declaration=2` makes an untyped declaration a parse error. The unsafe access and cast warnings are on as warnings. Addons are excluded by the engine default.

### GUT 9.7.1, vendored

9.7.x is the GUT line for Godot 4.7. It lives in `addons/gut/` and is committed, so tests run from a fresh clone after `godot --headless --import`.

### Repository layout

The git repository root is `SHOOTER/` (holding `CLAUDE.md`); the Godot project root is `SHOOTER/firing-range/`. All Godot commands run with `--path firing-range` or from inside that folder.

## Milestone 1: movement and greybox range

### Movement model: friction plus capped acceleration

Ground movement is friction followed by acceleration toward a wish velocity, the classic arena-shooter model, because it gives momentum for free: speed builds over about 0.2 s, direction changes carry sideways drift, and releasing the keys coasts to a stop.

Two deliberate changes from the classic model:

- **Acceleration is capped.** Input can redirect momentum but never push horizontal speed above `max(speed before, target speed)`. The uncapped version overshoots when accelerating at an angle to the current velocity. That is the strafe-jump exploit in the air, and a first test run showed it also gave 7.28 m/s against a 7.0 m/s sprint when turning on the ground. Top speed is now exactly the configured value. The same capped function does air control and slide steering.
- **Friction is integrated exactly** (exponential above `stop_speed`, linear below), so its result does not depend on tick rate.

### Slide: constant deceleration

A slide is kinetic friction, so speed falls linearly at `slide_deceleration` until `slide_end_speed`, then becomes a crouch. Duration and distance have closed forms (`MovementMath.slide_duration`, `slide_distance`) that the tests check against the simulation. Slopes do not affect slide speed yet; the range is flat apart from one test ramp.

A slide starts from speed, not from the sprint key: crouch while moving at or above `slide_min_entry_speed` (5.5 m/s, above walk speed). The entry boost has a cooldown so chained slides cannot build speed.

### Gravity as two half steps

Each airborne tick applies half of gravity before the move and half after (velocity Verlet). The jump arc then matches the analytic parabola: the tested apex is within 2 mm of `jump_height` in pure math and within 3 cm on the Jolt body. Jump velocity is derived from `jump_height` and gravity rather than tuned directly.

### Stance changes the collider, feel changes the camera

Crouch and slide shrink the capsule from the top (feet stay planted) at `crouch_transition_speed`. Standing back up is refused while a body test says there is no headroom. The gameplay eye is always `collider height - eye_offset_from_top`; `PlayerController.get_eye_position()` and `get_aim_basis()` are the origin and direction that bullets will use.

Head bob, landing dip, slide camera drop and roll, and the sprint/slide FOV kick are all in `CameraFeel`, which only reads from the player. They cannot change movement or, later, hit results.

### FOV is stored as vertical degrees

Godot cameras take vertical FOV. The default is 65 vertical, about 97 horizontal at 16:9. The overlay shows both.

### No stair stepping yet

`CharacterBody3D` does not step up ledges. The three steps in the test area (0.5 m each) are meant to be jumped. If targets or props later need walkable low ledges, add a step-up shape cast then.

### Range is generated, not hand-placed

`range/range_builder.gd` builds ground, walls, lanes, markers and the test area in `_ready` from exported numbers, so every distance has one source and the scene file stays small. Signs grow with distance (digit height is 2% of distance) to stay readable from the line, and each sign is pushed sideways until it clears the one behind it as seen from the firing line.

The ground uses a world-space grid shader (1 m cells, heavier lines every 5 m). A flat colour gives no motion cue, which makes movement feel impossible to judge.

### Tuning starting points

Walk 4.5, sprint 7.0, crouch 2.2 m/s. Ground accel 9 /s against friction 6 /s reaches walk speed in about 0.18 s and stops in about 0.26 s. Jump height 0.65 m under 9.81 m/s². Slide: +1.5 m/s boost capped at 9, deceleration 6 m/s², so a sprint slide lasts about 0.9 s over about 5.3 m. These are first guesses for play-testing, all in `player/data/movement_default.tres`.

### Automated runs never grab the mouse

The player captures the mouse only in a normal windowed run. Headless runs, Movie Maker captures and the perf probe set `mouse_look_enabled = false`. Before this, Movie Maker captures picked up real mouse movement and produced frames with a turned camera.

### Performance (Milestone 1)

Measured with `godot --path . --disable-vsync -- --perf-probe`: 10 s sprinting downrange while sweeping the view 50 degrees each way, 1280x720 window.

| Configuration | Average | 1% low | Frames over 16.67 ms |
|---|---|---|---|
| Mobile, no sun shadow (shipped) | 306 fps | 169 fps | 1 of 3062 |
| Mobile, sun shadow 2 splits | 263 fps | 186 fps | 1 of 2630 |
| Compatibility, sun shadow 2 splits | 174 fps | 114 fps | 0 of 1736 |
| Mobile, no sun shadow, vsync on | 60.0 fps | 55.5 fps | none over 25 ms |

The scene is 42 draw calls and about 1,100 primitives. The single slow frame in the uncapped runs is a one-off hitch (worst 33.5 ms), not a pattern.

## Renderer switch to Compatibility (after Milestone 1)

### Renderer: Compatibility (OpenGL 4.1)

`rendering/renderer/rendering_method="gl_compatibility"`. The project owner approved the switch because Mobile's faults on the target GPU were correctness problems, not frame rate (see the superseded entry under Project setup). Everything that was turned off as a Mobile workaround was re-tested and is back on.

| Check | Mobile | Compatibility |
|---|---|---|
| Errors in the windowed boot log | 8 compute-pipeline failures on every boot, plus 14 first-frame errors with a `Sky` | 0 errors, 0 warnings |
| Sun shadow, jerky-camera capture (share of the lower frame that goes dark on upward-pitched frames) | about 40% | no change from the no-shadow baseline (at most 9%, which is the unlit wall) |
| Sun shadow, static pitched poses | clean | clean, every frame identical |
| Procedural sky with sky ambient | errors, black or blocky ambient | clean in the same captures |

The captures are the ones used for the Mobile findings: a scripted camera that jumps in yaw and pitch every frame for 40 frames, plus static poses at the firing line, 10 m downrange pitched up between 5 and 45 degrees, and facing the test area and crouch tunnel.

Two things had to be retuned for how Compatibility lights the scene:

- **Light levels.** Compatibility draws a shadow-casting light in a separate additive pass, which brightens lit surfaces. Sun energy went from 1.2 to 0.6 and ambient energy from 0.75 to 0.6 to keep the lit ground at the same mid grey (about 139, 157, 160 in the capture).
- **Sky ambient at 40%.** With all ambient light taken from the sky, the ground came out strongly blue (shadowed ground 52, 85, 110). `ambient_light_sky_contribution = 0.4` mixes the sky with a neutral colour, which keeps a slight cool tint in shadows and a grey ground.

### Frame cap at 60 instead of vsync

Native OpenGL on this macOS does not enforce vsync. With the window focused for the whole run and `window_get_vsync_mode()` reporting enabled, the perf probe measured 119.8 fps. Re-applying the vsync mode after the window was shown changed nothing.

Options tried:

| Option | Result |
|---|---|
| Native OpenGL, vsync on | Not enforced: 120 to 145 fps across seven runs |
| ANGLE driver (`opengl3_angle`) | 90 to 127 fps uncapped with 1% lows of 37 to 62 fps, and a 1.05 s hitch in both vsync runs. Too little headroom. |
| Native OpenGL, `application/run/max_fps=60` | 59.8 to 60.0 fps, median frame 16.6 to 16.7 ms |

So the frame rate is held by `application/run/max_fps=60`. This is a frame limiter, not a display sync: frame count is steady at 60, but frames are not aligned to the display refresh. Windowed apps on macOS go through the compositor, so there is no tearing; an occasional repeated frame is possible. Revisit if play-testing shows judder.

### Performance after the switch

1280x720 window, final configuration (sun shadow with 2 splits, procedural sky), same 10 s sprint-and-sweep probe as Milestone 1.

| Run | Average | 1% low | Worst frame |
|---|---|---|---|
| As played (60 fps cap), focus steady | 60.0 fps | 54.0 fps | 18.8 ms |
| Uncapped (`--disable-vsync --max-fps 0`), 7 runs | 145 to 193 fps | 84 to 111 fps in runs with steady focus | 9.6 to 26.4 ms |

47 to 52 draw calls, about 1,250 primitives.

Caveats on these numbers:

- Whenever the window gained or lost focus during a run, that run had one frame of about 70 ms. It happened in several probe runs because the probe is launched from a background shell and focus moved mid-run; those runs' 1% lows (down to 26 fps capped, 61 fps uncapped) are excluded above. It is an app-switch hitch, not a steady-state one: no run without a focus change had a frame over 26.4 ms. Focus tracking was added to the probe partway through, so for the first three uncapped runs steady focus is inferred from the absence of that hitch.
- The steady as-played run happened to be unfocused throughout. A fully focused capped run was not captured, so confirm it by eye with the overlay (`ms worst`) during play-testing.
- Uncapped averages vary by about 30% between runs on this machine, so treat the range as the result rather than any single figure. Mobile without shadows was about 300 fps; Compatibility with shadows and sky is roughly half that and still well over twice the budget.

## Milestone 2: shooting core

### Projectiles are rows in packed arrays

`ProjectileSystem` is one node holding position, velocity, age and spec arrays for up to 128 projectiles. Firing takes a free slot and allocates nothing. Each tick integrates every live projectile and raycasts from the previous position to the new one, so a 900 m/s bullet (15 m per tick) cannot skip a thin wall. The system runs after weapons in the tick, so a shot moves on the tick it is fired. Integration is exact for constant acceleration; Milestone 3 adds drag by changing the acceleration and adds fields to `ProjectileSpec`.

### Shots leave from the eye, not the muzzle

Bullets start at `PlayerController.get_eye_position()` along `get_aim_basis()`. The viewmodel, its kick and the muzzle flash are cosmetic. A test fires a second of full-auto and checks every round lands on the same point.

### Weapon timing

- The shot interval remainder is carried from shot to shot, so 700 rpm (5.14 ticks) averages exactly. It is not carried across a pause, which had made the first interval of a burst one tick short.
- Bullets spawn on tick boundaries; there is no sub-tick spawn offset.
- Ammo changes only on a shot or a completed reload, so a reload cancelled by switching leaves the count untouched. A reload fills the magazine; there is no reserve ammo on the range.
- Pulling the trigger on an empty magazine starts the empty reload. A reload pressed mid-cycle is queued until the weapon is ready.
- Sprinting blocks firing and aiming, as specified; it does not block reloading. Reloading drops the aim. The sniper stays scoped while the bolt cycles.
- Fire and reload presses are latched from input events, because polling an edge in the physics tick loses a click shorter than one tick.

### Never toggle `visible` under the camera rig

The camera rig has physics interpolation off. In Godot 4.7, after `visible` is toggled on a node in that subtree, the renderer stops receiving its later transform changes: the viewmodel froze on screen while its script kept moving it. `WeaponView` therefore adds and removes models from the tree and hides the muzzle flash by scaling it.

### Effects

- Impact marks are instances in one MultiMesh that reuses the oldest, because the Compatibility renderer has no Decal node. Marks only stick to static bodies.
- Particles are `CPUParticles3D`. `GPUParticles3D` was not evaluated.
- Sounds are synthesised at startup from seeded noise and sine tones, so the project has no audio files.

### Capture quirks (Movie Maker only)

Physics runs somewhat behind the frame count in Movie Maker mode on this machine, so `--hold` times are in physics seconds and captures need extra frames. Quitting a capture while sounds are playing logs a "5 ObjectDB instances leaked" warning from the audio playbacks; normal runs that quit mid-burst do not.

### Tuning starting points

| | Halberd R-5 | Longwatch B-9 |
|---|---|---|
| Muzzle velocity | 850 m/s | 900 m/s |
| Rate | 700 rpm, full-auto | 1.1 s bolt cycle |
| Magazine | 30 | 5 |
| Reload, tactical / empty | 1.9 s / 2.4 s | 2.6 s / 3.3 s |
| ADS time, FOV, sensitivity | 0.25 s, 45°, 0.7 | 0.4 s, 12°, 0.2 |
| Raise / lower | 0.4 s / 0.3 s | 0.6 s / 0.45 s |

### Performance (Milestone 2)

Perf probe walking downrange and firing full-auto with reloads, 1280x720, window focused for the whole run.

| Run | Average | 1% low | Worst frame |
|---|---|---|---|
| Firing, as played (60 cap) | 60.0 fps | 55.0 fps | 18.5 ms |
| Firing, uncapped | 177.8 fps | 99.3 fps | 21.0 ms |
| Sprinting, uncapped (Milestone 1 probe) | 184.3 fps | 110.0 fps | 9.7 ms |

73 draw calls and about 2,050 primitives while firing. 167 tests pass.

## Milestone 3: ballistics and recoil

### Drag model: quadratic, constant Cd, RK4 per tick

Drag deceleration is `k * |v| * v` with `k = 0.5 * air density * Cd * area / mass`. Cd is held constant rather than varying with Mach number. That is a simplification, but over the 0 to 400 m the range covers both bullets stay supersonic, where a real G7-style Cd changes slowly. Each physics tick takes one RK4 step: it is within a millimetre of a 240 Hz run at 300 m, and the drop matches the analytic flat-fire solution to 2 mm at 100, 200 and 300 m (tests in `test_projectile_math.gd` and `test_projectile_system.gd`). The flat-fire solution treats |v| as the horizontal speed, which for these shots is exact to a few parts per million. A spec with Cd 0 keeps the exact vacuum parabola.

The swept raycast still goes in a straight line from the old position to the new one. Over one tick the curved path sags 0.3 mm from that chord.

| Bullet | Mass, diameter, Cd | k (1/m) | Speed at 300 m | Drop at 100 / 200 / 300 m (vacuum) |
|---|---|---|---|---|
| Halberd R-5, 850 m/s | 4.0 g, 5.7 mm, 0.30 | 0.00117 | 598 m/s | 7.3 / 32 / 78 cm (6.8 / 27 / 61) |
| Longwatch B-9, 900 m/s | 10.9 g, 7.82 mm, 0.27 | 0.00073 | 723 m/s | 6.4 / 27 / 63 cm (6.1 / 24 / 55) |

The rifle loses about 30% of its speed by 300 m and the sniper about 20%, in line with real 5.56 mm and 7.62 mm rifle rounds.

### Damage falloff by distance, not by impact speed

Damage is full out to a start distance, then falls linearly to a minimum fraction at an end distance, measured along the flight path. Scaling with impact energy would have tied damage to the drag tuning; separate distance knobs are easier to balance. The rifle does 32, falling to 70% between 50 and 200 m. The sniper does 110, falling to 80% between 150 and 400 m. Hit zones and armor come in Milestone 4, on top of `ProjectileHit.damage`.

### Recoil moves the real aim

Each shot adds its pattern entry plus a random deviation to a recoil offset on the player (`recoil_pitch`, `recoil_yaw`). That offset sits on top of the mouse look angles, and both the bullets and the camera follow it, so recoil is gameplay rather than an effect. The camera blends the offset between ticks so a kick does not step at high frame rates.

- **Recovery.** Once the weapon has rested for `recoil_recovery_delay`, the offset returns to zero at `recoil_recovery_rate`. The rifle's 0.12 s delay is longer than its 0.086 s shot interval, so nothing recovers mid-burst.
- **Compensation is not recovered twice.** Mouse movement against the offset cancels it before it moves the base angle. Without this, a player who pulls the spray down would then have the view recover further down, below the target.
- **Pattern reset.** The pattern restarts at shot 1 after `recoil_reset_time` without a shot. Past its last entry, the last `recoil_loop_length` entries repeat.
- **Aimed scale.** The rifle kicks at 80% while aimed; the sniper kicks the same either way.

The rifle pattern climbs about 0.45 to 0.6 degrees per shot for the first 10 rounds, drifts right, swings left, then wanders at 0.3 degrees per shot. That is about 11.8 degrees over a full magazine before the aimed scale. The sniper kicks 4 degrees up and 0.3 degrees right, ±0.5 degrees, and recovers at 12 degrees per second, well inside its 1.1 s bolt cycle.

### Spread and first-shot accuracy

Shots leave inside a cone: hip spread blended to aimed spread by ADS progress, plus bloom. Each shot adds bloom, and it shrinks only after the same rest delay as recoil recovery, so it builds through a burst and settles between taps. Both weapons have zero aimed spread, so the first aimed shot from a settled weapon goes exactly along the sights. Hip spread is 2 degrees for the rifle and 4 for the sniper. The rifle blooms 0.15 degrees per shot up to 1.2. Points in the cone are spread evenly over its cross-section.

Recoil and spread draw from one seeded random generator on `WeaponController` (`random_seed`, or `reseed()`). Tests seed it. The Milestone 2 test that "every round lands on the same point" no longer holds now that recoil moves the aim. It is replaced by a test that a seeded burst lands identically with the `WeaponView` node removed entirely, which still proves the viewmodel never feeds into hits.

### Bullet path view

`debug/bullet_paths.gd` draws the points the simulation actually visited, one per tick, with no smoothing, so it shows exactly what the hit test swept. It is drawn without a depth test, so paths stay visible behind walls and over the viewmodel.

The first version rebuilt an ImmediateMesh vertex by vertex every tick, which cost about 6 ms a frame with 40 long paths (84 fps uncapped against 162). Each path now builds its own line vertices as it records, and a redraw concatenates them natively into one ArrayMesh surface, at about 1 ms.

### Movie Maker frames repeating (correction to the Milestone 2 note)

The Milestone 2 note blamed physics for running behind in Movie Maker. The actual cause is macOS throttling a Godot window that is not in front: Movie Maker then reports far fewer frames rendered than written (25 of 200) and repeats the last one. Running with `--always-on-top` fixed it; all 200 frames were distinct.

### Performance (Milestone 3)

Perf probe walking downrange and firing full-auto with reloads, 1280x720, window focused for the whole run.

| Run | Average | 1% low | Worst frame |
|---|---|---|---|
| Firing, as played (60 cap) | 60.0 fps | 53.7 fps | 18.8 ms |
| Firing with bullet paths, as played (60 cap) | 60.0 fps | 53.6 fps | 18.7 ms |
| Firing, uncapped | 163.7 fps | 102.0 fps | 11.4 ms |
| Firing with bullet paths, uncapped | 132.1 fps | 53.0 fps | 23.9 ms |

Drag, recoil and spread cost about 0.5 ms a frame against Milestone 2's 177.8 fps uncapped (5.6 to 6.1 ms). No capped run had a frame over 25 ms. 206 tests pass.
