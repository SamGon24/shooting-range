class_name WeaponRuntime
extends RefCounted
## Session state survives exchanging the primary slot at the range.
var build: WeaponBuild
var logic: WeaponLogic
var recoil: RecoilLogic


func _init(definition: WeaponData, rng: RandomNumberGenerator) -> void:
	build = WeaponBuild.new(definition)
	var computed: WeaponData = build.get_stats()
	logic = WeaponLogic.new(computed)
	recoil = RecoilLogic.new(computed, rng)
