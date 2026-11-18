class_name WeaponTypes
extends RefCounted

enum Class { SMG, RIFLE, SNIPER, LMG, SHOTGUN, PISTOL, ROCKET, KNIFE, SHIELD }
enum Role { PRIMARY, SECONDARY }
enum Slot { MUZZLE, BARREL, OPTIC, STOCK, MAGAZINE }
const SLOT_NAMES: PackedStringArray = ["Muzzle", "Barrel", "Optic", "Stock", "Magazine"]


static func allows_slot(weapon_class: Class, slot: Slot) -> bool:
	if weapon_class <= Class.SHOTGUN:
		return true
	return weapon_class == Class.PISTOL and slot in [Slot.MUZZLE, Slot.OPTIC, Slot.MAGAZINE]
