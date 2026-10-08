extends SoftBody3D

@export var camera_follow_speed: float = 6.0
@export var speed: float = 100.0
@export_range(0.0, 1.0) var mouse_sensitivity: float = 0.01
@export var tilt_limit: float = deg_to_rad(75)
## How many soft-body points are averaged to find the slime's centre.
## Lower = cheaper, higher = more accurate. 64 is plenty.
@export var centre_sample_count: int = 64

@onready var spring_arm_3d: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Camera3D

var number_of_points: int = 0
var _sample_stride: int = 1


func _ready() -> void:
	# 1) The camera rig must not inherit the SoftBody3D node's transform.
	#    The node itself stays where it was placed while the points move,
	#    so we position the rig ourselves in world space.
	spring_arm_3d.top_level = true

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


func _physics_process(_delta: float) -> void:
	controls()


func _process(delta: float) -> void:
	update_camera(delta)


func update_camera(delta: float) -> void:
	if number_of_points == 0:
		return
	var target: Vector3 = get_centre_approx()
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
