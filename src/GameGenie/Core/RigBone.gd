class_name RigBone
extends Node2D

## Represents a single body part/bone in the Game Genie 2D skeletal rig.
## Uses Node2D's native scene tree for automatic forward kinematics,
## local-to-global transform propagation, and pivot rotation.

signal bone_changed

@export var bone_name: String = ""
@export var sprite_path: String = ""
@export var pivot_offset: Vector2 = Vector2.ZERO:
	set(value):
		pivot_offset = value
		bone_changed.emit()

@export var custom_z_index: int = 0:
	set(value):
		custom_z_index = value
		z_index = value
		bone_changed.emit()

## Sockets on this bone where child parts can snap.
## Key: Socket name (e.g. "hand", "weapon", "elbow")
## Value: Vector2 local position relative to this bone's origin.
var sockets: Dictionary = {}

## The raster pixel image of this part.
var sprite_image: Image = null

## Cached texture for fast viewport rendering.
var sprite_texture: ImageTexture = null


func _init(p_name: String = "") -> void:
	bone_name = p_name
	name = p_name


## Sets the sprite image and generates a texture for canvas display.
func set_sprite(img: Image, path: String = "") -> void:
	sprite_image = img
	sprite_path = path
	if sprite_image and not sprite_image.is_empty():
		sprite_texture = ImageTexture.create_from_image(sprite_image)
	else:
		sprite_texture = null
	bone_changed.emit()


## Loads the sprite from a PNG file path.
func load_sprite_from_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		push_error("GameGenie: Sprite file not found: %s" % path)
		return ERR_FILE_NOT_FOUND
	var img := Image.new()
	var err := img.load(path)
	if err == OK:
		set_sprite(img, path)
	return err


## Registers an attachment socket.
func set_socket(socket_name: String, local_pos: Vector2) -> void:
	sockets[socket_name] = local_pos
	bone_changed.emit()


## Gets the global canvas position of a named socket.
func get_socket_global_position(socket_name: String) -> Vector2:
	if socket_name in sockets:
		return to_global(sockets[socket_name])
	return global_position


## Returns the top-left canvas origin of the sprite image when drawn with pivot offset.
func get_sprite_draw_origin() -> Vector2:
	return -pivot_offset


## Serializes this bone to a dictionary for JSON recipes.
func to_dict() -> Dictionary:
	var sock_dict := {}
	for s_name in sockets:
		var p: Vector2 = sockets[s_name]
		sock_dict[s_name] = [p.x, p.y]

	return {
		"name": bone_name,
		"parent": get_parent().name if get_parent() is RigBone else "",
		"sprite_path": sprite_path,
		"pivot": [pivot_offset.x, pivot_offset.y],
		"rotation": rotation_degrees,
		"position": [position.x, position.y],
		"z_index": custom_z_index,
		"sockets": sock_dict
	}


## Deserializes this bone from a dictionary.
func from_dict(data: Dictionary) -> void:
	bone_name = data.get("name", name)
	name = bone_name
	sprite_path = data.get("sprite_path", "")
	var piv = data.get("pivot", [0, 0])
	pivot_offset = Vector2(piv[0], piv[1])
	rotation_degrees = data.get("rotation", 0.0)
	var pos = data.get("position", [0, 0])
	position = Vector2(pos[0], pos[1])
	custom_z_index = data.get("z_index", 0)

	sockets.clear()
	var raw_sockets = data.get("sockets", {})
	for s_name in raw_sockets:
		var sp = raw_sockets[s_name]
		sockets[s_name] = Vector2(sp[0], sp[1])

	if sprite_path != "" and FileAccess.file_exists(sprite_path):
		load_sprite_from_file(sprite_path)
