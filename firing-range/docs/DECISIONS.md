# Decisions

Non-obvious choices, newest milestone last. Each entry says what was chosen, why, and what would make us revisit it.

Target machine for every measurement below: MacBook Pro, Intel i5-8259U, 8 GB, Intel Iris Plus Graphics 655, macOS Sequoia, Godot 4.7.2 stable.

## Project setup

### Renderer: Mobile (kept), with three restrictions on this GPU

Mobile holds 60 fps with a wide margin (see Performance), so the rule in `CLAUDE.md` says stay on it. On this Intel GPU it runs through Vulkan on MoltenVK, and three things do not work:

| Problem | Evidence | What we do |
|---|---|---|
| 8 engine compute pipelines fail to compile at startup (`Compute pipeline compile failed ... AIR builtin function was called but no definition was found`) | Happens with an empty scene, before any project code runs | Nothing we can fix. They are logged on every windowed boot. Avoid engine features that need compute shaders. |
| A `Sky` background triggers 14 more errors on the first frame, and sky-based ambient light renders black or blocky | Reproduced in a 3-node test scene; gone with a colour background | Background is a flat colour, ambient light is a fixed colour, reflections are off. No `Sky` resource anywhere. |
| Sun shadows misrender while the camera turns upward: the far shadow cascade marks the whole ground as shadowed for those frames | Scripted jerky-camera capture: 2 splits about 40% of the lower frame dark, 4 splits about 20%, single cascade about 90%. A still camera is fine. Not caused by physics interpolation (same result with it off). | The sun's `shadow_enabled` is off. Shapes are read from direct light plus ambient only. |

The Compatibility renderer has none of these problems on this machine: zero startup errors and clean sun shadows in the same jerky-camera test. It is slower here (about 174 fps with shadows, against about 300 fps for Mobile without) but still nearly three times the budget.

**Open decision for the project owner:** switching to Compatibility would restore sun shadows and remove the startup errors. `CLAUDE.md` only allows that switch for frame rate, so it has not been made. Things that would force the question: Milestone 2 muzzle flash and impact particles (GPU particles may hit the same compute failures; CPU particles are the fallback on Mobile), and Milestone 4 targets, which read much better with shadows.

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
