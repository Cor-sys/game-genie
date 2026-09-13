class_name RigCanvasOverlay
extends Node2D

## Interactive canvas overlay for Game Genie.
## Draws bone segments, pivot points, and socket markers directly onto Pixelorama's canvas.
## Handles mouse dragging to rotate and position bones in real time.

var rig: RigModel = null:
	set(value):
		if rig != value:
			if rig:
				rig.rig_modified.disconnect(queue_redraw)
			rig = value
			if rig:
				rig.rig_modified.connect(queue_redraw)
			queue_redraw()

var selected_bone: RigBone = null:
	set(value):
		selected_bone = value
		queue_redraw()

var is_dragging := false
var drag_start_angle := 0.0
var drag_bone_start_rot := 0.0

const COLOR_BONE := Color(0.2, 0.8, 0.4, 0.8)
const COLOR_BONE_SELECTED := Color(1.0, 0.85, 0.2, 1.0)
const COLOR_PIVOT := Color(1.0, 0.3, 0.3, 0.9)
const COLOR_SOCKET := Color(0.3, 0.6, 1.0, 0.9)


func _draw() -> void:
	if rig == null or not visible:
		return

	# Draw each bone in the hierarchy
	for b_name in rig.bones:
		var bone: RigBone = rig.bones[b_name]
		_draw_bone(bone)


func _draw_bone(bone: RigBone) -> void:
	var pivot_pos := bone.global_position
	var is_sel := (bone == selected_bone)
	var bone_col := COLOR_BONE_SELECTED if is_sel else COLOR_BONE

	# Draw connection line to parent bone if parent exists
	var parent = bone.get_parent()
	if parent is RigBone:
		var parent_pos: Vector2 = parent.global_position
		draw_line(parent_pos, pivot_pos, bone_col, 2.0 if is_sel else 1.2, true)

	# Draw pivot marker (circle)
	draw_circle(pivot_pos, 3.0 if is_sel else 2.0, COLOR_PIVOT)
	if is_sel:
		draw_arc(pivot_pos, 5.0, 0, TAU, 16, COLOR_BONE_SELECTED, 1.0)

	# Draw socket markers
	for sock_name in bone.sockets:
		var sock_pos := bone.get_socket_global_position(sock_name)
		# Draw small diamond for socket
		var d := 2.5
		var points := PackedVector2Array([
			sock_pos + Vector2(0, -d),
			sock_pos + Vector2(d, 0),
			sock_pos + Vector2(0, d),
			sock_pos + Vector2(-d, 0)
		])
		draw_colored_polygon(points, COLOR_SOCKET)


func _input(event: InputEvent) -> void:
	if not visible or rig == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos := get_local_mouse_position()
			# Check if clicked near a bone pivot
			var clicked_bone: RigBone = null
			var closest_dist := 12.0

			for b_name in rig.bones:
				var b: RigBone = rig.bones[b_name]
				var dist := mouse_pos.distance_to(b.global_position)
				if dist < closest_dist:
					closest_dist = dist
					clicked_bone = b

			if clicked_bone:
				selected_bone = clicked_bone
				is_dragging = true
				var dir := mouse_pos - selected_bone.global_position
				drag_start_angle = dir.angle()
				drag_bone_start_rot = selected_bone.rotation
				get_viewport().set_input_as_handled()
		else:
			if is_dragging:
				is_dragging = false
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and is_dragging and selected_bone:
		var mouse_pos := get_local_mouse_position()
		var dir := mouse_pos - selected_bone.global_position
		var current_angle := dir.angle()
		var delta_angle := current_angle - drag_start_angle
		selected_bone.rotation = drag_bone_start_rot + delta_angle
		rig.rig_modified.emit()
		queue_redraw()
		get_viewport().set_input_as_handled()
