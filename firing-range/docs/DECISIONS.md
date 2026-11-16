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
