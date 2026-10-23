@tool
extends EditorScript
## Keeps the LAYOUT of the open level in step with the size of your props.
## You never type a number: it compares the scale the props were built at (recorded
## by build_props.gd) with the scale this level was last arranged for (recorded in
## the level itself), and moves the items by the difference.
##
## WHEN TO RUN IT
##   After you change SLIME_WIDTH in build_props.gd and run that, open each level and
##   run this. Running it again on a level that already matches does nothing, so it
##   is always safe to run.
##
## HOW TO RUN
##   1. Back up the level first (FileSystem panel > right-click it > Duplicate).
##   2. Open the level scene so it is the active tab.
##   3. Open this file in the Script editor, File > Run (Ctrl+Shift+X).
##   4. Read the Output panel. Looks right? Save the level (Ctrl+S).
##      Wrong? Scene > Reload Saved Scene undoes it.
##
## FIRST RUN ON A LEVEL
##   A level this script has never seen is ASSUMED to already match the props, so the
##   first run only records the current scale and moves nothing.
##
## NOTES
##   - Only instanced scenes are touched (your props and the slime). Lights, cameras
##     and plain nodes are left alone. The slime is moved but never resized.
##   - Props using a fixed "height" in build_props.gd OVERRIDES don't change size when
##     the world scale changes, so check those by eye.

## Only if this level is NOT in step with the props right now and you know the scale it
## was arranged for. 0 = assume it is in step.
const START_SCALE := 0.0

## Nudge by eye. 0 = automatic. 0.5 moves everything half as far from the origin
## (closer together); 2 moves it twice as far (more spread out).
const MANUAL_FACTOR := 0.0

## Scenes built by build_props.gd (their size is already updated by that tool).
const PROPS_DIR := "res://scenes/props/"
const PROPS_SCALE_FILE := "res://scenes/props/_scale.cfg"
const META_KEY := "layout_scale"

## Also resize items that did NOT come from build_props.gd (raw .glb files or your own
## scenes). Leave false unless those items are still at the old size.
const ALSO_RESIZE_OTHER_ITEMS := false


func _run() -> void:
	var level := get_scene()
	if level == null:
		push_error("Open a level scene first (make it the active tab), then run this script again.")
		return

	var props_scale := _props_scale()
	if props_scale <= 0.0:
		push_error("No prop scale recorded. Run build_props.gd first (it creates %s)." % PROPS_SCALE_FILE)
		return

	var layout_scale := float(level.get_meta(META_KEY, 0.0))
	var source := "recorded in this level"
	if layout_scale <= 0.0:
		if START_SCALE > 0.0:
			layout_scale = START_SCALE
			source = "START_SCALE"
		else:
			layout_scale = props_scale
			source = "first run on this level, assumed to match"

	var factor := props_scale / layout_scale
	if MANUAL_FACTOR > 0.0:
		factor = MANUAL_FACTOR
		source += ", factor set by MANUAL_FACTOR"

	print("")
	print("Level '%s': arranged for x%.2f (%s), props are x%.2f  ->  moving items by x%.3f" % [level.name, layout_scale, source, props_scale, factor])

	if is_equal_approx(factor, 1.0):
		print("Layout already matches the props. Nothing moved.")
	else:
		var counts := {"moved": 0, "left": 0}
		_rescale_children(level, counts, factor)
		print("Moved %d items, left %d alone." % [counts["moved"], counts["left"]])

	level.set_meta(META_KEY, props_scale)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	print("Look at the level, then save it (Ctrl+S). To undo: Scene > Reload Saved Scene.")


func _props_scale() -> float:
	var memory := ConfigFile.new()
	if memory.load(PROPS_SCALE_FILE) != OK:
		return 0.0
	return float(memory.get_value("props", "scale", 0.0))


func _rescale_children(parent: Node, counts: Dictionary, factor: float) -> void:
	for child in parent.get_children():
		var item := child as Node3D
		if item == null:
			continue
		if item.scene_file_path != "":
			item.position *= factor
			var note := "moved"
			var from_tool := item.scene_file_path.begins_with(PROPS_DIR)
			if ALSO_RESIZE_OTHER_ITEMS and not from_tool and not item is SoftBody3D:
				item.scale *= factor
				note = "moved + resized"
			counts["moved"] += 1
			print("  %s %s" % [note.rpad(16), item.name])
		elif item.get_child_count() > 0 and item.get_class() == "Node3D":
			_rescale_children(item, counts, factor)  # a plain group node: go inside it
		else:
			counts["left"] += 1
			print("  left alone       %s (not an instanced scene)" % item.name)
