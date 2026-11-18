class_name WeaponBuild
extends RefCounted
## Base definitions and equipped attachments are immutable inputs. Changes
## go through set_attachment; get_stats never recomputes an unchanged build.

const LIMITS: StatLimits = preload("res://weapons/attachments/data/stat_limits.tres")
var base: WeaponData
var computation_count: int = 0
var _attachments: Dictionary[int, AttachmentData] = {}
var _computed: WeaponData


func _init(definition: WeaponData) -> void:
	base = definition


func can_attach(slot: WeaponTypes.Slot, attachment: AttachmentData) -> bool:
	if attachment != null:
		if attachment.slot != slot or not attachment.accepts(base.weapon_class):
			return false
		if attachment.optic_kind < -1 or attachment.optic_kind > 4 or not is_finite(attachment.optic_fov_degrees) or not is_finite(attachment.optic_sight_height_m):
			return false
		for modifier: StatModifier in attachment.modifiers:
			if modifier == null or not LIMITS.bounds.has(modifier.stat) or not is_finite(modifier.value):
				return false
			if modifier.operation == StatModifier.Operation.MULTIPLY and modifier.value < 0.0:
				return false
	return true


func set_attachment(slot: WeaponTypes.Slot, attachment: AttachmentData) -> bool:
	if not can_attach(slot, attachment):
		return false
	if _attachments.get(slot) == attachment:
		return true
	if attachment == null:
		_attachments.erase(slot)
	else:
		_attachments[slot] = attachment
	_computed = null
	return true


func get_attachment(slot: WeaponTypes.Slot) -> AttachmentData:
	return _attachments.get(slot)


func get_attachments() -> Array[AttachmentData]:
	var result: Array[AttachmentData] = []
	for slot: int in WeaponTypes.SLOT_NAMES.size():
		var attachment: AttachmentData = _attachments.get(slot)
		if attachment != null:
			result.append(attachment)
	return result


func get_stats() -> WeaponData:
	if _computed != null:
		return _computed
	computation_count += 1
	_computed = base.duplicate() as WeaponData
	_computed.base_definition = base
	_computed.projectile = base.projectile.duplicate() as ProjectileSpec
	if base.delivery != null and base.delivery.kind == DeliveryData.Kind.PELLET:
		_computed.projectile.source = DamageSource.Kind.PELLET
	elif base.delivery != null and base.delivery.kind == DeliveryData.Kind.MELEE:
		_computed.projectile.source = DamageSource.Kind.MELEE
	var optic: AttachmentData = get_attachment(WeaponTypes.Slot.OPTIC)
	if optic != null and optic.optic_kind >= 0:
		_computed.optic_kind = optic.optic_kind
		_computed.ads_fov_degrees = optic.optic_fov_degrees
		_computed.sight_height_m = optic.optic_sight_height_m
		_computed.scoped = optic.optic_kind >= 2
	var values: Dictionary[StringName, float] = {}
	for stat: StringName in LIMITS.bounds:
		values[stat] = _read(stat)
	# Category order is fixed, with additions before multiplications. Within
	# each category: slot order, then Resource modifier array order.
	for operation: StatModifier.Operation in [StatModifier.Operation.ADD, StatModifier.Operation.MULTIPLY]:
		for attachment: AttachmentData in get_attachments():
			for modifier: StatModifier in attachment.modifiers:
				if modifier.operation != operation:
					continue
				var value: float = values[modifier.stat]
				values[modifier.stat] = value + modifier.value if operation == StatModifier.Operation.ADD else value * modifier.value
	for stat: StringName in LIMITS.bounds:
		var bounds: Vector2 = LIMITS.bounds[stat]
		var value: float = clampf(values[stat], bounds.x, bounds.y)
		if stat == &"magazine_size":
			value = roundf(value)
		_write(stat, value)
	if optic != null and optic.optic_kind >= 0:
		_computed.ads_position.y = -_computed.sight_height_m - base.bore_height_m
	_computed.projectile.falloff_end_distance = maxf(_computed.projectile.falloff_start_distance, _computed.projectile.falloff_end_distance)
	_computed.recoil_pattern = base.recoil_pattern.duplicate()
	for index: int in _computed.recoil_pattern.size():
		_computed.recoil_pattern[index] *= _computed.recoil_scale
	_computed.recoil_random_degrees = base.recoil_random_degrees * _computed.recoil_scale
	return _computed


func _read(path: StringName) -> float:
	if String(path).begins_with("projectile."):
		return float(_computed.projectile.get(String(path).trim_prefix("projectile.")))
	return float(_computed.get(path))


func _write(path: StringName, value: float) -> void:
	if String(path).begins_with("projectile."):
		_computed.projectile.set(String(path).trim_prefix("projectile."), value)
	else:
		_computed.set(path, roundi(value) if path == &"magazine_size" else value)
