@tool
extends EditorScript
## Builds a ready-to-use scene for every prop .glb: body type (static / rigid /
## none), collision shape, size and mass, so you don't set each prop up by hand.
##
## HOW TO RUN
##   Open this file in the Script editor, then File > Run  (Ctrl+Shift+X).
##   Change the settings below, run it again, and every prop scene is rebuilt.
##   Generated scenes are OVERWRITTEN on every run, so put one-off tweaks in
##   OVERRIDES instead of editing the generated scenes by hand.
##
## WHAT YOU GET
##   res://scenes/props/<name>.tscn   one scene per prop (body + visual + collision)
##   res://scenes/props_gallery.tscn  every prop in a row next to your slime, to
##                                    check sizes (open it and press F6 to play)

const GLB_DIR := "res://assets/glb_props"
const OUT_DIR := "res://scenes/props"
const GALLERY_PATH := "res://scenes/props_gallery.tscn"
const SLIME_SCENE := "res://scenes/Slime.tscn"
const MAKE_GALLERY := true
const GALLERY_GAP := 1.5

## Multiplies the size of EVERY prop. Raise it if props look too small next to
## the slime, lower it if they look too big. Re-run the tool after changing.
const GLOBAL_SCALE := 3.0

## Rigid props get mass = volume * DENSITY, kept between MIN_MASS and MAX_MASS (kg).
## Keep them lighter than the slime (Total Mass) if you want the slime to push them.
const DENSITY := 80.0
const MIN_MASS := 0.3
const MAX_MASS := 8.0

## body:  "static" (never moves) | "rigid" (can be pushed) | "none" (decoration, no collision)
## shape: "box" | "convex" | "trimesh" | "none"
##        box     = cheapest, good for crates/cabinets
##        convex  = hugs the shape, good for round things and anything "rigid"
##        trimesh = exact shape, keeps gaps open (under a table). Static only.
## Optional keys: "scale" (multiplier on top of GLOBAL_SCALE), "height" (final
## height in metres, overrides scale), "mass" (kg, rigid only).
const DEFAULTS := {"body": "static", "shape": "convex", "scale": 1.0}

## Matched against the file name (case-insensitive). The FIRST matching rule wins.
const RULES := [
	# Tiny pickups / decoration: no collision, so the slime never snags on them.
	{"words": ["syringe", "tube", "vial", "pipette"], "body": "none", "shape": "none"},
	# Small things the slime can shove around.
	{"words": ["carton", "corton", "crate", "box", "book", "jar", "bottle", "flask", "beaker", "bucket"], "body": "rigid", "shape": "convex"},
	# Furniture with gaps: exact collision so you can squeeze underneath.
	{"words": ["table", "shelf", "desk"], "body": "static", "shape": "trimesh"},
	# Big solid machines.
	{"words": ["cabinet", "console", "autoclave", "safe", "fridge", "floor", "wall"], "body": "static", "shape": "box"},
	# Round solid things.
	{"words": ["tank", "cylinder", "canister", "barrel"], "body": "static", "shape": "convex"},
]

## One-off changes for a single prop, by file name (without .glb).
const OVERRIDES := {
	# "another_corton2": {"body": "rigid", "scale": 1.5, "mass": 3.0},
	# "storage_cabinet": {"height": 6.0},
}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var files := _list_glbs(GLB_DIR)
	if files.is_empty():
		push_error("No .glb files found in %s. Check GLB_DIR at the top of this script." % GLB_DIR)
		return

	print("")
	print("%s %s %s %s %s" % ["PROP".rpad(24), "BODY".rpad(8), "SHAPE".rpad(8), "SIZE (m)".rpad(20), "MASS"])
	var built: Array[Dictionary] = []
	for file in files:
		var result := _build_prop(file)
		if not result.is_empty():
			built.append(result)

	if MAKE_GALLERY and not built.is_empty():
		_build_gallery(built)

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

	print("")
	print("Built %d prop scenes in %s" % [built.size(), OUT_DIR])
	if MAKE_GALLERY:
		print("Open %s and press F6 to check the sizes." % GALLERY_PATH)


func _list_glbs(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.get_extension().to_lower() == "glb":
			found.append(dir_path.path_join(file_name))
	found.sort()
	return found


func _settings_for(prop_name: String) -> Dictionary:
	var lowered := prop_name.to_lower()
	var cfg: Dictionary = DEFAULTS.duplicate()
	var matched := false
	for rule: Dictionary in RULES:
		for word: String in rule["words"]:
			if lowered.contains(word):
				cfg.merge(rule, true)
				matched = true
				break
		if matched:
			break
	if OVERRIDES.has(prop_name):
		cfg.merge(OVERRIDES[prop_name], true)
	return cfg


func _build_prop(glb_path: String) -> Dictionary:
	var prop_name := glb_path.get_file().get_basename()
	var cfg := _settings_for(prop_name)
	var kind: String = cfg["body"]
	var shape_kind: String = cfg["shape"]

	var packed := ResourceLoader.load(glb_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		push_warning("Skipped %s: could not load it (is it imported yet?)" % glb_path)
		return {}
	var visual := packed.instantiate() as Node3D
	if visual == null:
		push_warning("Skipped %s: the file does not have a 3D root node." % glb_path)
		return {}

	var meshes: Array[Dictionary] = []
	_collect_meshes(visual, visual, meshes)
	if meshes.is_empty():
		push_warning("Skipped %s: no meshes inside." % prop_name)
		visual.free()
		return {}
	if _has_collision_object(visual):
		push_warning("%s already contains collision from the import (name suffix like -col). Re-export it with ADD_COLLISION_SUFFIX = False to avoid doubled colliders." % prop_name)

	var bounds := _bounds_of(meshes)
	var factor := _scale_for(cfg, bounds)

	# Rigid bodies can't use trimesh (concave) shapes.
	if kind == "rigid" and shape_kind == "trimesh":
		push_warning("%s: rigid props can't use trimesh, using convex instead." % prop_name)
		shape_kind = "convex"

	var mass := 0.0
	var body: Node3D
	match kind:
		"rigid":
			var rigid := RigidBody3D.new()
			mass = _mass_for(cfg, bounds, factor)
			rigid.mass = mass
			body = rigid
		"static":
			body = StaticBody3D.new()
		_:
			body = Node3D.new()
			shape_kind = "none"
	body.name = prop_name

	# The visual is scaled; the collision is built at the final size (never scale
	# the root body itself, physics shapes don't like it).
	visual.name = "Visual"
	visual.transform = Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO)
	body.add_child(visual)
	visual.owner = body

	if shape_kind != "none":
		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		match shape_kind:
			"box":
				var box := BoxShape3D.new()
				box.size = (bounds.size * factor).max(Vector3.ONE * 0.01)
				collider.shape = box
				collider.position = bounds.get_center() * factor
			"trimesh":
				collider.shape = _trimesh_shape(meshes, factor)
			_:
				collider.shape = _convex_shape(meshes, factor)
		body.add_child(collider)
		collider.owner = body

	var out_path := OUT_DIR.path_join(prop_name + ".tscn")
	var scene := PackedScene.new()
	var err := scene.pack(body)
	if err == OK:
		err = ResourceSaver.save(scene, out_path)
	body.free()
	if err != OK:
		push_error("Could not save %s (error %d)" % [out_path, err])
		return {}

	var final_size := bounds.size * factor
	print("%s %s %s %s %s" % [
		prop_name.rpad(24), kind.rpad(8), shape_kind.rpad(8),
		("%.1f x %.1f x %.1f" % [final_size.x, final_size.y, final_size.z]).rpad(20),
		("%.1f kg" % mass) if kind == "rigid" else "-",
	])
	return {"path": out_path, "size": final_size, "name": prop_name}


func _scale_for(cfg: Dictionary, bounds: AABB) -> float:
	if cfg.has("height") and bounds.size.y > 0.0001:
		return float(cfg["height"]) / bounds.size.y
	return GLOBAL_SCALE * float(cfg["scale"])


func _mass_for(cfg: Dictionary, bounds: AABB, factor: float) -> float:
	if cfg.has("mass"):
		return float(cfg["mass"])
	var size := bounds.size * factor
	return clampf(size.x * size.y * size.z * DENSITY, MIN_MASS, MAX_MASS)


# ---------------------------------------------------------------- mesh helpers

func _collect_meshes(node: Node, root: Node3D, out: Array[Dictionary]) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		out.append({"mesh": mesh_node.mesh, "xform": _relative_transform(mesh_node, root)})
	for child in node.get_children():
		_collect_meshes(child, root, out)


## Transform of `node` relative to `root` (works even when not in the scene tree).
func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			result = spatial.transform * result
		current = current.get_parent()
	return result


func _has_collision_object(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _has_collision_object(child):
			return true
	return false


func _bounds_of(meshes: Array[Dictionary]) -> AABB:
	var bounds := AABB()
	var first := true
	for entry in meshes:
		var mesh: Mesh = entry["mesh"]
		var xform: Transform3D = entry["xform"]
		var box := xform * mesh.get_aabb()
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)
	return bounds


func _convex_shape(meshes: Array[Dictionary], factor: float) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for entry in meshes:
		var mesh: Mesh = entry["mesh"]
		var xform: Transform3D = entry["xform"]
		var hull := mesh.create_convex_shape(true, false)
		if hull == null:
			continue
		for point: Vector3 in hull.points:
			points.append(xform * point * factor)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


func _trimesh_shape(meshes: Array[Dictionary], factor: float) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	for entry in meshes:
		var mesh: Mesh = entry["mesh"]
		var xform: Transform3D = entry["xform"]
		for vertex: Vector3 in mesh.get_faces():
			faces.append(xform * vertex * factor)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


# --------------------------------------------------------------------- gallery

func _build_gallery(built: Array[Dictionary]) -> void:
	var root := Node3D.new()
	root.name = "PropsGallery"

	var total_width := 6.0
	for entry in built:
		var entry_size: Vector3 = entry["size"]
		total_width += entry_size.x + GALLERY_GAP

	# Floor (top surface at y = 0).
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = Vector3(total_width / 2.0 - 3.0, -0.5, 0.0)
	root.add_child(floor_body)
	floor_body.owner = root
	var floor_size := Vector3(total_width + 10.0, 1.0, 24.0)
	var floor_shape := CollisionShape3D.new()
	floor_shape.name = "CollisionShape3D"
	var floor_box := BoxShape3D.new()
	floor_box.size = floor_size
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_shape.owner = root
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "FloorMesh"
	var floor_box_mesh := BoxMesh.new()
	floor_box_mesh.size = floor_size
	floor_mesh.mesh = floor_box_mesh
	floor_body.add_child(floor_mesh)
	floor_mesh.owner = root

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.owner = root

	# Props in a row, each with a name label above it.
	var cursor := 4.0
	for entry in built:
		var packed := ResourceLoader.load(entry["path"], "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		var instance := packed.instantiate() as Node3D
		var entry_size: Vector3 = entry["size"]
		instance.position = Vector3(cursor + entry_size.x / 2.0, 0.05, 0.0)
		root.add_child(instance)
		instance.owner = root

		var label := Label3D.new()
		label.name = "Label_" + str(entry["name"])
		label.text = str(entry["name"])
		label.font_size = 48
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(cursor + entry_size.x / 2.0, entry_size.y + 0.6, 0.0)
		root.add_child(label)
		label.owner = root

		cursor += entry_size.x + GALLERY_GAP

	# Your slime, dropped in at the start, for a direct size comparison.
	if ResourceLoader.exists(SLIME_SCENE):
		var slime_packed := load(SLIME_SCENE) as PackedScene
		var slime := slime_packed.instantiate() as Node3D
		if slime != null:
			slime.position = Vector3(0.0, 2.0, 0.0)
			root.add_child(slime)
			slime.owner = root

	var scene := PackedScene.new()
	if scene.pack(root) == OK:
		ResourceSaver.save(scene, GALLERY_PATH)
	root.free()
