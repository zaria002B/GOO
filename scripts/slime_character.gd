extends CharacterBody3D
## Slime character controller.
## - CharacterBody3D + CapsuleShape3D handle real movement/collision.
## - "SlimeMesh" is a plain MeshInstance3D, a direct child of this body, so
##   it is physically impossible for it to separate while moving.
## - The slime automatically senses tight spaces with a ring of raycasts and
##   shrinks/grows to fit, with no input required.
## - The jelly look comes from two layered effects: a macro squash-and-stretch
##   spring on the mesh's scale (this script), plus a per-vertex asynchronous
##   wobble and landing ripple (the ShaderMaterial on SlimeMesh).

# --- Movement tuning ---
@export var walk_speed: float = 4.5
@export var acceleration: float = 12.0
@export var friction: float = 10.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 18.0

# --- Look tuning ---
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_deg: float = -60.0
@export var max_pitch_deg: float = 70.0

# --- Auto-squeeze sensing tuning ---
@export var normal_radius: float = 0.4
@export var normal_height: float = 0.9
@export var squeeze_radius: float = 0.18   # smallest the body can shrink to
@export var squeeze_height: float = 0.45
@export var probe_ray_count: int = 10      # rays cast in a ring around the body
@export var probe_range: float = 0.75      # how far each ray checks (>= normal_radius)
@export var probe_safety_margin: float = 0.04
@export var probe_collision_mask: int = 1
@export var shape_morph_speed: float = 8.0
@export var squeeze_speed_mult: float = 0.55  # how much slower while squeezed

# --- Squash & stretch spring tuning ---
@export var stretch_spring_stiffness: float = 100.0
@export var stretch_spring_damping: float = 10.0
@export var move_stretch_amount: float = 0.28    # how much moving stretches it
@export var land_squash_kick: float = 9.0        # how hard a landing squashes it

# --- Shader ripple tuning ---
@export var landing_impact_base: float = 0.14
@export var landing_impact_speed_scale: float = 0.015  # extra ripple per unit of fall speed

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var slime_mesh: MeshInstance3D = $SlimeMesh
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var slime_material: ShaderMaterial = slime_mesh.material_override as ShaderMaterial

var _pitch: float = 0.0
var _is_squeezing: bool = false
var _current_radius: float
var _current_height: float

var _mesh_scale: Vector3 = Vector3.ONE
var _mesh_scale_velocity: Vector3 = Vector3.ZERO
var _was_on_floor: bool = true

var _impact_elapsed: float = 999.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_current_radius = normal_radius
	_current_height = normal_height
	_apply_capsule_size(_current_radius, _current_height)
	_was_on_floor = is_on_floor()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(
			_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
		camera_pivot.rotation.x = _pitch

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

func _physics_process(delta: float) -> void:
	_handle_auto_squeeze(delta)
	_handle_movement(delta)
	_update_squash_and_stretch(delta)
	_update_shader_impact(delta)

func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := camera.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var wish_dir := (forward * -input_dir.y + right * input_dir.x)
	if wish_dir.length() > 0.0:
		wish_dir = wish_dir.normalized()

	var speed := walk_speed * (squeeze_speed_mult if _is_squeezing else 1.0)
	var target_velocity := wish_dir * speed

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var accel: float = acceleration if wish_dir.length() > 0.0 else friction
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, accel * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	var fall_speed_before_landing := -velocity.y

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not _is_squeezing:
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	var landed_this_frame := is_on_floor() and not _was_on_floor
	if landed_this_frame:
		_apply_landing_squash(fall_speed_before_landing)
	_was_on_floor = is_on_floor()

## Casts a ring of rays around the body to find the tightest gap nearby, then
## sets that as the target capsule size. No button needed - it just fits.
func _handle_auto_squeeze(delta: float) -> void:
	var available_radius := _measure_available_radius()

	var squeeze_span := normal_radius - squeeze_radius
	var squeeze_factor := 0.0
	if squeeze_span > 0.0:
		squeeze_factor = clamp((normal_radius - available_radius) / squeeze_span, 0.0, 1.0)

	var target_radius := available_radius
	var target_height: float = lerp(normal_height, squeeze_height, squeeze_factor)

	_current_radius = move_toward(_current_radius, target_radius, shape_morph_speed * delta)
	_current_height = move_toward(_current_height, target_height, shape_morph_speed * delta)
	_apply_capsule_size(_current_radius, _current_height)

	_is_squeezing = squeeze_factor > 0.05

func _measure_available_radius() -> float:
	var space_state := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 0.05, 0.0)
	var min_distance := probe_range
	var found_hit := false

	for i in range(probe_ray_count):
		var angle := TAU * float(i) / float(probe_ray_count)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * probe_range)
		query.exclude = [self]
		query.collision_mask = probe_collision_mask
		var result := space_state.intersect_ray(query)
		if result:
			found_hit = true
			var dist: float = origin.distance_to(result["position"])
			if dist < min_distance:
				min_distance = dist

	if not found_hit:
		return normal_radius

	return clamp(min_distance - probe_safety_margin, squeeze_radius, normal_radius)

func _apply_capsule_size(radius: float, height: float) -> void:
	var shape: CapsuleShape3D = collision_shape.shape
	shape.radius = radius
	shape.height = height

func _apply_landing_squash(fall_speed: float) -> void:
	_mesh_scale_velocity += Vector3(land_squash_kick, -land_squash_kick * 1.6, land_squash_kick) * 0.05

	if slime_material:
		var strength: float = landing_impact_base + clamp(fall_speed, 0.0, 10.0) * landing_impact_speed_scale
		slime_material.set_shader_parameter("impact_amplitude", strength)
		_impact_elapsed = 0.0

func _update_shader_impact(delta: float) -> void:
	_impact_elapsed += delta
	if slime_material:
		slime_material.set_shader_parameter("impact_time", _impact_elapsed)

func _update_squash_and_stretch(delta: float) -> void:
	var radius_ratio := _current_radius / normal_radius
	var height_ratio := _current_height / normal_height

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var stretch: float = clamp(horizontal_speed / walk_speed, 0.0, 1.0) * move_stretch_amount

	var target_scale := Vector3(
		radius_ratio * (1.0 - stretch * 0.5),
		height_ratio * (1.0 + stretch),
		radius_ratio * (1.0 - stretch * 0.5)
	)

	var displacement := target_scale - _mesh_scale
	var force := displacement * stretch_spring_stiffness - _mesh_scale_velocity * stretch_spring_damping
	_mesh_scale_velocity += force * delta
	_mesh_scale += _mesh_scale_velocity * delta

	slime_mesh.scale = _mesh_scale
