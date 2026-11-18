class_name WeaponRuntime
extends RefCounted
## Session state survives exchanging the primary slot at the range.
var build: WeaponBuild
var logic: WeaponLogic
var recoil: RecoilLogic
## Zero distance the player picked for this weapon, metres. 0 keeps the
## Resource's `zero_distance_m`.
var selected_zero_m: float = 0.0


func _init(definition: WeaponData, rng: RandomNumberGenerator) -> void:
	build = WeaponBuild.new(definition)
	var computed: WeaponData = build.get_stats()
	logic = WeaponLogic.new(computed)
	recoil = RecoilLogic.new(computed, rng)
