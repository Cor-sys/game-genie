class_name Backfill
extends RefCounted

## Procedural Backfill & Ring-Dilation Subsystem for Game Genie.
## Solves the "Ghost Anatomy" problem (limbs cut against covering layers).
## When a limb rotates away, this grows the occluded layer into the vacated void
## one ring at a time, inheriting neighbor colors to preserve hand-drawn shading gradients.


## Dilates non-transparent pixels of `source_img` into transparent regions that were
## covered by `occluder_mask`.
## Each new pixel inherits the color of the adjacent neighbor it grew from.
static func dilate_occluded_region(
	source_img: Image,
	occluder_mask: Image,
	rings: int = 2
) -> Image:
	var w := source_img.get_width()
	var h := source_img.get_height()
	var result := source_img.duplicate()

	var src_pixels: PackedInt32Array = result.get_data().to_int32_array()
	var mask_pixels: PackedInt32Array
	if occluder_mask and not occluder_mask.is_empty():
		mask_pixels = occluder_mask.get_data().to_int32_array()
	else:
		# If no explicit mask, allow dilation anywhere within the source bounding box
		mask_pixels = PackedInt32Array()
		mask_pixels.resize(w * h)
		mask_pixels.fill(-1)  # All allowed

	for _r in range(rings):
		var copy: PackedInt32Array = src_pixels.duplicate()
		var modified := 0

		for y in range(h):
			var row := y * w
			for x in range(w):
				var idx := row + x
				var col: int = copy[idx]
				var alpha := (col >> 24) & 0xFF

				# If pixel is empty, but allowed by the occluder mask
				if alpha == 0:
					var m_col: int = mask_pixels[idx] if idx < mask_pixels.size() else 0
					var m_alpha := (m_col >> 24) & 0xFF
					if m_alpha > 0 or mask_pixels[idx] == -1:
						# Look for an adjacent opaque neighbor to grow from
						var neighbor_col := 0
						if y > 0 and ((copy[(y - 1) * w + x] >> 24) & 0xFF) > 0:
							neighbor_col = copy[(y - 1) * w + x]
						elif y < h - 1 and ((copy[(y + 1) * w + x] >> 24) & 0xFF) > 0:
							neighbor_col = copy[(y + 1) * w + x]
						elif x > 0 and ((copy[y * w + (x - 1)] >> 24) & 0xFF) > 0:
							neighbor_col = copy[y * w + (x - 1)]
						elif x < w - 1 and ((copy[y * w + (x + 1)] >> 24) & 0xFF) > 0:
							neighbor_col = copy[y * w + (x + 1)]

						if neighbor_col != 0:
							src_pixels[idx] = neighbor_col
							modified += 1

		if modified == 0:
			break

	var out_bytes: PackedByteArray = src_pixels.to_byte_array()
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out_bytes)


## Composites an array of layered images onto a target canvas image in Z-order.
## Each item in layers: {"image": Image, "offset": Vector2i, "z_index": int}
static func composite_to_canvas(
	canvas_size: Vector2i,
	layers: Array[Dictionary],
	backfill_layer: Image = null
) -> Image:
	var final_canvas := Image.create_empty(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)

	# 1. Draw backfill layer behind everything if present
	if backfill_layer and not backfill_layer.is_empty():
		final_canvas.blend_rect(
			backfill_layer,
			Rect2i(0, 0, backfill_layer.get_width(), backfill_layer.get_height()),
			Vector2i.ZERO
		)

	# 2. Sort body parts by Z-index
	var sorted_layers := layers.duplicate()
	sorted_layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("z_index", 0) < b.get("z_index", 0)
	)

	# 3. Alpha blend each part into final composite
	for item in sorted_layers:
		var img: Image = item.get("image", null)
		var offset: Vector2i = item.get("offset", Vector2i.ZERO)
		if img and not img.is_empty():
			var rect := Rect2i(0, 0, img.get_width(), img.get_height())
			final_canvas.blend_rect(img, rect, offset)

	return final_canvas
