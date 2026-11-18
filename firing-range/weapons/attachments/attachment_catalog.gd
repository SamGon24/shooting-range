class_name AttachmentCatalog
extends Resource
@export var choices: Array[AttachmentData] = []


func for_slot(slot: WeaponTypes.Slot, weapon_class: WeaponTypes.Class) -> Array[AttachmentData]:
	var result: Array[AttachmentData] = []
	for attachment: AttachmentData in choices:
		if attachment.slot == slot and attachment.accepts(weapon_class):
			result.append(attachment)
	return result


func next_attachment(current: AttachmentData, slot: WeaponTypes.Slot, weapon_class: WeaponTypes.Class) -> AttachmentData:
	var compatible: Array[AttachmentData] = for_slot(slot, weapon_class)
	if compatible.is_empty():
		return null
	var next: int = compatible.find(current) + 1
	return compatible[next] if next < compatible.size() else null
