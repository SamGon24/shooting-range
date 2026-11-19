class_name WeaponData
extends Resource
## Every stat for one weapon. Weapon code reads these and holds no numbers of
## its own. The weapons live in `weapons/data/*.tres`.

@export var weapon_class: WeaponTypes.Class = WeaponTypes.Class.RIFLE
@export var role: WeaponTypes.Role = WeaponTypes.Role.PRIMARY
@export var fire_mode: FireModeData
@export var delivery: DeliveryData
@export var reload_policy: ReloadData
@export var uses_ammo: bool = true
@export var can_aim: bool = true
@export_range(0.1, 1.0, 0.05) var movement_speed_scale: float = 1.0
@export var guard: GuardData
## Computed snapshots point to the original definition, never the reverse.
var base_definition: WeaponData
@export var bore_height_m: float = 0.01
@export var recoil_scale: float = 1.0
@export_enum("Iron:0", "Red dot:1", "2x:2", "4x:3", "8x:4", "Hybrid 3.5x:5") var optic_kind: int = 0
var _legacy_automatic: bool = true

@export var display_name: String = "Weapon"

@export_group("Fire")
## True fires for as long as the trigger is held; false needs a press per shot.
@export var automatic: bool = true:
	get:
		return fire_mode.kind == FireModeData.Kind.FULL_AUTO if fire_mode != null else _legacy_automatic
	set(value):
		_legacy_automatic = value
		if fire_mode != null and value != (fire_mode.kind == FireModeData.Kind.FULL_AUTO):
			fire_mode = fire_mode.duplicate() as FireModeData
			fire_mode.kind = FireModeData.Kind.FULL_AUTO if value else FireModeData.Kind.SEMI_AUTO
## Cyclic rate of fire, rounds per minute.
@export_range(30.0, 1500.0, 1.0, "suffix:rpm") var rounds_per_minute: float = 700.0
## Time to work the bolt after a shot. 0 for weapons without one. The next
## shot waits for whichever is longer: this or the cyclic rate.
@export_range(0.0, 3.0, 0.01, "suffix:s") var bolt_cycle_time: float = 0.0
## Recovery after sprint ends; zero preserves the original MVP handling.
@export_range(0.0, 2.0, 0.01, "suffix:s") var sprint_to_fire_time: float = 0.0
## What the weapon fires (muzzle velocity and, later, drag and damage).
@export var projectile: ProjectileSpec

@export_group("Sight zero")
## Horizontal distance where a level sight line meets the calibrated path.
## 0 disables angular calibration (the bore offset still applies).
@export_range(0.0, 1000.0, 1.0, "suffix:m") var zero_distance_m: float = 100.0
## Distances the player may cycle the zero through with the zero key. Empty
## means the zero is fixed. `zero_distance_m` is the starting choice.
@export var zero_options: PackedFloat32Array = PackedFloat32Array()
## Sight line above the bore, measured from the reference viewmodel geometry.
## Gameplay uses this fixed value, never the animated viewmodel transform.
@export_range(0.0, 0.5, 0.001, "suffix:m") var sight_height_m: float = 0.0

@export_group("Magazine")
@export_range(1, 200) var magazine_size: int = 30
## Reload time with rounds left in the magazine.
@export_range(0.1, 6.0, 0.01, "suffix:s") var reload_tactical_time: float = 1.9
## Reload time from an empty magazine (includes chambering a round).
@export_range(0.1, 6.0, 0.01, "suffix:s") var reload_empty_time: float = 2.4

@export_group("Recoil")
## View kick per shot in degrees: x is yaw (positive right), y is pitch
## (positive up). Shot 1 uses the first entry, shot 2 the second, and so on.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.5)])
## Past the end of the pattern, the last this-many entries repeat.
@export_range(1, 100) var recoil_loop_length: int = 1
## Random kick added to every shot, up to ± this many degrees (x yaw, y pitch).
@export var recoil_random_degrees: Vector2 = Vector2.ZERO
## Kick multiplier when fully aimed.
@export_range(0.0, 2.0, 0.01) var aimed_recoil_scale: float = 1.0
## Seconds without a shot before the view starts to recover.
@export_range(0.0, 2.0, 0.01, "suffix:s") var recoil_recovery_delay: float = 0.12
## How fast unrecovered view kick returns, degrees per second. Kick the
## player has already pulled down does not recover again.
@export_range(0.0, 90.0, 0.1, "suffix:°/s") var recoil_recovery_rate: float = 10.0
## Seconds without a shot before the pattern starts again from shot 1.
@export_range(0.0, 5.0, 0.01, "suffix:s") var recoil_reset_time: float = 0.3

@export_group("Spread")
## Shots leave inside a cone around the aim. Half-angle from the hip, degrees.
@export_range(0.0, 15.0, 0.05, "suffix:°") var hip_spread_degrees: float = 2.0
## Cone half-angle when fully aimed. With 0, the first shot from a settled
## weapon goes exactly where the sights point.
@export_range(0.0, 15.0, 0.05, "suffix:°") var aimed_spread_degrees: float = 0.0
## Cone added by each shot (bloom), degrees.
@export_range(0.0, 5.0, 0.01, "suffix:°") var spread_per_shot_degrees: float = 0.0
@export_range(0.0, 15.0, 0.05, "suffix:°") var max_bloom_degrees: float = 1.0
## How fast bloom shrinks once `recoil_recovery_delay` has passed without
## a shot, degrees per second.
@export_range(0.0, 60.0, 0.1, "suffix:°/s") var bloom_recovery_rate: float = 4.0

@export_group("Aim down sights")
## Time to go from hip to fully aimed, and back.
@export_range(0.05, 1.5, 0.01, "suffix:s") var ads_time: float = 0.25
## Vertical field of view when fully aimed, degrees.
@export_range(2.0, 90.0, 0.5, "suffix:°") var ads_fov_degrees: float = 45.0
## Mouse sensitivity multiplier when fully aimed.
@export_range(0.05, 1.0, 0.01) var ads_sensitivity_scale: float = 0.7
## True for the 8x blackout presentation, which hides the aimed viewmodel.
@export var scoped: bool = false

@export_group("Switching")
## Time to bring the weapon up after switching to it.
@export_range(0.05, 2.0, 0.01, "suffix:s") var raise_time: float = 0.4
## Time to put the weapon away when switching from it.
@export_range(0.05, 2.0, 0.01, "suffix:s") var lower_time: float = 0.3

@export_group("Viewmodel (cosmetic)")
@export var viewmodel_scene: PackedScene
## Procedural reload / cycle / equip / melee animation for the viewmodel.
## Its timings are fractions of this weapon's own Resource times.
@export var handling: HandlingProfile
## Viewmodel position relative to the camera when firing from the hip.
@export var hip_position: Vector3 = Vector3(0.17, -0.17, -0.42)
## Viewmodel position when fully aimed, so the sights sit on the screen centre.
@export var ads_position: Vector3 = Vector3(0.0, -0.085, -0.34)
## How far the viewmodel jumps back per shot, metres.
@export_range(0.0, 0.3, 0.005, "suffix:m") var kick_back: float = 0.04
## How far the viewmodel muzzle climbs per shot, degrees.
@export_range(0.0, 20.0, 0.1, "suffix:°") var kick_pitch_degrees: float = 2.0

@export_group("Smoke and casings (cosmetic)")
## Smoke particles puffed from the muzzle per shot. 0 for none.
@export_range(0, 12) var muzzle_smoke_particles: int = 0
## Ejected casing box: thickness X and Y, length Z, metres. Zero size means
## the weapon ejects nothing.
@export var casing_size: Vector3 = Vector3.ZERO
## Ejection port in the viewmodel's own space; +X is out of the weapon's side.
@export var casing_port: Vector3 = Vector3(0.03, 0.02, 0.05)
@export var casing_color: Color = Color(0.8, 0.62, 0.25)
## Seconds after the shot the casing is thrown: 0 for self-loaders, and the
## time the bolt or pump takes to open for manual actions.
@export_range(0.0, 1.0, 0.01, "suffix:s") var casing_eject_delay_s: float = 0.0

@export_group("Sound (placeholder)")
## Base pitch of the generated shot sound, Hz. Lower sounds heavier.
@export_range(30.0, 400.0, 1.0, "suffix:Hz") var shot_sound_pitch_hz: float = 110.0
@export_range(0.05, 1.0, 0.01, "suffix:s") var shot_sound_duration: float = 0.22


## Seconds between shots.
func shot_interval() -> float:
	return fire_mode.interval(rounds_per_minute, bolt_cycle_time) if fire_mode != null else maxf(60.0 / rounds_per_minute, bolt_cycle_time)


## Reload duration for a magazine holding `ammo_in_magazine` rounds.
func reload_time(ammo_in_magazine: int) -> float:
	return reload_empty_time if ammo_in_magazine <= 0 else reload_tactical_time


func definition() -> WeaponData:
	return base_definition if base_definition != null else self


func wants_shot(held: bool, pressed: bool) -> bool:
	return fire_mode.wants_shot(held, pressed) if fire_mode != null else (held if automatic else pressed)

## Nonzero only for optics whose zoom follows the selected player FOV.
@export var optic_magnification: float = 0.0
