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

**Superseded by sight zeroing below:** the fixed gameplay bore origin is now one configured sight height below the eye. Animated viewmodel geometry still has no effect on hits.

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

## Milestone 4: targets

### One swept hit path, solid humanoid zones

`TargetHits` listens to the existing `ProjectileSystem.projectile_hit` and dispatches only to the collider named in that report. There are no target raycasts, overlap checks or separate damage sweeps. Each humanoid has six `AnimatableBody3D` boxes (head, torso, two arms, two legs), on the same layer the projectile sweep already hits. The carrier moves them at the physics tick with `sync_to_physics` off, so collider and visible positions agree. Using animatable rather than static bodies also keeps the existing impact effects from leaving floating marks on moving or folding targets.

Zone multipliers live in `targets/data/dummy_default.tres`: head 1.5, sniper head 2.0, torso 1.0, limbs 0.8. `ProjectileSpec.weapon_class` selects the sniper rule explicitly; neither weapon names nor damage thresholds select it. Ballistics applies distance falloff before the target applies its zone multiplier, then armor and health. The zone enum belongs to the tuning Resource: making that Resource depend on the hit-zone node created a circular preload through the dummy's default Resource, which retained GUT resources at shutdown. Keeping data dependencies independent of nodes removes that cycle.

### Armor is a contiguous pool of plates

`TargetHealth` is node-free. Remaining armor is a float pool initialized to `plate_count * plate_health`, with the count clamped to 0–3. Damage subtracts `min(armor, damage)` from armor and sends the remainder to health. An exact break on the final plate leaves health untouched; there is no rounding or lost overflow between plates. `remaining_plates()` rounds upward so a partially damaged plate still counts. Negative damage and hits while dead do nothing.

A kill disables all hit-zone layers immediately, folds the silhouette backward over 0.15 s, and restores its health, initial armor and upright pose exactly 3 s after the kill (not 3 s after folding finishes). The clock and pose update at the physics tick. Movers continue on their rails during downtime; a reset happens wherever the carrier is, without teleporting the rail.

### Layout and rail motion

Nine dummies are active: stationary at 25/50/100/200/300 m with 0/1/2/3/0 plates, plus four unarmored movers. The stationary targets are staggered across the five lanes rather than stacked directly behind each other. At both 50 and 100 m, the left rail walks at 1.5 m/s and the right rail sprints at 6 m/s. Each rail is 4 m long. These are exported layout values on `RangeBuilder`; the armor assignment and placement are in `_build_targets()`.

A rail folds an increasing travelled-distance phase into an outgoing and returning leg. It preserves endpoint overshoot, reverses immediately on exact endpoints, and handles several reversals in one step. Tests check speed, both endpoints, large versus small steps, and a real projectile striking a rail-carried zone at its moved position.

### Steel uses physics, not an animation

Three 8 kg steel boxes hang at 100/200/300 m from world-anchored `HingeJoint3D` nodes. The hinge's axis is world X at the top of each plate, limited to ±65 degrees. On an existing projectile report, the plate receives an off-centre impulse of `bullet mass * impact velocity * impulse_scale`; Jolt supplies the swing, gravity and settling. Tuning exports are in `targets/steel_plate.gd`. A real-projectile test checks the ring event, hinge constraint and physical rotation.

The placeholder ring is a cached, one-second decaying pair of inharmonic sine tones in `SfxFactory.steel_ring()`, played spatially with a 60 m unit distance so it remains audible downrange. This intentionally generous attenuation is for range feedback; judge distant volume during play-testing. No audio or other binary assets were added.

### Verification and performance (Milestone 4)

Headless GUT: 221 tests cover the complete project, including armor-first carry-over, an exact final-plate break, both weapons' zone multipliers, pop-down and exact reset timing, real sniper headshot / rifle body-shot outcomes at 100 m, all four limb colliders, rail movement and moved hit zones, and a real projectile ringing and swinging steel. Windowed and headless boots have zero errors. Movie Maker frames were inspected from the range and close to the 25 m dummy; human play-testing of readability, durability, motion feel and distant ring volume remains pending.

1280×720, Compatibility, all nine dummies and three steel targets active, walking and firing full-auto with reloads (`godot --always-on-top -- --perf-probe --perf-fire`). Window focused for 100% of measured frames:

| Average | 1% low | Worst frame | Frames over 25 ms | Draw calls / primitives |
|---|---|---|---|---|
| 60.0 fps | 53.3 fps | 21.18 ms | 0 of 601 | 162 / 2,750 |

The extra meshes and physics bodies retain the 60 fps target on the Intel Iris Plus 655. Values above describe a capped run, not an uncapped headroom measurement.


## Sight zeroing (after Milestone 4)

### Geometry-derived bore offset and equip-time calibration

Both weapon Resources now specify `zero_distance_m = 100.0`. `sight_height_m` is measured from the reference geometry, rather than from the animated pose or the camera-relative ADS translation:

| Weapon | Sight reference | Bore reference | Sight height |
|---|---|---|---|
| Halberd R-5 | FrontSightPost tip: centre y 0.045 + half-height 0.015 = 0.060 m | Barrel / Muzzle centre y 0.010 m | 0.050 m |
| Longwatch B-9 | Scope optical axis y 0.085 m | Barrel / Muzzle centre y 0.012 m | 0.073 m |

The projectile starts at `gameplay eye - gameplay aim up * sight_height_m`, without forward or sideways cosmetic muzzle offsets. The reference geometry supplies the tuning value only; removing the viewmodel, changing its kick or moving its rendered pose cannot alter the shot. This replaces the earlier eye-origin convention and makes the below-sight start and both sight-line crossings possible.

`SightZeroing.solve()` bisects the upward low-arc bracket from 0 to 45 degrees, using full `sin` and `cos` to form each trial launch velocity. Every trial uses `ProjectileMath.step_drag()` at the actual physics tick, including projectile gravity scale and drag at the active system's air density. Its final sample intersects the sight-distance plane along the same straight chord used by the projectile sweep, rather than integrating a shorter final tick. There is no flat-fire formula, small-angle approximation or separate hit path in calibration.

`WeaponController` solves once when the weapon is equipped, including the initial equip. Switching back solves again with the current atmosphere and physics settings. Each shot rotates the gameplay aim upward by the cached angle and applies spread around that bore direction. Existing recoil remains in the gameplay aim, and this shot's recoil is still applied after its bullet leaves. The calibration is for a horizontal line of sight; it is a fixed mechanical bore/sight angle when aiming uphill or downhill. A zero distance of 0 disables the angular correction; an unreachable low-arc zero warns and falls back to an uncalibrated bore.

### Angles and trajectory table

Godot's own integrator and swept-plane intersection, 60 Hz, gravity 9.81 m/s², air density 1.225 kg/m³, original weapon bullet specs, level settled aim:

| Weapon | Elevation above sight line (radians) | Elevation (degrees) |
|---|---|---|
| Halberd R-5 | 0.001238613 | 0.070967308° |
| Longwatch B-9 | 0.001367129 | 0.078330732° |

Signed impact height relative to point of aim, in centimetres. Positive is above aim; negative is below. These are zeroed trajectories, not the old unzeroed horizontal-launch drop figures.

| Distance | Halberd R-5 | Longwatch B-9 |
|---|---|---|
| 25 m | -2.359 | -4.295 |
| 50 m | -0.604 | -2.048 |
| 75 m | +0.203 | -0.597 |
| 100 m | 0.000 | 0.000 |
| 125 m | -1.276 | -0.302 |
| 150 m | -3.689 | -1.501 |
| 200 m | -12.187 | -6.746 |
| 300 m | -46.218 | -29.710 |

**The requested above-aim impact at 50 m conflicts with the measured sight heights and a 100 m zero.** The rifle is still below its first crossing at 50 m; it is above aim at 75 m and returns through aim at 100 m. The sniper's 73 mm sight height puts its first crossing at 100 m, with its second crossing a little farther downrange. Keeping the geometry and 100 m zeros therefore requires the below-aim values shown at 50 m. Getting both weapons above aim there would require changing sight geometry or zero distance. The tests preserve these physical inputs and the computed offsets rather than assuming a sign; a separate lower-sight test demonstrates the expected positive 50 m rise and two crossings.

### Verification

Pure solver tests compare against independent 240 Hz integration with and without drag, exercise a launch angle above 20 degrees to guard against small-angle shortcuts, and cover disabled and unreachable zeros. Geometry tests measure the front sight tip and scope axis against the viewmodel muzzle references. Live controller tests equip both weapons and fire into real Jolt walls at 50, 100 and 300 m: zero-distance impacts must be within 1 cm of aim, and other distances must agree with the integrator within 1 mm. A switch test changes air density and verifies recalibration on equip. Existing recoil, spread and viewmodel-independence tests remain in the full suite.

Full headless suite: **228/228 tests pass**, with clean shutdown. Headless and windowed startup checks both completed without errors.

## Milestone 5: feedback and HUD

### Target signals are the only feedback authority

`RangeFeedback` listens to each dummy's existing `damaged` / `restored` signals and each steel target's existing `rang` signal. It never raycasts, computes damage or applies impulses. A dummy now exposes `last_plate_breaks` before emitting `damaged`; steel exposes `last_hit` before `rang`. The existing signal signatures remain unchanged. Targets do not depend on UI scripts.

Marker priority is kill > armor break > hit. Breaking any plate, including an exact 50-point break, is blue; removing only part of a plate is white. A killing hit that also breaks armor is red. A stronger visible marker is retained for its remaining lifetime if a weaker event arrives immediately afterward. Feedback remains visible during ADS and through the scope overlay.

Damage labels show the signal's zone-adjusted incoming damage, including overkill, rounded to the nearest whole point. Body and limb numbers are white; head numbers are amber. Steel has a white hitmarker and confirmation sound but no damage number because it has no health. Numbers are pooled screen-space labels anchored to the world hit point, offset alternately left/right, rising in pixels and fading. They hide behind the camera and expire after 0.8 s. New events reuse the oldest slot once the 24-label pool wraps. The marker is one custom-drawn control. No feedback event allocates nodes.

### Statistics definitions and reset boundaries

`RangeStats` is node-free. Shots count actual `projectile_fired` launches, excluding rejected pool launches and dry fire. Hits count once when a launched projectile damages a dummy or rings steel. Ground, walls, props and bullets through a down dummy are misses. Accuracy is `100 * hits / shots`; headshot percentage is `100 * dummy head hits / all target hits`. Both read 0% for an empty denominator; armor-only head hits count as headshots. Steel contributes to hits but not headshots or TTK.

A physics-time clock supplies hit timestamps. Each dummy life has an independent first-damage timestamp, including armor damage; a killing hit completes that target's TTK. A one-hit kill is 0.000 s. The panel holds the last completed TTK until the next kill or stats reset. Target restore ends any open timer, and interleaved targets cannot overwrite each other's start time.

T (`range_stats_reset`) clears counters, active timers, completed TTK, marker and number labels. It does not change ammo, weapons or target state. The adapter clears eligibility for already-flying projectiles, so their subsequent real feedback is still shown but cannot produce hits in a new zero-shot session. Eligible slots are also removed on accepted hits and expiration and overwritten on reuse, keeping bookkeeping bounded by the projectile pool.

### Crosshair, readouts and audio

The crosshair's extra radius is `tan(current spread half-angle) * viewport height / (2 * tan(vertical FOV / 2))`, added to its base gap. It reads `RecoilLogic.spread_degrees()` including current bloom and uses the active camera's actual FOV. It hides at ADS blend 0.5 or when scoped; it never feeds aim or projectile logic. Ammo/reload/switch behavior is retained. Gameplay FPS and stats are in the HUD's layer 10, independent of the F3 diagnostics on layer 100.

Audio confirmation is non-spatial player feedback, separate from the existing spatial impact and steel sounds. Three cached chirps are generated by `SfxFactory.confirmation()` before any hit and played by three prebuilt players, each with bounded polyphony. A hit is a short downward chirp, armor break a longer high-to-low chirp, and kill a rising chirp. The original tone synthesis is described in `CREDITS.md`; no samples or binary assets were added.

### Complete Milestone 5 tuning reference

The defaults below live in scripts; change exported properties on the corresponding HUD child in `ui/hud.tscn` to override them. Times are seconds, lengths are pixels unless stated otherwise, and colors are RGBA.

| File / node | Values |
|---|---|
| `ui/hud.gd`, HUD root | `crosshair_hide_aim_blend = 0.5`; `fps_update_seconds = 0.25`; `stats_update_seconds = 0.2` |
| `ui/crosshair.gd`, Crosshair | `gap = 6`; `line_length = 8`; `thickness = 2`; `dot_size = 2`; `color = (1,1,1,0.9)`; `outline_color = (0,0,0,0.6)`; outline expansion is 2 px in drawing code |
| `ui/feedback_view.gd`, FeedbackView: marker | `marker_hold_seconds = 0.10`; `marker_fade_seconds = 0.18`; `marker_gap = 8`; `marker_length = 7`; `marker_thickness = 2`; `kill_length = 12`; `hit_color = (1,1,1,1)`; `armor_color = (0.25,0.65,1,1)`; `kill_color = (1,0.22,0.20,1)`; `marker_outline_color = (0,0,0,0.7)`; drawing code adds a 2 px outline |
| `ui/feedback_view.gd`, FeedbackView: numbers | `number_capacity = 24`; `number_lifetime = 0.8`; `number_rise_pixels_per_second = 36`; `number_horizontal_offset = 16` (alternating ±); `number_font_size = 22`; `number_outline_size = 4` (black); `number_color = (1,1,1,1)`; `headshot_color = (1,0.78,0.25,1)`; `roundi(amount)` sets displayed precision |
| `ui/feedback_audio.gd`, FeedbackAudio: hit | `hit_volume_db = -15`; `hit_start_hz = 1400`; `hit_end_hz = 1000`; `hit_seconds = 0.045` |
| `ui/feedback_audio.gd`, FeedbackAudio: armor break | `armor_volume_db = -11`; `armor_start_hz = 2300`; `armor_end_hz = 400`; `armor_seconds = 0.16` |
| `ui/feedback_audio.gd`, FeedbackAudio: kill | `kill_volume_db = -9`; `kill_start_hz = 1000`; `kill_end_hz = 1800`; `kill_seconds = 0.22` |
| `ui/feedback_audio.gd`, FeedbackAudio: pool | `polyphony = 4` per confirmation type |
| `weapons/effects/sfx_factory.gd`, `confirmation()` | Mix rate 22,050 Hz, 16-bit mono PCM; 0.003 s attack; `exp(-progress * 4)` decay; fundamental weight 0.7; overtone weight 0.3 at 1.5× frequency; frequency sweeps linearly from start to end |
| `ui/hud.tscn`, FPS | Right margin 28, top 18, width 122, height 24; font 16, outline 4 |
| `ui/hud.tscn`, Stats / Readout | Fixed panel: right margin 28, top 52, width 260, height 183; background `(0.035,0.045,0.055,0.78)`, corner radius 4; text inset 14 horizontally / 10 vertically, font 16, line spacing 5; percentages use 1 decimal and TTK 3 decimals in `Hud._refresh_stats()` |
| `ui/hud.tscn`, inherited Ammo / WeaponName | Ammo: right margin 28, bottom 22, width 312, height 46, font 32, black outline 6, white text. Weapon name: right margin 28, bottom 66, width 312, height 26, font 16, black outline 5, text `(0.86,0.88,0.9,1)` |
| `weapons/data/halberd_rifle.tres`, crosshair source | Hip / aimed spread 2° / 0°; bloom +0.15° per shot, cap 1.2°, recovery 4°/s after 0.12 s rest |
| `weapons/data/longwatch_sniper.tres`, crosshair source | Hip / aimed spread 4° / 0°; bloom +0° per shot, cap 0°, recovery 4°/s after 0.15 s rest |
| `project.godot`, input | `range_stats_reset`: T, physical keycode 84 |

### Readout update cost and verification

The first full-HUD firing runs averaged 59.7–59.9 fps, with 5–7 frames over 25 ms and 1% lows of 28–34 fps. An isolated HUD-off comparison held 60.0 fps, 55.9 fps 1% low and 18.15 ms worst, with no measured frame over 25 ms. Keeping the HUD visible but disabling only stats/FPS text updates likewise removed the measured hitches. This localized the cost to changing readouts rather than target feedback or the 3D scene.

Stats still record every event immediately. Display text is now dirty-flagged and refreshed at most every 0.2 s (5 Hz), with reset displayed immediately. Replacing the stats PanelContainer with a fixed Panel also avoids minimum-size/container relayout on each text change. No target feedback events are dropped; marker and number presentation still responds to each event.

Final standard firing probe, `godot --always-on-top -- --perf-probe --perf-fire`, 1280×720, Compatibility, all targets and full HUD active, window focused for 100% of measured frames:

| Average | 1% low | Worst frame | Frames over 25 ms | Draw calls / primitives |
|---|---|---|---|---|
| 60.0 fps | 55.2 fps | 18.32 ms | 0 of 601 | 166 / 3,014 |

Windowed startup completed with zero errors. Movie Maker captures were inspected for white hitmarkers, blue armor breaks, red kill Xs, amber headshot numbers, stats and TTK, plus the final fixed panel layout. Capture-only audio shutdown warnings match the earlier recorded Movie Maker limitation; normal windowed startup and the performance probe are clean. Human judgment of feedback timing, clutter, audio balance and distant readability remains pending; the step-by-step procedure is in README.

Final full headless GUT suite: **245/245 tests pass**, 4,558 assertions, with no errors or shutdown leaks. Coverage includes stats maths and resets, per-target TTK, authoritative damage-marker selection, in-flight reset boundaries, HUD reset input, spread projection / bloom recovery, feedback pooling / lifetime, confirmation sound data / selection, and bounded stats-display latency.

## Milestone 6: final MVP polish

### Capped pushable props and the existing bullet path

Eight props (four crates, four barrels) are built once near the firing line and test area. Their placement avoids the lane centres and movement obstacles. `PhysicsProp.receive_hit()` receives the same `ProjectileHit` dispatched by `TargetHits` for steel and dummies. The off-centre impulse is exactly bullet mass in kg times impact velocity; there is no additional raycast or overlap path. A 4 g rifle round at 850 m/s therefore applies 3.4 N·s, before ordinary damping and contacts.

After `move_and_slide()`, the player forwards rigid-prop contacts and its pre-slide velocity. Pushing is horizontal, capped by both `push_force * physics_delta` and the relative closing momentum. It cannot add vertical launch velocity or keep accelerating a prop already moving away faster than the player. Prop count is capped at eight, and a body below y = -10 m or beyond its home radius returns to its initial transform with velocities cleared. GUT checks both masses' bullet impulse, force-limited player pushing and actual swept-projectile dispatch.

### Pause, settings and mouse-free navigation

The range root explicitly uses `PROCESS_MODE_PAUSABLE`. Only `PauseMenu` uses `PROCESS_MODE_ALWAYS`; opening it pauses the SceneTree, leaving physics, projectile integration, player / weapon ticks, prop simulation, rail motion, ragdoll / target reset clocks, stats timestamps and in-game audio stopped. The renderer and menu still run. Tests check that gameplay tick counts, physical position, a live projectile and the range-stat clock remain unchanged during real elapsed menu time, then advance after resume. This freezes gameplay ticks, not the engine's global frame counter.

All added commands use InputMap actions. `pause` is Esc / controller Start, and UI accept / cancel / directions have explicit keyboard, A/B, D-pad and left-stick bindings. Resume receives focus on every open; vertical and Tab focus neighbours form a cycle, and the scroll container follows focus. Sliders adjust with Left/Right, checkbox / Resume activate with Enter, Space or A, and B cancels back to gameplay. The player's old Esc-only cursor release handler is replaced by this menu. Mouse recapture uses the existing fire action rather than a hard-coded mouse button. Menu transitions clear buffered fire/reload and fire / aim / reload / jump action presses so activating Resume does not act in-game.

`ViewSettings` remains the single persistence owner. Its existing `view` section in `user://settings.cfg` gains ADS sensitivity multiplier, master / effects volume and gameplay FPS visibility; legacy invert-Y and view values still load. Settings apply immediately and save on resume. `ConfigFile` preserves any other sections. Tests round-trip every preference through a separate config path and never overwrite the player's settings. ADS scaling is the per-weapon value multiplied by the global preference, blended from unscaled hip sensitivity.

A text AudioBusLayout defines Effects -> Master. All weapon, handling, impact, steel and HUD players use Effects, and ViewSettings controls both buses with linear gain; zero mutes. The FPS preference affects only the gameplay HUD, never F3 diagnostics. No native extension, OS subprocess, service or runtime path outside `user://` was introduced. Browser export and physical-controller validation remain future acceptance work, not claims made by this native MVP.

### Pooled ragdolls replace pop-downs

Ragdolls are enabled after passing the all-awake performance check below. Each dummy creates six frozen rigid bodies and five disconnected pin joints once at startup, reusing the existing hit-zone shapes and meshes. A killing shot disables live hit-zone collision, hides the standing silhouette, activates the parts at the exact hit-zone transforms, connects the pins and applies bullet momentum to the struck part. Moving targets contribute their carrier velocity. The ragdoll subtree is top-level/world-space, so the rail continues without dragging the corpse.

Ragdoll bodies use layer 4 and mask 1: they contact the world and props, while excluding player, projectile and corpse-to-corpse contacts. Adjacent joints also use the engine's connected-body collision exclusion. Only 54 ragdoll bodies / 45 pins can be active in the shipped nine-target layout. Connecting joints only after unfreezing avoids trying to constrain two static bodies; disconnecting before freezing avoids retaining unnecessary idle constraints.

At exactly 3 seconds of gameplay time, the parts freeze and hide, their collisions and velocities clear, and the original standing hit zones / armor / health return. No new nodes are allocated on kill or reset. Tests snapshot every original zone transform and layer and verify exact restoration, no extra nodes, killing momentum and separation from a moving rail. `ragdoll_enabled = false` retains the tested pop-down fallback, but is not the shipped default. The rig is deliberately greybox with pin joints rather than anatomical angular limits.

### Complete Milestone 6 tuning reference

This table covers newly introduced values and the existing view preferences exposed by the menu; prior milestone tables still describe unchanged movement, weapons and feedback.

| File | Values / policy |
|---|---|
| `range/range_builder.gd` | `prop_count = 8`, hard cap eight locations. Alternating crate / barrel locations (x,z), metres: (-18,1), (18,1), (-18,4), (18,4), (-6,12), (6,12), (-6,17), (6,17). Spawn y is half the corresponding height. |
| `props/physics_prop.gd` | Crate mass 8 kg, side 0.65 m; barrel mass 12 kg, radius 0.30 m, height 0.9 m, 12 radial mesh segments. `push_force = 60` N; `return_radius = 30` m; recycle below y = -10 m. Linear / angular damping 0.2 / 0.4 (combined with world damping). Collision layer / mask 1 / 3. |
| Same file, appearance | Crate color `(0.48,0.36,0.22,1)`, barrel `(0.28,0.36,0.32,1)`, roughness 0.85. |
| `player/view_settings.gd` | FOV default 65°, range 50–100°, hotkey step 5°. Sensitivity default 0.10 °/count, range 0.01–1.0, hotkey ratio 1.1. Invert-Y false. Head bob and FOV-kick scales both 1.0, range 0–2. ADS multiplier 1.0, range 0.1–2.0. Master / effects volume 1.0 / 1.0, range 0–1. Show FPS true. Storage `user://settings.cfg`, section `view`; linear gain floor 0.0001 for dB conversion, zero explicitly mutes. |
| `ui/pause_menu.gd`, slider increments | Sensitivity 0.01; ADS multiplier 0.05; FOV 1°; head bob / FOV kick 0.05; master / effects volume 0.05. Readouts use two decimals. Bounds are the ViewSettings ranges above. |
| Same file, layout / focus | Canvas layer 200; black shade alpha 0.65; centred panel 660×580 px; margins 20; row separation 10; title font 24; help font 14; setting-label minimum width 250; slider minimum 220×30; value width 60. Focus starts on Resume and wraps through nine controls. Scroll follows focus. |
| `project.godot`, added menu input | Pause: Esc (physical key 4194305), Start (button 6). Accept: Enter / Space, A (0). Cancel: Esc, B (1). Directions: arrows, D-pad 11/12/13/14 and left-stick axes 1/0 ±1; UI dead zone 0.5. Default Tab / Shift+Tab actions remain available. |
| `default_bus_layout.tres` | Master and Effects start at 0 dB; Effects sends to Master. Individual player volumes remain as authored in previous milestones. |
| `targets/target_dummy.gd` | `ragdoll_enabled = true`; carrier velocity from successive physics-tick positions. Live hit-zone transforms and materials remain the source of body geometry. |
| `targets/dummy_ragdoll.gd` | Masses in existing zone order (head, torso, left arm, left leg, right arm, right leg): 4 / 24 / 3 / 8 / 3 / 8 kg (50 kg total). `impulse_scale = 1.0`; linear / angular damping 0.25 / 1.0, combined with world damping. Active collision layer / mask 4 / 1; idle 0 / 0. |
| Same file, pins | Torso connects to part indices 0,2,3,4,5. Local anchors, metres: (0,1.49,0), (-0.27,1.43,0), (-0.14,0.88,0), (0.27,1.43,0), (0.14,0.88,0). Pins use engine defaults and connected-body collision exclusion. |
| `targets/data/dummy_default.tres` | Reset remains 3.0 s of gameplay time; fallback fold duration remains 0.15 s. |
| `debug/range_stress.gd` | Opt-in `--perf-stress`; `--perf-popdown` disables ragdolls only in that run. Re-kill damage 400, sniper projectile momentum at 900 m/s, torso point offset (0,0.1,0.1) m. Keeps rag parts awake with 0.005 N·m·s yaw impulses each tick; props get 8 m/s² rotating horizontal forcing at a 0.2 m lever, speed capped at 4 m/s; steel gets 0.03 N·m·s X torque impulses each tick. No fixture forcing runs in ordinary play. |
| `debug/perf_probe.gd` | Existing 2 s warmup / 10 s measurement, 50° yaw sweep / 4 s period and -4° pitch. Reports min/max awake ragdoll parts in every measured frame and count of stress props. |

### Performance pass, before / after and ragdoll decision

All measurements below are on the documented target Mac at 1280×720, Compatibility, full HUD and firing/reloads, with the window focused for 100% of measured frames. The stress fixture continually wakes all props and steel and immediately re-kills every dummy on restore, including activation/reset cost throughout the measurement. Ragdoll runs reported **54 min / 54 max awake parts**; this is not a test of already-sleeping corpses. The fixture applies no scoring shots for its synthetic kills.

| Configuration | Average | 1% low | Worst | Frames >25 ms |
|---|---|---|---|---|
| Before Milestone 6, Milestone 5 ordinary firing | 60.0 fps | 55.2 fps | 18.32 ms | 0 / 601 |
| Milestone 6 stress, pop-down baseline, eight moving props / steel | 60.0 fps | 37.0 fps | 27.39 ms | 23 / 601 |
| Initial all-ragdoll stress, capped | 60.0 fps | 43.9 fps | 28.58 ms | 1 / 602 |
| All-ragdoll stress, uncapped headroom | 115.4 fps | 70.6 fps | 15.09 ms | 0 / 1,156 |
| Final isolated all-ragdoll stress, capped | 60.0 fps | 49.0 fps | 21.92 ms | 0 / 601 |

The uncapped run had **zero frames over 16.67 ms**, keeping worst-case simulation/render work within the 60 fps budget. Ragdolls are retained. The final capped run had 166 draw calls / 3,012 primitives, eight continuously awake props, all 54 rag parts awake, three driven steel hinges and 83 fired rounds. Bounded prop count, pooled bodies, disconnected idle constraints, shared geometry and corpse collision filtering keep physics and allocation costs controlled; the earlier HUD refresh bound remains in force. No gameplay feedback or ragdoll feature was silently removed.

Capped runs are paced by the limiter rather than enforced OpenGL vsync. The earlier capped spikes also appeared in the pop-down baseline, whereas the uncapped all-ragdoll run stayed below 16.67 ms on every frame. Treat those as measured pacing variability rather than claiming that adding ragdolls made rendering faster. The final isolated run confirms the requested capped behavior; the table retains the earlier results instead of reporting only the best run.

### Final verification and future phases

**254/254 headless GUT tests pass**, 4,632 assertions, clean shutdown. Windowed startup and the final stress probe have zero errors. Movie Maker frames were inspected for the focused pause menu, props at the movement area and articulated ragdolls. The pause-menu capture retains the existing Movie Maker active-audio shutdown warning; ordinary startup and probes are clean. Final manual judgment is pending; README contains the numbered MVP checklist.

Web work still needs an actual browser export, physics/template validation, pointer-lock / audio activation gestures, persistence and browser performance tests. Menu controls have InputMap bindings and synthetic keyboard/controller event tests, but physical-device checks and full controller gameplay (right-stick look, mappings, dead zones, rebinding, prompts) remain post-MVP. No web-incompatible runtime service, native library or OS operation was added. The MVP uses simplified greybox ragdolls and capped recycling props rather than an unrestricted physics sandbox.

## Milestone 7 — weapon composition and attachments

### Preserve the Milestone 6 definitions

The existing guns remain independent `WeaponData` Resources, with no per-gun subclasses. Before refactoring, every original exported weapon stat and nested projectile stat was frozen in `tests/fixtures/milestone_6_weapon_stats.json`. `test_weapon_build.gd` compares both zero-attachment computed builds against that fixture, including packed recoil arrays, poses, sight geometry, sound settings and scene paths. New metadata does not replace or regenerate the fixture. All original tests remain in the suite, covering fire timing, recoil, reloads, zeroing, hits, damage, feedback and rendering state.

`WeaponData` composes three Resources:

- `FireModeData`: full-auto uses a held trigger; semi-auto / bolt / pump use a fresh press. Interval remains `max(60 / rpm, cycle_time)`. `weapons/framework/auto.tres` and `bolt.tres` select the existing rifle / sniper behavior.
- `DeliveryData`: `weapons/framework/ballistic.tres` delegates to the original `ProjectileSystem.fire`. Pellet, explosive and melee tags are declared, but their runtime implementations deliberately wait for Milestones 8–9; unsupported launches fail explicitly. There is no additional hit-detection path.
- `ReloadData`: `weapons/framework/magazine.tres` retains the existing tactical / empty timing and full-magazine refill. Single-round refill adds one, bounded by capacity; none disallows reloading. Interruptible shell reload is explicitly unsupported until Milestone 8.

`WeaponLoadout` names primary and secondary slots and validates roles / classes. Both existing guns are primaries, while the user requires both to stay playable now. Therefore only `weapons/data/range_loadout.tres` enables `comparison_mode = true`; the Resource default is false and ordinary loadouts reject primary / primary pairs. This preserves 1 / 2 and wheel behavior without misclassifying the sniper as a secondary. Remove the range exception when a real default secondary ships in Milestone 9.

### Deterministic cached builds and safe application

`WeaponBuild` holds immutable authored inputs and caches a separate computed `WeaponData`, independent projectile spec and copied recoil pattern. Base Resource identity keys viewmodels and sounds; snapshot identity never creates another gun model or another synthesized sound. One slot accepts one `AttachmentData`, which declares class compatibility, typed `StatModifier` entries, a part scene, mount path and optional optic settings. Class rules independently reject pistol barrel / stock and all rocket / knife / shield attachments, even if an attachment's compatibility array mistakenly includes them.

Build order is fixed: copy base stats; select optic overrides; apply every **ADD**, then every **MULTIPLY**. Within either pass use muzzle → barrel → optic → stock → magazine, then the modifier array's authored order. Keep intermediate values as floats; clamp once after stacking, then round magazine size once. Enforce falloff end ≥ start. For example `(850 + 50) × 1.1 = 990 m/s` regardless of installation order; `(30 + 0.4) × 1.5` rounds once to 46 rounds. Recoil scale multiplies both pattern entries and random deviation; it does not change the camera's cosmetic kick.

Only allowlisted scalar paths can be modified. Unknown fields, non-finite values and negative multipliers are rejected. `set_attachment` invalidates only a real selection change; `get_stats` returns the existing snapshot when unchanged. Authored Resources are treated as immutable: change selections through the build API, not by editing a fitted Resource in place at runtime. A computation counter makes this boundary testable.

The controller queues requests per weapon until ready / firing with the previous cooldown finished. Reloading, lowering, raising and bolt-cycle timing remain intact. Applying a batch computes once, preserves recoil state, clamps current bloom and loaded rounds only if necessary, and never grants rounds when capacity grows. It updates logic, view and audio through the existing weapon signal, and numerically recalibrates the zero using current air density. Already-flying rounds retain their original spec. Clearing all five slots is one batch; clearing an empty build is a no-op.

`DamageSource.Kind` adds BALLISTIC / PELLET / SPLASH / MELEE metadata. `ProjectileSpec.source` defaults to BALLISTIC; `ProjectileSystem` copies it to `ProjectileHit.source` on the existing swept-ray hit. Existing target damage and scoring semantics are unchanged. A real projectile-to-target integration test verifies metadata survives this path.

### Mounted parts and optics

The seventeen catalog Resources live in `weapons/attachments/data/`; [README's attachment table](../README.md#attachment-tuning-and-play-test) lists **every modifier, FOV, sight height and individual Resource filename**. There are three choices per physical slot and five optics, exceeding the suggested optic count to cover all five requested types. Every entry has both a benefit and a cost. Catalog order determines debug cycling, including None after the last compatible choice. Both existing weapons accept all five slots; optics / muzzle / magazines also declare future pistol compatibility.

Each viewmodel has `Mounts/{Muzzle,Barrel,Optic,Stock,Magazine}`. An attachment's local `Mount` marker is aligned with the corresponding weapon marker using an inverse transform. Cosmetic parts never determine projectile origins. Fitted optics detach the native sight nodes and None reattaches those exact nodes. This also preserves the MVP workaround for inherited visibility / physics-interpolation faults. Muzzle parts have an `Exit` marker for the existing flash; flash nodes are detached before an old part is freed, so repeated swaps retain effects without leaks. Node creation happens on selection / equip events, never per shot.

Optic FOV is authored as `degrees(2 × atan(tan(65° / 2) / magnification))`, with no small-angle approximation. The reference stays 65° even when a player changes hip FOV. Explicitly fitting an 8× scope therefore gives 9.106142756°, while **None retains the original sniper's 12°**; None also retains rifle 45° and both original sight heights / ADS poses. Fitted iron / red-dot FOV is 65°. Iron has physical sights, red dot uses a transparent red overlay, 2× a full crosshair, 4× ticks and 8× the original scope reticle. Only scopes hide the model. Head bob, recoil cosmetics and mount transforms remain separate from the calibrated bore direction.

Optic sight height is authored above the bore; the camera-relative ADS Y offset becomes `-sight_height_m - bore_height_m`. Bore heights are 0.010 m rifle / 0.012 m sniper, matching the unchanged model geometry. These values are explicit in the respective weapon Resources. Fixed authored geometry, rather than reading animated meshes, keeps zeroing deterministic.

### Complete new limits and presentation tuning

All clamp bounds below are in `weapons/attachments/data/stat_limits.tres` (`StatLimits`). `Vector2` stores the bounds as engine floats; tests use tolerance for decimal bounds such as 0.05. The operation order, integer rounding and min/max relation above are policies rather than hidden tuning.

| Stat | Minimum–maximum |
|---|---|
| `ads_time` | 0.05–1.5 s |
| `rounds_per_minute` | 30–1500 rpm |
| `bolt_cycle_time` | 0–3 s |
| `magazine_size` | 1–200 rounds |
| `reload_tactical_time`, `reload_empty_time` | 0.1–6 s each |
| `recoil_scale` | 0.25–2 |
| `hip_spread_degrees`, `aimed_spread_degrees`, `max_bloom_degrees` | 0–15° each |
| `spread_per_shot_degrees` | 0–5° |
| `recoil_recovery_rate` | 0–90°/s |
| `raise_time`, `lower_time` | 0.05–2 s each |
| `ads_fov_degrees` | 2–90° |
| `ads_sensitivity_scale` | 0.05–1 |
| `sight_height_m` | 0–0.5 m |
| `projectile.muzzle_velocity` | 50–1500 m/s |
| `projectile.damage` | 0–500 |
| `projectile.falloff_start_distance`, `projectile.falloff_end_distance` | 0–1000 m each |
| `projectile.min_damage_fraction` | 0–1 |

| File | New values / defaults |
|---|---|
| `weapons/weapon_data.gd` and `weapons/data/*.tres` | New default metadata: rifle class / primary role, recoil scale 1, iron optic kind 0, bore height 0.010 m. Sniper overrides class to sniper, optic kind to 4 and bore height to 0.012 m. Existing firearm stats are unchanged. |
| `weapons/attachments/attachment_data.gd` | Default part mount `Mount`; optic kind -1 inherits base, default fallback FOV 45° / sight height 0.050 m. Each catalog optic overrides all three values. `StatModifier` default operation MULTIPLY, value 1. |
| `weapons/framework/*.gd`, `*.tres` | Default full-auto / ballistic / magazine kinds. Auto fires while held; other modes require a press. Default comparison mode false; shipped range Resource explicitly true. Enum order is a stable data contract, not a tuning slider. |
| `weapons/viewmodels/halberd_rifle_viewmodel.tscn` | Muzzle `(0,0.010,-0.50)`; barrel `(0,0.010,-0.25)`; optic `(0,0.010,-0.01)`; stock `(0,-0.012,0.25)`; magazine `(0,-0.030,-0.04)`, metres. |
| `weapons/viewmodels/longwatch_sniper_viewmodel.tscn` | Muzzle `(0,0.012,-0.84)`; barrel `(0,0.012,-0.25)`; optic `(0,0.012,-0.01)`; stock `(0,-0.020,0.32)`; magazine `(0,-0.030,-0.03)`, metres. |
| `weapons/attachments/parts/{baffle,ported,compact_cap}.tscn` | Box cross-section 0.045×0.045 m, lengths 0.080 / 0.100 / 0.035 m; extend along -Z from mount, Exit at the end. |
| `weapons/attachments/parts/{long_barrel,short_barrel,heavy_barrel}.tscn` | Cross-section 0.035×0.035 m; lengths 0.350 / 0.180 / 0.300 m, extend along -Z. |
| `weapons/attachments/parts/{brace,light_stock,balanced_stock}.tscn` | Cross-section 0.060×0.100 m; lengths 0.220 / 0.160 / 0.200 m, extend along +Z. |
| `weapons/attachments/parts/{extended_mag,quick_mag,drum}.tscn` | Width 0.040 m, depth 0.065 m; heights 0.170 / 0.090 / 0.220 m, extend along -Y. |
| `weapons/attachments/parts/{iron,red_dot,scope_2x,scope_4x,scope_8x}.tscn` | Stem width / depth 0.018 / 0.035 m, height `optic sight height - 0.020 m`, centre at half stem height. Iron post 0.006×0.020×0.006 m, top at sight height. Red-dot sides 0.006×0.040×0.040 m at X ±0.021 m, centred at sight height; top 0.048×0.006×0.040 m at sight height +0.020 m. Scope radii 0.020 / 0.026 / 0.032 m, lengths 0.140 / 0.190 / 0.240 m, 12 radial segments / one ring, rotated X 90°, axis at sight height. |
| All part `.tscn` files above | Identity Mount transforms; roughness 0.8; shadows off. RGB by slot: muzzle `(0.24,0.27,0.30)`, barrel `(0.32,0.35,0.38)`, optic `(0.20,0.24,0.28)`, stock `(0.34,0.37,0.30)`, magazine `(0.35,0.32,0.24)`, alpha 1. Boxes centred at half their extension length. |
| `ui/hud.gd` | `red_dot_show_aim_blend = 0.85`; existing crosshair hide remains 0.5. Scope model hiding retains the existing WeaponView threshold 0.85. |
| `ui/scope_overlay.gdshader` | New `reticle_kind` default 4 preserves native sniper. Red RGB `(1,0.12,0.08)`; dot radius retains 0.0022 screen heights, alpha fade width 0.001. 2× line alpha 0.85 / existing half-width 0.0011; 4× tick spacing 0.05, phase offset 0.025, half-length 0.008, alpha 0.85. Native circle radius / gap / ring values unchanged. |
| `debug/attachment_debug.gd` | Canvas layer 11; physics priority -10 to collect requests before weapons; selection label offsets left 24 / top -155 / right 600 / bottom -24 px, top / bottom anchored to 1; font 14, outline 3. Label follows F3 visibility, refreshes only on selection / weapon changes. |
| `project.godot` | `attachment_muzzle/barrel/optic/stock/magazine`: F5–F9, physical codes 4194336–4194340; `attachment_clear`: F10, 4194341. Dead zone 0.2. All are InputMap actions and pause with gameplay. |

Debug choices are per weapon and session-only. Nothing writes a loadout file yet; `user://loadout.cfg` belongs to the Armory milestone. No new filesystem dependency, thread or native plugin was introduced into gameplay.

### Verification and performance

New coverage checks frozen zero-attachment stats, arithmetic order / clamps / integer rounding, compatibility, cache reuse, policy composition and source propagation, safe live changes, zero recalibration without mutating launched specs, all catalog trade-offs, every optic's zoom / sight height / model state, red-dot HUD behavior, and F5–F10 fitting / clearing with surviving muzzle effects. The original Milestone 6 tests remain unchanged in intent.

Final full headless GUT run: **269/269 tests, 4,997 assertions, 119.698 s**, clean shutdown with no engine errors. The frozen-fixture comparison proves both computed bare builds retain every original Milestone 6 stat; existing integration tests continue proving their behavior.

Windowed normal startup and the final performance run shut down with zero errors. Movie Maker frames were inspected for the fitted hip model, aligned red-dot ADS and 4× scope / tick reticle. Choices in those captures were baffle / long barrel / red dot (or 4×) / braced stock / extended magazine. Captures and test drivers are temporary files outside the repo.

All figures below use the target Intel Mac, Compatibility, 1280×720, firing with the HUD / diagnostics, eight continuously moving props, three driven steel plates and all **54 min / 54 max** ragdoll parts awake. Each probe measures ten seconds after two seconds of warmup. No tests, captures or commits ran concurrently. Final probes used a temporary SceneTree driver to fit all five parts and restore foreground focus when lost; shipped game focus handling is unchanged.

| Configuration | Focus | Average | 1% low | Worst | Frames >25 ms |
|---|---|---|---|---|---|
| Milestone 6 final capped, historical reference | 100% | 60.0 fps | 49.0 fps | 21.92 ms | 0 / 601 |
| Milestone 6 uncapped, historical reference | 100% | 115.4 fps | 70.6 fps | 15.09 ms | 0 / 1,156 |
| Milestone 7 capped, five parts / fitted irons via debug actions | 100% | 60.0 fps | 42.7 fps | 31.90 ms | 2 / 601 |
| Milestone 7 uncapped, five parts / red dot, foreground driver | 100% | 91.3 fps | 55.4 fps | 19.61 ms | 0 / 914 |
| Milestone 7 final capped, five parts / red dot, foreground driver | 100% | 60.0 fps | 42.6 fps | 30.46 ms | 2 / 600 |

Two preliminary uncapped attempts lost focus (0% and 18%) and are excluded from acceptance comparisons. The valid uncapped run measured 12 / 914 frames above 16.67 ms, median 10.66 ms, with 189 draw calls / 3,906 primitives at the final sample. The final capped run had 190 draw calls / 4,014 primitives and 75 shots. Render counts vary with the ragdoll / prop poses and particles at the sample time. All five fitted parts and the diagnostic selection label add work relative to the MVP; builds themselves never recompute per frame.

The range still averages the requested 60 fps capped, with substantial average uncapped headroom. **This is not a claim that every frame meets 16.67 ms:** uncapped tail frames and two capped pacing spikes remain. The historical MVP table is a reference, not a controlled thermal comparison. Preserve this limitation for the final-arsenal performance pass rather than hiding it behind the average or claiming a nonexistent optimization.

### Recommendations for the remaining Phase 2 plan

1. At the start of Milestone 8, add a logical `shot_id` shared by all pellets / impacts from one trigger event. Route existing hit metadata through that ID so stats count one hit per shot and damage numbers combine per target / shot before pellet delivery ships. `source` alone cannot provide grouping.
2. Keep pump timing and interruptible shell reload state separate from the animation milestone. Build their deterministic gameplay timelines first; Milestone 10 should consume them without driving ammo or damage.
3. When Milestone 9 supplies secondaries, choose a real default secondary and disable the range's explicit comparison exception. Do not reclassify the sniper to satisfy the slot rule.
4. Milestone 11 should edit selections through the existing build boundary and preview independent snapshots. Add stable attachment-ID persistence / validation there; keep authored Resource inputs immutable. Use the same fixed FOV reference in Armory magnification labels.
5. Keep a full-slot assembly in Milestone 12's arsenal stress matrix, including high-zoom ADS, pellet bursts and splash. Budget total draw calls and contacts together; the current tail measurements justify retaining that explicit check.
