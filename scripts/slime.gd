extends SoftBody3D
@onready var spring_arm_3d: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $Camera3D
@export var camera_follow_speed := 5.0
@export var speed := 100.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	control()
func control() -> void:
		var input_dir := Input.get_vector("move_left","move_right","move_forward","move_back")
		var direction := (Vector3(input_dir.x,0,input_dir.y)).normalized()
		direction = direction.rotated(Vector3.FORWARD,camera_3d.global_rotation.y)
		if direction:
			apply_central_force(direction*speed)
	
