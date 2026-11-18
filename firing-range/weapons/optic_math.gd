class_name OpticMath
extends RefCounted
## Tangent-space magnification; independent of aspect ratio and input device.
static func fov_for_zoom(reference_fov: float, zoom: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(reference_fov) * 0.5) / zoom))

static func sensitivity_for_zoom(zoom: float) -> float:
	return 1.0 / zoom

static func lens_fov(reference_fov: float, zoom: float, lens_height_fraction: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(reference_fov) * 0.5) * lens_height_fraction / zoom))
