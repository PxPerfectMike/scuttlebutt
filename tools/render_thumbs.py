"""Draws the thumbs up and thumbs down icons (64x64 TGA) into Scuttlebutt/Media.

Usage: python tools/render_thumbs.py
Drawn at 8x and scaled down so the edges are smooth.
"""

import os

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "Scuttlebutt", "Media")
BIG = 512
SIZE = 64
OUTLINE = 22


def shapes(grow):
	"""Rounded rectangles (box, radius) for a thumb pointing up, grown by `grow` pixels."""
	parts = [
		((236, 30, 330, 270), 47),  # thumb
		((196, 222, 452, 470), 56),  # fist
		((60, 236, 176, 482), 22),  # cuff
	]
	out = []
	for (x0, y0, x1, y1), r in parts:
		out.append(((x0 - grow, y0 - grow, x1 + grow, y1 + grow), r + grow))
	return out


def draw(fill, shade, line):
	img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	for box, r in shapes(OUTLINE):
		d.rounded_rectangle(box, r, fill=line)
	for box, r in shapes(0):
		d.rounded_rectangle(box, r, fill=fill)
	# Shading on the lower half of the fist and cuff.
	d.rounded_rectangle((196, 360, 452, 470), 56, fill=shade)
	d.rectangle((60, 380, 176, 482), fill=shade)
	# Gaps between the fingers, the thumb's crease, and the line between cuff and fist.
	for y in (286, 348, 410):
		d.line((330, y, 452, y), fill=line, width=16)
	d.line((236, 270, 330, 270), fill=line, width=16)
	d.line((186, 236, 186, 482), fill=line, width=OUTLINE)
	# A highlight down the thumb.
	d.rounded_rectangle((258, 60, 282, 200), 12, fill=(255, 255, 255, 110))
	return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
	os.makedirs(OUT, exist_ok=True)
	up = draw((70, 210, 70, 255), (40, 160, 50, 255), (10, 40, 10, 255))
	down = draw((225, 60, 55, 255), (170, 35, 35, 255), (45, 8, 8, 255)).transpose(Image.FLIP_TOP_BOTTOM)
	up.save(os.path.join(OUT, "ThumbUp.tga"))
	down.save(os.path.join(OUT, "ThumbDown.tga"))
	preview = Image.new("RGBA", (SIZE * 4 + 8, SIZE * 2 + 4), (40, 40, 40, 255))
	preview.alpha_composite(up.resize((SIZE * 2, SIZE * 2), Image.NEAREST), (0, 0))
	preview.alpha_composite(down.resize((SIZE * 2, SIZE * 2), Image.NEAREST), (SIZE * 2 + 8, 0))
	preview.save(os.path.join(os.environ.get("PREVIEW_DIR", OUT), "thumbs-preview.png"))


if __name__ == "__main__":
	main()
