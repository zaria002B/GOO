extends RigidBody3D
## Invisible physics "driver" for the slime.
## This is the thing that actually moves and collides with the world.
## The visible SoftBody3D mesh (SlimeBody) stays pinned to it so the
## slime follows this body around while still squashing and jiggling.

@export var move_speed: float = 4.0
@export var acceleration: float = 14.0
@export var jump_impulse: float = 5.0
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = deg_to_rad(-70.0)
@export var max_pitch: float = deg_to_rad(60.0)

@onready var camera_pivot: Node3D = $CameraPivot
@onready var ground_ray: RayCast3D = $GroundRay

var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_grounded: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Lock rotation so the driver stays upright - it's an invisible
	# "core" for the slime, not something that should tumble.
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, min_pitch, max_pitch)
		rotation.y = _yaw
		camera_pivot.rotation.x = _pitch

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	_is_grounded = ground_ray.is_colliding()

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)

	var yaw_basis := Basis(Vector3.UP, _yaw)
	var wish_dir := yaw_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if wish_dir.length_squared() > 0.0:
		wish_dir = wish_dir.normalized()

	var target_velocity := wish_dir * move_speed
	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	horizontal = horizontal.move_toward(target_velocity, acceleration * delta)

	linear_velocity.x = horizontal.x
	linear_velocity.z = horizontal.z

	if Input.is_action_just_pressed("jump") and _is_grounded:
		linear_velocity.y = jump_impulse
