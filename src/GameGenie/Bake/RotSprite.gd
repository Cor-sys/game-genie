class_name RotSprite
extends RefCounted

## RotSprite implementation in GDScript.
## Rotates pixel art without blur or jagged edge degradation by:
## 1. Upscaling 8x with 3 passes of Scale2x (EPX) — edge preserving, invents no colors
## 2. Rotating the 8x image with nearest-neighbor around the scaled pivot
## 3. Downsampling 8x by mode filter (majority-vote color in each 8x8 block)
## 4. Closing pinholes (repairing single-pixel erosion on thin limbs)

const SCALE: int = 8  # 2^3 = 8x


## Rotates an Image by degrees around the given local pivot (in source pixel coordinates).
## Returns a new pixel-perfect rotated Image of the same or expanded size.
static func rotate_pixel_art(src_image: Image, degrees: float, pivot: Vector2) -> Image:
	if is_zero_approx(degrees) or is_equal_approx(fposmod(degrees, 360.0), 0.0):
		return src_image.duplicate()

	var w := src_image.get_width()
	var h := src_image.get_height()

	# Convert source Image (RGBA8) into PackedInt32Array for fast bitwise comparison
	var raw_bytes := src_image.get_data()
	var pixels_src: PackedInt32Array = raw_bytes.to_int32_array()

	# 1. Three passes of Scale2x: w*h -> 2w*2h -> 4w*4h -> 8w*8h
	var cur_w := w
	var cur_h := h
	var cur_pixels := pixels_src

	for _i in range(3):
		cur_pixels = _scale2x_pass(cur_pixels, cur_w, cur_h)
		cur_w *= 2
		cur_h *= 2

	# 2. Nearest-neighbor rotation at 8x scale around scaled pivot
	var rad := -deg_to_rad(degrees)  # negative for clockwise match
	var cos_a := cos(rad)
	var sin_a := sin(rad)
	var pivot_8x := pivot * float(SCALE)

	var rotated_8x := PackedInt32Array()
	rotated_8x.resize(cur_w * cur_h)

	for dy in range(cur_h):
		var rel_y := float(dy) - pivot_8x.y
		var row_offset := dy * cur_w
		for dx in range(cur_w):
			var rel_x := float(dx) - pivot_8x.x

			# Inverse rotation to find source pixel
			var sx := int(round(cos_a * rel_x - sin_a * rel_y + pivot_8x.x))
			var sy := int(round(sin_a * rel_x + cos_a * rel_y + pivot_8x.y))

			if sx >= 0 and sx < cur_w and sy >= 0 and sy < cur_h:
				rotated_8x[row_offset + dx] = cur_pixels[sy * cur_w + sx]
			else:
				rotated_8x[row_offset + dx] = 0  # Transparent

	# 3. Downsample 8x by majority-vote (mode filter)
	var downsampled := _mode_downsample_8x(rotated_8x, w, h)

	# 4. Close pinholes (2 passes)
	_close_pinholes(downsampled, w, h, 2)

	# Rebuild Godot Image
	var out_bytes: PackedByteArray = downsampled.to_byte_array()
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out_bytes)


## Single pass of Scale2x (EPX) on a PackedInt32Array.
## Output size is (2*w) x (2*h).
static func _scale2x_pass(src: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var out_w := w * 2
	var out_h := h * 2
	var dst := PackedInt32Array()
	dst.resize(out_w * out_h)

	for y in range(h):
		var y_up := maxi(y - 1, 0)
		var y_down := mini(y + 1, h - 1)
		var row_curr := y * w
		var row_up := y_up * w
		var row_down := y_down * w

		var dst_row0 := (y * 2) * out_w
		var dst_row1 := (y * 2 + 1) * out_w

		for x in range(w):
			var x_left := maxi(x - 1, 0)
			var x_right := mini(x + 1, w - 1)

			var p: int = src[row_curr + x]
			var a: int = src[row_up + x]
			var b: int = src[row_curr + x_right]
			var c: int = src[row_curr + x_left]
			var d: int = src[row_down + x]

			var p1 := p
			var p2 := p
			var p3 := p
			var p4 := p

			if c == a and c != d and a != b:
				p1 = a
			if a == b and a != c and b != d:
				p2 = b
			if d == c and d != b and c != a:
				p3 = c
			if b == d and b != a and d != c:
				p4 = d

			var dst_x0 := x * 2
			var dst_x1 := x * 2 + 1

			dst[dst_row0 + dst_x0] = p1
			dst[dst_row0 + dst_x1] = p2
			dst[dst_row1 + dst_x0] = p3
			dst[dst_row1 + dst_x1] = p4

	return dst


## Downsamples an 8x upscaled buffer back to w x h by taking the mode (most common color)
## in each 8x8 cell.
static func _mode_downsample_8x(src_8x: PackedInt32Array, target_w: int, target_h: int) -> PackedInt32Array:
	var stride_8x := target_w * 8
	var dst := PackedInt32Array()
	dst.resize(target_w * target_h)

	for by in range(target_h):
		var start_y := by * 8
		var dst_row := by * target_w

		for bx in range(target_w):
			var start_x := bx * 8

			# Histogram of colors in 8x8 block (64 pixels total)
			var counts: Dictionary = {}
			var max_color := 0
			var max_count := 0
			var transparent_count := 0

			for dy in range(8):
				var row_idx := (start_y + dy) * stride_8x
				for dx in range(8):
					var col: int = src_8x[row_idx + start_x + dx]
					var alpha := (col >> 24) & 0xFF
					if alpha == 0:
						transparent_count += 1
					else:
						var count: int = counts.get(col, 0) + 1
						counts[col] = count
						if count > max_count:
							max_count = count
							max_color = col

			# If more than half the block is transparent, it resolves to transparent
			if transparent_count >= 33 or max_count == 0:
				dst[dst_row + bx] = 0
			else:
				dst[dst_row + bx] = max_color

	return dst


## Fills single-pixel transparent gaps if surrounded by 3 or 4 opaque orthogonal neighbors.
static func _close_pinholes(pixels: PackedInt32Array, w: int, h: int, passes: int = 2) -> void:
	for _pass in range(passes):
		var changes := 0
		var copy := pixels.duplicate()

		for y in range(h):
			var row := y * w
			for x in range(w):
				var idx := row + x
				var col: int = copy[idx]
				var alpha := (col >> 24) & 0xFF

				# Only test transparent pixels
				if alpha == 0:
					var neighbors: Array[int] = []
					if y > 0:
						var c: int = copy[(y - 1) * w + x]
						if ((c >> 24) & 0xFF) > 0:
							neighbors.append(c)
					if y < h - 1:
						var c: int = copy[(y + 1) * w + x]
						if ((c >> 24) & 0xFF) > 0:
							neighbors.append(c)
					if x > 0:
						var c: int = copy[y * w + (x - 1)]
						if ((c >> 24) & 0xFF) > 0:
							neighbors.append(c)
					if x < w - 1:
						var c: int = copy[y * w + (x + 1)]
						if ((c >> 24) & 0xFF) > 0:
							neighbors.append(c)

					if neighbors.size() >= 3:
						# Take majority color among neighbors
						var counts := {}
						var best_col := neighbors[0]
						var best_count := 0
						for nc in neighbors:
							var cnt: int = counts.get(nc, 0) + 1
							counts[nc] = cnt
							if cnt > best_count:
								best_count = cnt
								best_col = nc
						pixels[idx] = best_col
						changes += 1

		if changes == 0:
			break
