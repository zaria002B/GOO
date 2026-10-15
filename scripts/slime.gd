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

@export_group("Wall Stick")
## Hold this action next to a wall to stick to it. Falls back to E if the
## action doesn't exist in the Input Map.
@export var stick_action: StringName = "stick"
## Climb / shimmy speed on the wall, in metres per second.
@export var climb_speed: float = 2.5
## How far from the slime's surface a wall can be and still be grabbed.
@export var wall_check_distance: float = 0.4
## Number of horizontal rays used to look for a wall around the slime.
@export var wall_ray_count: int = 8
## Which physics layers count as climbable walls.
@export_flags_3d_physics var wall_mask: int = 1
## Surfaces whose normal tilts up/down more than this are treated as floor/ceiling.
@export_range(0.0, 1.0) var max_wall_normal_y: float = 0.35
## How strongly the slime is steered toward its target wall velocity.
## Higher = snappier and grippier, lower = floaty.
@export var wall_control_gain: float = 8.0
## 1.0 cancels gravity exactly. If it slides down the wall, raise it a little
## (1.1, 1.2). If it drifts upward on its own, lower it.
@export var wall_hold_strength: float = 1.0
## Gentle speed pressing the slime into the wall so it stays in contact.
@export var wall_press_speed: float = 0.5
## Safety cap on the wall force, as an acceleration (m/s^2).
@export var wall_max_accel: float = 60.0
## Jumping while stuck kicks off the wall. How much of the kick points away from it.
@export var wall_jump_push: float = 0.6
## After letting go or wall-jumping, how long before it can stick again.
@export var wall_release_time: float = 0.3

@export_group("Sprint & Crouch")
## Hold to move faster (also speeds up wall climbing). Falls back to Shift
## if the action doesn't exist in the Input Map.
@export var sprint_action: StringName = "sprint"
## Multiplier applied to movement speed while sprinting.
@export var sprint_multiplier: float = 1.8
## Hold to push the slime downward and flatten it so it can squeeze through
## tight gaps below (grates, drains). Falls back to C if the action doesn't exist.
@export var crouch_action: StringName = "crouch"
## Extra downward acceleration (m/s^2) while crouching, on top of gravity.
## If it won't go through a gap, raise it. If it squashes too violently, lower it.
@export var crouch_down_accel: float = 30.0
## Walking speed multiplier while crouching (creeping is more controllable).
@export var crouch_move_multiplier: float = 0.6

@onready var spring_arm_3d: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Camera3D

var number_of_points: int = 0
var is_stuck: bool = false

var _sample_stride: int = 1
var _jump_cooldown_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _stick_lockout_left: float = 0.0
var _wall_normal: Vector3 = Vector3.ZERO
var _prev_centre: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _has_prev: bool = false
var _gravity: float = 9.8


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

	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

	# Valid point indices = vertices of the mesh's first surface. This avoids
	# the old "loop until Vector3.ZERO" trick, which can miscount (or give 0
	# and produce a NaN centre) if points aren't ready yet.
	if mesh != null and mesh.get_surface_count() > 0:
		number_of_points = mesh.surface_get_array_len(0)
	_sample_stride = maxi(1, ceili(float(number_of_points) / float(centre_sample_count)))


func _physics_process(delta: float) -> void:
	var centre := get_centre_approx()
	_update_velocity(centre, delta)

	_stick_lockout_left = maxf(0.0, _stick_lockout_left - delta)
	update_wall_stick(centre)

	if is_stuck:
		wall_controls()
	else:
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

	var crouching := is_crouch_pressed()
	var move_speed := speed
	if crouching:
		move_speed *= crouch_move_multiplier
	elif is_sprint_pressed():
		move_speed *= sprint_multiplier

	# One combined force per frame (safer than calling apply_central_force twice).
	var force := direction * move_speed
	if crouching:
		# Push the whole body down: flattens it against the floor and drives it
		# through gaps below. Not applied while stuck to a wall (crouch lets go).
		force += Vector3.DOWN * total_mass * crouch_down_accel
	if force != Vector3.ZERO:
		apply_central_force(force)


# ---------------------------------------------------------------- wall stick

## Uses the Input Map action if it exists, otherwise a hard-coded key so
## everything works before you've set up the actions.
func _action_or_key(action: StringName, fallback_key: Key) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_key_pressed(fallback_key)


func is_stick_pressed() -> bool:
	return _action_or_key(stick_action, KEY_E)


func is_sprint_pressed() -> bool:
	return _action_or_key(sprint_action, KEY_SHIFT)


func is_crouch_pressed() -> bool:
	return _action_or_key(crouch_action, KEY_C)


## A soft body reports no contacts, so we look for walls by casting rays
## outward from its centre in a ring. The nearest near-vertical hit becomes
## the wall we stick to.
func update_wall_stick(centre: Vector3) -> void:
	is_stuck = false
	if _stick_lockout_left > 0.0 or number_of_points == 0 or not is_stick_pressed():
		return
	# Crouch overrides stick: holding it lets go of the wall and drops you.
	if is_crouch_pressed():
		return

	var reach := _estimate_radius(centre) + wall_check_distance
	var space := get_world_3d().direct_space_state
	var best_dist := INF
	var best_normal := Vector3.ZERO

	for i in wall_ray_count:
		var angle := TAU * float(i) / float(wall_ray_count)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(centre, centre + dir * reach, wall_mask, [get_physics_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > max_wall_normal_y:
			continue
		var p: Vector3 = hit["position"]
		var d := centre.distance_to(p)
		if d < best_dist:
			best_dist = d
			best_normal = n

	if best_normal == Vector3.ZERO:
		return

	best_normal.y = 0.0
	_wall_normal = best_normal.normalized()
	is_stuck = true


## While stuck, steer the slime toward a target velocity along the wall
## (a velocity controller), cancel gravity, and press gently into the wall.
func wall_controls() -> void:
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var n := _wall_normal

	# Left/right follows the camera's right direction, flattened onto the wall.
	var lateral := camera_3d.global_basis.x
	lateral = lateral - n * lateral.dot(n)
	if lateral.length_squared() < 0.01:
		lateral = Vector3.UP.cross(n)
	lateral = lateral.normalized()

	var climb := climb_speed
	if is_sprint_pressed():
		climb *= sprint_multiplier

	var target_velocity := lateral * input_dir.x * climb \
			+ Vector3.UP * -input_dir.y * climb \
			- n * wall_press_speed

	var force := (target_velocity - _velocity) * total_mass * wall_control_gain
	force += Vector3.UP * total_mass * _gravity * wall_hold_strength
	force = force.limit_length(total_mass * wall_max_accel)
	apply_central_force(force)


func _estimate_radius(centre: Vector3) -> float:
	var r := 0.0
	for i in range(0, number_of_points, _sample_stride):
		var p := get_point_transform(i)
		r = maxf(r, Vector2(p.x - centre.x, p.z - centre.z).length())
	return r


## SoftBody3D has no velocity property, so we estimate it from how the
## centre moved since the last physics frame (lightly smoothed).
func _update_velocity(centre: Vector3, delta: float) -> void:
	if _has_prev and delta > 0.0:
		var raw := (centre - _prev_centre) / delta
		_velocity = _velocity.lerp(raw, 0.5)
	_prev_centre = centre
	_has_prev = true


# ---------------------------------------------------------------------- jump

func handle_jump(delta: float) -> void:
	_jump_cooldown_left = maxf(0.0, _jump_cooldown_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)

	var action: StringName = jump_action if InputMap.has_action(jump_action) else &"ui_accept"
	if Input.is_action_just_pressed(action):
		_jump_buffer_left = jump_buffer_time

	if _jump_buffer_left <= 0.0 or _jump_cooldown_left > 0.0:
		return

	if is_stuck:
		# Wall jump: kick away from the wall and up, then briefly can't re-stick.
		var kick := (_wall_normal * wall_jump_push + Vector3.UP).normalized()
		apply_central_impulse(kick * jump_impulse)
		_stick_lockout_left = wall_release_time
	elif is_grounded():
		apply_central_impulse(Vector3.UP * jump_impulse)
	else:
		return

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
	return centre_point / maxi(sampled, 1)


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
