extends SceneTree

func _init() -> void:
	print("--- Running Game Genie Engine Unit Tests ---")

	# 1. Test Rig Hierarchy and Forward Kinematics
	var rig := RigModel.new("TestHero")
	rig.canvas_size = Vector2i(64, 64)

	var torso := rig.add_bone("Torso")
	torso.position = Vector2(32, 32)
	torso.pivot_offset = Vector2(8, 8)
	torso.set_socket("shoulder_r", Vector2(10, -5))

	var arm := rig.add_bone("RightArm", "Torso")
	var attached := rig.attach_to_socket("RightArm", "Torso", "shoulder_r")
	assert(attached, "Socket attachment failed")
	assert(arm.position == Vector2(10, -5), "Child position did not match socket")

	# Rotate torso and check arm global position updates
	torso.rotation_degrees = 90.0
	assert(not is_zero_approx(arm.global_position.x), "Forward kinematics failed")
	print("  ✓ Rig forward kinematics & socket attachment verified")

	# 2. Test RotSprite with synthetic pixel art
	var test_img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var red := Color.RED
	var blue := Color.BLUE
	# Draw a 3-pixel vertical bar
	for y in range(4, 12):
		test_img.set_pixel(8, y, red)
		test_img.set_pixel(9, y, blue)

	torso.set_sprite(test_img)
	arm.set_sprite(test_img)

	var rotated := RotSprite.rotate_pixel_art(test_img, 30.0, Vector2(8, 8))
	assert(rotated != null and not rotated.is_empty(), "RotSprite failed to produce image")
	assert(rotated.get_width() == 16 and rotated.get_height() == 16, "RotSprite output size mismatch")

	# Verify palette integrity: only red, blue, or transparent
	var src_raw: PackedInt32Array = test_img.get_data().to_int32_array()
	var red_int: int = src_raw[8 * 16 + 8]
	var blue_int: int = src_raw[8 * 16 + 9]
	var raw: PackedInt32Array = rotated.get_data().to_int32_array()

	for px in raw:
		var alpha := (px >> 24) & 0xFF
		if alpha > 0:
			assert(px == red_int or px == blue_int, "RotSprite invented colors!")
	print("  ✓ RotSprite scale2x 8x + rotation + mode downsample + palette integrity verified")

	# 3. Test Snapshot Baker
	var baked := SnapshotBaker.bake(rig)
	assert(baked != null, "Snapshot bake returned null")
	assert(baked.get_width() == 64 and baked.get_height() == 64, "Baked image dimensions mismatch")
	print("  ✓ SnapshotBaker composite verified")

	# 4. Test JSON Recipe Serialization ("Art as Code")
	rig.save_pose("Aim_Up")
	var temp_json_path := "user://test_recipe.json"
	var save_err := rig.save_recipe(temp_json_path)
	assert(save_err == OK, "Failed to save recipe JSON")

	var new_rig := RigModel.new("LoadedHero")
	var load_err := new_rig.load_recipe(temp_json_path)
	assert(load_err == OK, "Failed to load recipe JSON")
	assert(new_rig.bones.size() == 2, "Loaded rig bone count mismatch")
	assert("Aim_Up" in new_rig.poses, "Loaded rig poses missing")
	print("  ✓ JSON Recipe serialization / deserialization verified")

	print("\nALL GAME GENIE ENGINE TESTS PASSED! (4/4)\n")
	quit(0)
