class_name SnapshotBaker
extends RefCounted

## Snapshot Baker for Game Genie.
## Traverses the RigModel hierarchy, applies RotSprite to rotated limbs around
## their joint pivots, handles backfill dilation, and composites the result into
## an editable, pixel-perfect RGBA8 Image for insertion into Pixelorama.

signal snapshot_completed(baked_image: Image)


## Synchronously bakes the current pose of the RigModel into an RGBA8 Image.
static func bake(rig: RigModel, backfill_img: Image = null) -> Image:
	var canvas_size := rig.canvas_size
	var layers: Array[Dictionary] = []

	var sorted_bones := rig.get_bones_sorted_by_depth()

	for bone in sorted_bones:
		if bone.sprite_image == null or bone.sprite_image.is_empty():
			continue

		var global_pos := bone.global_position
		var global_rot := bone.global_rotation_degrees
		var pivot := bone.pivot_offset

		var part_image: Image
		var draw_offset: Vector2i

		if is_zero_approx(global_rot) or is_equal_approx(fposmod(global_rot, 360.0), 0.0):
			part_image = bone.sprite_image.duplicate()
			draw_offset = Vector2i(round(global_pos.x - pivot.x), round(global_pos.y - pivot.y))
		else:
			# Apply RotSprite to achieve pixel-perfect rotation without staircasing
			part_image = RotSprite.rotate_pixel_art(bone.sprite_image, global_rot, pivot)
			draw_offset = Vector2i(round(global_pos.x - pivot.x), round(global_pos.y - pivot.y))

		layers.append({
			"image": part_image,
			"offset": draw_offset,
			"z_index": bone.custom_z_index
		})

	# Composite layers with Backfill underdrawing
	return Backfill.composite_to_canvas(canvas_size, layers, backfill_img)


## Asynchronously bakes the pose via WorkerThreadPool so the UI never hitches.
func bake_async(rig: RigModel, backfill_img: Image = null) -> void:
	var task_id := WorkerThreadPool.add_task(func():
		var result := SnapshotBaker.bake(rig, backfill_img)
		_on_bake_finished.call_deferred(result)
	)


func _on_bake_finished(result: Image) -> void:
	snapshot_completed.emit(result)
