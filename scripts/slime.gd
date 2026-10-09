extends SoftBody3D

@export var camera_follow_speed: float = 6.0
@export var speed: float = 100.0
@export_range(0.0, 1.0) var mouse_sensitivity: float = 0.01
@export var tilt_limit: float = deg_to_rad(75)
## How many soft-body points are averaged to find the slime's centre.
## Lower = cheaper, higher = more accurate. 64 is plenty.
@export var centre_sample_count: int = 64
## How far behind the slime the camera sits. The SpringArm3D decides this,
## not the Camera3D's own position, so tune it here (or via Spring Length).
@export var camera_distance: float = 6.0
## Lifts the point the camera orbits above the slime's centre.
@export var camera_height: float = 3

@export_group("Jump")
## Upward impulse applied on jump. Tune this by feel (see notes): too low =
## barely hops, too high = launches. Depends on Total Mass and physics engine.
@export var jump_impulse: float = 50.0
## Input action used to jump. Falls back to ui_accept (Space/Enter) if the
## action doesn't exist in the Input Map.
@export var jump_action: StringName = "jump"
## How far below the slime's lowest point still counts as "on the ground".
@export var ground_check_distance: float = 0.2
## Which physics layers count as ground.
@export_flags_3d_physics var ground_mask: int = 1
## Minimum time between jumps (stops double-firing right after leaving the ground).
@export var jump_cooldown: float = 0.35
## Pressing jump slightly before landing still counts.
@export var jump_buffer_time: float = 0.15

@onready var spring_arm_3d: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Camera3D

var number_of_points: int = 0
var _sample_stride: int = 1
var _jump_cooldown_left: float = 0.0
var _jump_buffer_left: float = 0.0


func _ready() -> void:
	# 1) The camera rig must not inherit the SoftBody3D node's transform.
	#    The node itself stays where it was placed while the points move,
	#    so we position the rig ourselves in world space.
	spring_arm_3d.top_level = true
	spring_arm_3d.spring_length = camera_distance

	# 2) The spring arm's ray starts INSIDE the slime. Without this it hits
	#    the slime's own surface and the arm collapses to almost zero length.
	spring_arm_3d.add_excluded_object(get_physics_rid())

	# 3) Make sure this camera is the active one (a Camera3D in world.tscn
	#    could otherwise win).
	camera_3d.make_current()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Valid point indices = vertices of the mesh's first surface. This avoids
	# the old "loop until Vector3.ZERO" trick, which can miscount (or give 0
	# and produce a NaN centre) if points aren't ready yet.
	if mesh != null and mesh.get_surface_count() > 0:
		number_of_points = mesh.surface_get_array_len(0)
	_sample_stride = maxi(1, ceili(float(number_of_points) / float(centre_sample_count)))


func _physics_process(delta: float) -> void:
	controls()
	handle_jump(delta)


func _process(delta: float) -> void:
	update_camera(delta)


func update_camera(delta: float) -> void:
	if number_of_points == 0:
		return
	var target: Vector3 = get_centre_approx() + Vector3.UP * camera_height
	if not target.is_finite():
		return

	# Snap on first frame / respawn, otherwise smoothly follow.
	if spring_arm_3d.global_position.distance_to(target) > 20.0:
		spring_arm_3d.global_position = target
		return

	# Frame-rate independent smoothing.
	var weight: float = 1.0 - exp(-camera_follow_speed * delta)
	spring_arm_3d.global_position = spring_arm_3d.global_position.lerp(target, weight)


func controls() -> void:
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction = direction.rotated(Vector3.UP, camera_3d.global_rotation.y)
	if direction:
		apply_central_force(direction * speed)


func handle_jump(delta: float) -> void:
	_jump_cooldown_left = maxf(0.0, _jump_cooldown_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)

	var action: StringName = jump_action if InputMap.has_action(jump_action) else &"ui_accept"
	if Input.is_action_just_pressed(action):
		_jump_buffer_left = jump_buffer_time

	if _jump_buffer_left > 0.0 and _jump_cooldown_left == 0.0 and is_grounded():
		apply_central_impulse(Vector3.UP * jump_impulse)
		_jump_buffer_left = 0.0
		_jump_cooldown_left = jump_cooldown


## A soft body has no "is_on_floor()", so we ray-cast down from its lowest
## point instead. Using the lowest point (not the centre) means it still
## counts as grounded when only part of the slime is on a ledge.
func is_grounded() -> bool:
	if number_of_points == 0:
		return false
	var lowest := get_point_transform(0)
	for i in range(1, number_of_points):
		var p := get_point_transform(i)
		if p.y < lowest.y:
			lowest = p
	var ray_from := lowest + Vector3.UP * 0.1
	var ray_to := lowest + Vector3.DOWN * ground_check_distance
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, ground_mask, [get_physics_rid()])
	var space := get_world_3d().direct_space_state
	return not space.intersect_ray(query).is_empty()


func get_centre_approx() -> Vector3:
	var centre_point := Vector3.ZERO
	var sampled: int = 0
	for i in range(0, number_of_points, _sample_stride):
		centre_point += get_point_transform(i)
		sampled += 1
	return centre_point / sampled


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		spring_arm_3d.rotation.x -= event.relative.y * mouse_sensitivity
		spring_arm_3d.rotation.x = clampf(spring_arm_3d.rotation.x, -tilt_limit, tilt_limit)
		spring_arm_3d.rotation.y -= event.relative.x * mouse_sensitivity
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
