class_name WeaponData
extends Resource
## Every stat for one weapon. Weapon code reads these and holds no numbers of
## its own. The weapons live in `weapons/data/*.tres`.

@export var display_name: String = "Weapon"

@export_group("Fire")
## True fires for as long as the trigger is held; false needs a press per shot.
@export var automatic: bool = true
## Cyclic rate of fire, rounds per minute.
@export_range(30.0, 1500.0, 1.0, "suffix:rpm") var rounds_per_minute: float = 700.0
## Time to work the bolt after a shot. 0 for weapons without one. The next
## shot waits for whichever is longer: this or the cyclic rate.
@export_range(0.0, 3.0, 0.01, "suffix:s") var bolt_cycle_time: float = 0.0
## What the weapon fires (muzzle velocity and, later, drag and damage).
@export var projectile: ProjectileSpec

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

@export_group("Aim down sights")
## Time to go from hip to fully aimed, and back.
@export_range(0.05, 1.5, 0.01, "suffix:s") var ads_time: float = 0.25
## Vertical field of view when fully aimed, degrees.
@export_range(2.0, 90.0, 0.5, "suffix:°") var ads_fov_degrees: float = 45.0
## Mouse sensitivity multiplier when fully aimed.
@export_range(0.05, 1.0, 0.01) var ads_sensitivity_scale: float = 0.7
## True draws the scope overlay and hides the viewmodel when aimed.
@export var scoped: bool = false

@export_group("Switching")
## Time to bring the weapon up after switching to it.
@export_range(0.05, 2.0, 0.01, "suffix:s") var raise_time: float = 0.4
## Time to put the weapon away when switching from it.
@export_range(0.05, 2.0, 0.01, "suffix:s") var lower_time: float = 0.3

@export_group("Viewmodel (cosmetic)")
@export var viewmodel_scene: PackedScene
## Viewmodel position relative to the camera when firing from the hip.
@export var hip_position: Vector3 = Vector3(0.17, -0.17, -0.42)
## Viewmodel position when fully aimed, so the sights sit on the screen centre.
@export var ads_position: Vector3 = Vector3(0.0, -0.085, -0.34)
## How far the viewmodel jumps back per shot, metres.
@export_range(0.0, 0.3, 0.005, "suffix:m") var kick_back: float = 0.04
## How far the viewmodel muzzle climbs per shot, degrees.
@export_range(0.0, 20.0, 0.1, "suffix:°") var kick_pitch_degrees: float = 2.0

@export_group("Sound (placeholder)")
## Base pitch of the generated shot sound, Hz. Lower sounds heavier.
@export_range(30.0, 400.0, 1.0, "suffix:Hz") var shot_sound_pitch_hz: float = 110.0
@export_range(0.05, 1.0, 0.01, "suffix:s") var shot_sound_duration: float = 0.22


## Seconds between shots.
func shot_interval() -> float:
	return maxf(60.0 / rounds_per_minute, bolt_cycle_time)


## Reload duration for a magazine holding `ammo_in_magazine` rounds.
func reload_time(ammo_in_magazine: int) -> float:
	return reload_empty_time if ammo_in_magazine <= 0 else reload_tactical_time
