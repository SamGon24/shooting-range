class_name OpticMath
extends RefCounted
## Tangent-space magnification; independent of aspect ratio and input device.
static func fov_for_zoom(reference_fov: float, zoom: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(reference_fov) * 0.5) / zoom))

static func sensitivity_for_zoom(zoom: float) -> float:
	return 1.0 / zoom

static func lens_fov(reference_fov: float, zoom: float, lens_height_fraction: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(reference_fov) * 0.5) * lens_height_fraction / zoom))

static func target_fov(data: WeaponData, reference_fov: float) -> float:
	return fov_for_zoom(reference_fov, data.optic_magnification) if data.optic_kind == 5 else data.ads_fov_degrees

static func screen_lens_zoom(source_fov: float, target_fov_degrees: float) -> float:
	return tan(deg_to_rad(source_fov) * 0.5) / tan(deg_to_rad(target_fov_degrees) * 0.5)
