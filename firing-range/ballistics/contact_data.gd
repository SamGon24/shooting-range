class_name ContactData
extends Resource
## Swept-sphere reach includes its radius, measured from the gameplay eye.
@export_range(0.1, 3.0, 0.01, "suffix:m") var reach_m: float = 1.8
@export_range(0.01, 0.5, 0.01, "suffix:m") var radius_m: float = 0.12
@export_range(0.0, 50.0, 0.5, "suffix:N·s") var impulse_n_s: float = 6.0
@export_range(1, 32) var max_results: int = 8
