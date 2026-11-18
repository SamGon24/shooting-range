class_name LoadoutConfig
extends RefCounted
## Catalog-only persistence. File contents never become load() paths.

const SAVE_PATH: String = "user://loadout.cfg"
const PRIMARY_PATH: String = "res://weapons/data/primary_catalog.tres"
const SECONDARY_PATH: String = "res://weapons/data/secondary_catalog.tres"
const ATTACHMENT_PATH: String = "res://weapons/attachments/data/catalog.tres"
const DEFAULT_PATH: String = "res://weapons/data/range_loadout.tres"

var primary: WeaponData
var secondary: WeaponData
var _primaries: WeaponCatalog
var _secondaries: WeaponCatalog
var _attachments: AttachmentCatalog
var _default: WeaponLoadout
var _builds: Dictionary[WeaponData, WeaponBuild] = {}


func _init() -> void:
	# Load authored data when a configuration is created, after scripts and
	# autoloads are ready. Never load a path read from the save file.
	_primaries = load(PRIMARY_PATH) as WeaponCatalog
	_secondaries = load(SECONDARY_PATH) as WeaponCatalog
	_attachments = load(ATTACHMENT_PATH) as AttachmentCatalog
	_default = load(DEFAULT_PATH) as WeaponLoadout
	primary = _default.primary
	secondary = _default.secondary


func attachment_catalog() -> AttachmentCatalog:
	return _attachments


func choices(role: WeaponTypes.Role) -> Array[WeaponData]:
	return _primaries.primaries if role == WeaponTypes.Role.PRIMARY else _secondaries.secondaries


func select(role: WeaponTypes.Role, definition: WeaponData) -> bool:
	if definition == null or definition.role != role or not choices(role).has(definition):
		return false
	if role == WeaponTypes.Role.PRIMARY:
		primary = definition
	else:
		secondary = definition
	return true


func selection(role: WeaponTypes.Role) -> WeaponData:
	if role == WeaponTypes.Role.PRIMARY:
		return primary
	return secondary


func get_build(definition: WeaponData) -> WeaponBuild:
	if definition == null or not choices(definition.role).has(definition):
		return null
	if not _builds.has(definition):
		_builds[definition] = WeaponBuild.new(definition)
	return _builds[definition]


func set_attachment(definition: WeaponData, slot: WeaponTypes.Slot, attachment: AttachmentData) -> bool:
	var build: WeaponBuild = get_build(definition)
	if build == null or slot < 0 or slot >= WeaponTypes.SLOT_NAMES.size():
		return false
	if attachment != null and not _attachments.choices.has(attachment):
		return false
	return build.set_attachment(slot, attachment)


func copy() -> LoadoutConfig:
	var result := LoadoutConfig.new()
	result.primary = primary
	result.secondary = secondary
	for definition: WeaponData in _builds:
		for attachment: AttachmentData in _builds[definition].get_attachments():
			result.set_attachment(definition, attachment.slot, attachment)
	return result


func save_to_disk(path: String = SAVE_PATH) -> Error:
	var file := ConfigFile.new()
	file.set_value("loadout", "version", 1)
	file.set_value("loadout", "primary", primary.resource_path)
	file.set_value("loadout", "secondary", secondary.resource_path)
	for definition: WeaponData in _builds:
		for attachment: AttachmentData in _builds[definition].get_attachments():
			file.set_value(definition.resource_path, WeaponTypes.SLOT_NAMES[attachment.slot], String(attachment.id))
	return file.save(path)


func load_from_disk(path: String = SAVE_PATH) -> Error:
	primary = _default.primary
	secondary = _default.secondary
	_builds.clear()
	var file := ConfigFile.new()
	var error: Error = file.load(path)
	if error != OK:
		return error
	var version: Variant = file.get_value("loadout", "version", 0)
	if not version is int or version != 1:
		return ERR_INVALID_DATA
	for role: WeaponTypes.Role in [WeaponTypes.Role.PRIMARY, WeaponTypes.Role.SECONDARY]:
		var key: String = "primary" if role == WeaponTypes.Role.PRIMARY else "secondary"
		var saved: Variant = file.get_value("loadout", key, "")
		for definition: WeaponData in choices(role):
			if saved is String and saved == definition.resource_path:
				select(role, definition)
			for slot: int in WeaponTypes.SLOT_NAMES.size():
				var id: Variant = file.get_value(definition.resource_path, WeaponTypes.SLOT_NAMES[slot], "")
				if not id is String:
					continue
				for attachment: AttachmentData in _attachments.choices:
					if id == String(attachment.id):
						set_attachment(definition, slot as WeaponTypes.Slot, attachment)
	return OK
