class_name RigPanel
extends VBoxContainer

## Main Game Genie Rig & Animation Studio Panel for Pixelorama.
## Manages character rigs, bones, attachment sockets, poses, and the Snapshot-to-timeline loop.

signal bone_selected(bone: RigBone)

const RigCanvasOverlayScript = preload("res://src/GameGenie/UI/RigCanvasOverlay.gd")

var rig: RigModel = null
var active_bone: RigBone = null
var overlay: Node2D = null

@onready var character_name_edit: LineEdit = %CharacterNameEdit
@onready var bone_tree: Tree = %BoneTree
@onready var bone_inspector: VBoxContainer = %BoneInspector
@onready var bone_name_label: Label = %BoneNameLabel
@onready var angle_slider: HSlider = %AngleSlider
@onready var angle_spinbox: SpinBox = %AngleSpinBox
@onready var pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var pivot_x_spinbox: SpinBox = %PivotXSpinBox
@onready var pivot_y_spinbox: SpinBox = %PivotYSpinBox
@onready var z_index_spinbox: SpinBox = %ZIndexSpinBox
@onready var sprite_path_label: Label = %SpritePathLabel
@onready var pose_option_btn: OptionButton = %PoseOptionButton
@onready var non_destructive_check: CheckBox = %NonDestructiveCheckBox
@onready var snap_button: Button = %SnapButton
@onready var file_dialog: FileDialog = %FileDialog

enum DialogMode { LOAD_RECIPE, SAVE_RECIPE, LOAD_SPRITE }
var current_dialog_mode: DialogMode = DialogMode.LOAD_RECIPE


func _ready() -> void:
	if rig == null:
		rig = RigModel.new("Hero")
		add_child(rig)
		_setup_default_dwarf_rig()

	_connect_ui_signals()
	_refresh_all()

	# Attach canvas overlay if Pixelorama canvas is ready
	call_deferred("_setup_canvas_overlay")


func _setup_canvas_overlay() -> void:
	if has_node("/root/Global") and Global.canvas:
		if overlay == null:
			overlay = RigCanvasOverlayScript.new()
			overlay.name = "GameGenieRigOverlay"
			Global.canvas.add_child(overlay)
		overlay.set("rig", rig)


func _connect_ui_signals() -> void:
	bone_tree.item_selected.connect(_on_tree_item_selected)
	angle_slider.value_changed.connect(_on_angle_changed)
	angle_spinbox.value_changed.connect(_on_angle_changed)
	pos_x_spinbox.value_changed.connect(_on_pos_changed)
	pos_y_spinbox.value_changed.connect(_on_pos_changed)
	pivot_x_spinbox.value_changed.connect(_on_pivot_changed)
	pivot_y_spinbox.value_changed.connect(_on_pivot_changed)
	z_index_spinbox.value_changed.connect(_on_z_index_changed)
	snap_button.pressed.connect(_on_snap_button_pressed)


## Populates a default modular rig (Torso, Arm, Weapon) to be immediately testable.
func _setup_default_dwarf_rig() -> void:
	rig.canvas_size = Vector2i(96, 84)

	var torso := rig.add_bone("Torso")
	torso.position = Vector2(48, 50)
	torso.pivot_offset = Vector2(16, 20)
	torso.set_socket("shoulder_r", Vector2(8, -8))

	var arm := rig.add_bone("RightArm", "Torso")
	rig.attach_to_socket("RightArm", "Torso", "shoulder_r")
	arm.pivot_offset = Vector2(4, 4)
	arm.set_socket("hand", Vector2(12, 0))

	var weapon := rig.add_bone("Weapon", "RightArm")
	rig.attach_to_socket("Weapon", "RightArm", "hand")
	weapon.pivot_offset = Vector2(4, 6)

	rig.save_pose("Level")
	arm.rotation_degrees = 30.0
	rig.save_pose("Aim_Up")
	arm.rotation_degrees = -30.0
	rig.save_pose("Aim_Dn")
	arm.rotation_degrees = 0.0


func _refresh_all() -> void:
	if rig == null:
		return
	character_name_edit.text = rig.character_name
	_rebuild_bone_tree()
	_rebuild_pose_options()


func _rebuild_bone_tree() -> void:
	bone_tree.clear()
	var root_item := bone_tree.create_item()
	root_item.set_text(0, "Rig: " + rig.character_name)

	var item_map := {}
	for b_name in rig.bones:
		var bone: RigBone = rig.bones[b_name]
		var parent = bone.get_parent()
		var parent_item = item_map.get(parent.name, root_item) if parent is RigBone else root_item
		var item := bone_tree.create_item(parent_item)
		item.set_text(0, b_name)
		item.set_metadata(0, bone)
		item_map[b_name] = item


func _rebuild_pose_options() -> void:
	pose_option_btn.clear()
	for p_name in rig.poses:
		pose_option_btn.add_item(p_name)


func _on_tree_item_selected() -> void:
	var selected_item := bone_tree.get_selected()
	if selected_item == null:
		return
	var bone = selected_item.get_metadata(0)
	if bone is RigBone:
		active_bone = bone
		if overlay:
			overlay.selected_bone = bone
		_update_inspector()
		bone_selected.emit(bone)


func _update_inspector() -> void:
	if active_bone == null:
		bone_inspector.visible = false
		return

	bone_inspector.visible = true
	bone_name_label.text = "Bone: " + active_bone.bone_name
	angle_slider.set_value_no_signal(active_bone.rotation_degrees)
	angle_spinbox.set_value_no_signal(active_bone.rotation_degrees)
	pos_x_spinbox.set_value_no_signal(active_bone.position.x)
	pos_y_spinbox.set_value_no_signal(active_bone.position.y)
	pivot_x_spinbox.set_value_no_signal(active_bone.pivot_offset.x)
	pivot_y_spinbox.set_value_no_signal(active_bone.pivot_offset.y)
	z_index_spinbox.set_value_no_signal(active_bone.custom_z_index)
	sprite_path_label.text = active_bone.sprite_path if active_bone.sprite_path != "" else "No sprite assigned"


func _on_angle_changed(val: float) -> void:
	if active_bone:
		active_bone.rotation_degrees = val
		angle_slider.set_value_no_signal(val)
		angle_spinbox.set_value_no_signal(val)
		rig.rig_modified.emit()


func _on_pos_changed(_val: float) -> void:
	if active_bone:
		active_bone.position = Vector2(pos_x_spinbox.value, pos_y_spinbox.value)
		rig.rig_modified.emit()


func _on_pivot_changed(_val: float) -> void:
	if active_bone:
		active_bone.pivot_offset = Vector2(pivot_x_spinbox.value, pivot_y_spinbox.value)
		rig.rig_modified.emit()


func _on_z_index_changed(val: float) -> void:
	if active_bone:
		active_bone.custom_z_index = int(val)
		rig.rig_modified.emit()


## --- POSE ACTIONS ---
func _on_save_pose_pressed() -> void:
	var p_name := "Pose_%d" % (rig.poses.size() + 1)
	rig.save_pose(p_name)
	_rebuild_pose_options()


func _on_apply_pose_pressed() -> void:
	if pose_option_btn.item_count > 0:
		var p_name := pose_option_btn.get_item_text(pose_option_btn.selected)
		rig.apply_pose(p_name)
		_update_inspector()


## --- THE SNAPSHOT LOOP ---
func _on_snap_button_pressed() -> void:
	if rig == null:
		return

	# 1. Bake the pose using RotSprite + Backfill pipeline
	var baked_image := SnapshotBaker.bake(rig)
	if baked_image == null or baked_image.is_empty():
		push_error("GameGenie: Snapshot bake failed")
		return

	# 2. Connect to Pixelorama's active project
	if not has_node("/root/Global") or Global.current_project == null:
		print("GameGenie: Snapshot generated outside of active project (%dx%d)" % [baked_image.get_width(), baked_image.get_height()])
		return

	var project = Global.current_project
	var target_layer: int = project.current_layer
	var target_frame: int = project.current_frame

	# If non-destructive mode is on, find or create the dedicated [Rig_Bake] layer
	if non_destructive_check.button_pressed:
		var bake_layer_idx := -1
		for i in range(project.layers.size()):
			if project.layers[i].name == "Rig_Bake":
				bake_layer_idx = i
				break

		if bake_layer_idx == -1:
			# Create a new layer above the current layer
			ExtensionsApi.project.add_new_layer(project.current_layer, "Rig_Bake")
			bake_layer_idx = project.current_layer + 1

		target_layer = bake_layer_idx

	# 3. Stamp baked pixel frame into Pixelorama's cel
	OpenSave.open_image_at_cel(baked_image, target_layer, target_frame)
	print("GameGenie: Pose snapped to Layer '%s' [Frame %d] with RotSprite quality!" % [
		project.layers[target_layer].name, target_frame + 1
	])
