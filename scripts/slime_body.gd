extends SoftBody3D
## Visible, physically-simulated slime blob.
## Pins the vertices near the bottom of the mesh to the driver RigidBody3D
## so the slime follows the driver's movement while the rest of the mesh
## stays free to squash, stretch and jiggle like real slime.

@export var driver_path: NodePath
@export var pin_height_fraction: float = 0.18  ## bottom slice of the mesh counted as "feet"
@export var max_pins: int = 10

func _ready() -> void:
	if driver_path.is_empty():
		push_warning("SlimeBody: set 'driver_path' in the Inspector to the driver RigidBody3D.")
		return
	# Wait a frame so the physics server has finished building the soft body
	# before we start touching it.
	call_deferred("_setup")

func _setup() -> void:
	var driver := get_node(driver_path)
	# Without this, the driver's own collision shape pushes against the
	# slime's points from the inside - which is what makes it look like
	# cloth draped over a ball instead of a self-contained blob. Ignoring
	# collision between the two lets pinning alone carry the movement,
	# while the mesh's shape is free to respond only to the environment.
	if driver is PhysicsBody3D:
		add_collision_exception_with(driver)
	_pin_bottom_points()

func _pin_bottom_points() -> void:
	if mesh == null:
		push_warning("SlimeBody: no mesh assigned, can't find vertices to pin.")
		return

	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return

	var min_y := INF
	var max_y := -INF
	for v in verts:
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)

	var threshold := min_y + (max_y - min_y) * pin_height_fraction
	var candidates: Array[int] = []
	for i in verts.size():
		if verts[i].y <= threshold:
			candidates.append(i)

	# Pin the lowest points first, capped at max_pins so the blob still
	# has plenty of freedom to deform.
	candidates.sort_custom(func(a, b): return verts[a].y < verts[b].y)
	var count: int = min(max_pins, candidates.size())
	for i in count:
		set_point_pinned(candidates[i], true, driver_path)
