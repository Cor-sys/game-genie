class_name RigModel
extends Node2D

## Root skeletal character rig model for Game Genie.
## Manages the bone tree, sockets, forward kinematics propagation,
## pose library, and JSON recipe serialization ("Art as Code").

signal rig_modified
signal pose_applied(pose_name: String)

@export var character_name: String = "unnamed_character"
@export var canvas_size: Vector2i = Vector2i(96, 84)

## Lookup table of all bones in the rig by name.
var bones: Dictionary = {}  # String -> RigBone
var root_bone: RigBone = null

## Named pose presets (e.g. {"Aim_Up": {"RightArm": {"angle": 30.0, "z_index": 1}}})
var poses: Dictionary = {}

## The currently active pose name.
var current_pose_name: String = "Default"


func _init(p_name: String = "unnamed_character") -> void:
	character_name = p_name
	name = p_name


## Adds a bone into the rig hierarchy.
## If parent_bone_name is empty, this bone becomes the root (or child of root).
func add_bone(bone_name: String, parent_bone_name: String = "") -> RigBone:
	if bone_name in bones:
		return bones[bone_name]

	var bone := RigBone.new(bone_name)
	bones[bone_name] = bone
	bone.bone_changed.connect(_on_bone_changed)

	if parent_bone_name != "" and parent_bone_name in bones:
		var parent: RigBone = bones[parent_bone_name]
		parent.add_child(bone)
	else:
		if root_bone == null:
			root_bone = bone
		add_child(bone)

	rig_modified.emit()
	return bone


## Attaches a child bone to a named socket on a parent bone.
func attach_to_socket(child_bone_name: String, parent_bone_name: String, socket_name: String) -> bool:
	if not child_bone_name in bones or not parent_bone_name in bones:
		push_error("GameGenie: Invalid bone names for socket attach")
		return false

	var child: RigBone = bones[child_bone_name]
	var parent: RigBone = bones[parent_bone_name]

	if not socket_name in parent.sockets:
		push_error("GameGenie: Parent %s has no socket named %s" % [parent_bone_name, socket_name])
		return false

	# Reparent if needed
	if child.get_parent() != parent:
		if child.get_parent():
			child.get_parent().remove_child(child)
		parent.add_child(child)

	# Snap child position to socket position
	child.position = parent.sockets[socket_name]
	rig_modified.emit()
	return true


func get_bone(bone_name: String) -> RigBone:
	return bones.get(bone_name, null)


## Returns all bones sorted by effective Z-index for rendering order.
func get_bones_sorted_by_depth() -> Array[RigBone]:
	var list: Array[RigBone] = []
	for b_name in bones:
		var bone: RigBone = bones[b_name]
		if bone.sprite_image != null:
			list.append(bone)

	list.sort_custom(func(a: RigBone, b: RigBone) -> bool:
		return a.custom_z_index < b.custom_z_index
	)
	return list


## Sets rotation angle for a bone.
func set_bone_angle(bone_name: String, degrees: float) -> void:
	if bone_name in bones:
		bones[bone_name].rotation_degrees = degrees
		rig_modified.emit()


## Captures the current transform state of all bones as a pose dictionary.
func capture_pose() -> Dictionary:
	var pose := {}
	for b_name in bones:
		var b: RigBone = bones[b_name]
		pose[b_name] = {
			"angle": b.rotation_degrees,
			"position": [b.position.x, b.position.y],
			"z_index": b.custom_z_index
		}
	return pose


## Saves the current state as a named pose.
func save_pose(pose_name: String) -> void:
	poses[pose_name] = capture_pose()
	current_pose_name = pose_name
	rig_modified.emit()


## Applies a named pose or raw pose dictionary to the rig.
func apply_pose(pose_data) -> void:
	var pose_dict: Dictionary = {}
	if pose_data is String:
		if not pose_data in poses:
			push_error("GameGenie: Pose not found: %s" % pose_data)
			return
		current_pose_name = pose_data
		pose_dict = poses[pose_data]
	elif pose_data is Dictionary:
		pose_dict = pose_data

	for b_name in pose_dict:
		if b_name in bones:
			var b: RigBone = bones[b_name]
			var entry = pose_dict[b_name]
			if "angle" in entry:
				b.rotation_degrees = float(entry["angle"])
			if "position" in entry:
				var p = entry["position"]
				b.position = Vector2(p[0], p[1])
			if "z_index" in entry:
				b.custom_z_index = int(entry["z_index"])

	pose_applied.emit(current_pose_name)
	rig_modified.emit()


## Exports character rig and all poses to a JSON recipe file.
func save_recipe(file_path: String) -> Error:
	var parts_data := {}
	for b_name in bones:
		var bone: RigBone = bones[b_name]
		parts_data[b_name] = bone.to_dict()

	var recipe := {
		"character": character_name,
		"canvas_size": [canvas_size.x, canvas_size.y],
		"root": root_bone.bone_name if root_bone else "",
		"parts": parts_data,
		"poses": poses
	}

	var json_str := JSON.stringify(recipe, "  ")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(json_str)
	file.close()
	return OK


## Loads a character rig and poses from a JSON recipe file.
func load_recipe(file_path: String) -> Error:
	if not FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		push_error("GameGenie: JSON parse error in %s: %s" % [file_path, json.get_error_message()])
		return err

	var data = json.get_data()
	if not data is Dictionary:
		return ERR_INVALID_DATA

	character_name = data.get("character", "unnamed_character")
	var cs = data.get("canvas_size", [96, 84])
	canvas_size = Vector2i(cs[0], cs[1])

	# Clear existing bones
	for child in get_children():
		child.queue_free()
	bones.clear()
	root_bone = null

	# First pass: create all bone instances
	var parts_data = data.get("parts", {})
	for b_name in parts_data:
		var b := RigBone.new(b_name)
		bones[b_name] = b
		b.bone_changed.connect(_on_bone_changed)

	# Second pass: wire hierarchy and load properties
	for b_name in parts_data:
		var b_dict = parts_data[b_name]
		var bone: RigBone = bones[b_name]
		bone.from_dict(b_dict)

		var parent_name = b_dict.get("parent", "")
		if parent_name != "" and parent_name in bones:
			bones[parent_name].add_child(bone)
		else:
			add_child(bone)

	var root_name = data.get("root", "")
	if root_name in bones:
		root_bone = bones[root_name]
	elif not bones.is_empty():
		root_bone = bones.values()[0]

	poses = data.get("poses", {})
	rig_modified.emit()
	return OK


func _on_bone_changed() -> void:
	rig_modified.emit()
