"""Renders branding/logo.png (400x400): two overlapping speech bubbles, gossip passing along.

Usage: python tools/render_logo.py
Drawn at 4x and scaled down for smooth edges.
"""

import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 400
S = 4  # supersampling
W = SIZE * S
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "branding", "logo.png")

NAVY = (22, 30, 52)
TEAL = (34, 86, 104)
GOLD = (236, 178, 64)
GOLD_DARK = (170, 112, 30)
PARCHMENT = (246, 234, 206)
INK = (58, 42, 30)
GREEN = (84, 200, 96)
RED = (222, 74, 64)


def radial_background():
	img = Image.new("RGB", (W, W), NAVY)
	draw = ImageDraw.Draw(img)
	steps = 120
	for i in range(steps):
		t = i / steps
		r = int(W * 0.75 * (1 - t))
		color = tuple(int(NAVY[k] + (TEAL[k] - NAVY[k]) * t) for k in range(3))
		c = W // 2
		draw.ellipse((c - r, c - r - W // 10, c + r, c + r - W // 10), fill=color)
	return img


def bubble(draw, box, tail, fill, outline):
	x0, y0, x1, y1 = box
	draw.rounded_rectangle(box, radius=(y1 - y0) // 2, fill=fill, outline=outline, width=6 * S)
	draw.polygon(tail, fill=fill)
	# Re-stroke the tail's outer edges.
	draw.line([tail[1], tail[2]], fill=outline, width=6 * S)
	draw.line([tail[2], tail[0]], fill=outline, width=6 * S)


def main():
	img = radial_background()
	shadow = Image.new("L", (W, W), 0)
	sd = ImageDraw.Draw(shadow)
	sd.rounded_rectangle((60 * S, 70 * S, 300 * S, 210 * S), radius=70 * S, fill=150)
	sd.rounded_rectangle((120 * S, 175 * S, 360 * S, 315 * S), radius=70 * S, fill=150)
	shadow = shadow.filter(ImageFilter.GaussianBlur(14 * S))
	img.paste((0, 0, 0), (6 * S, 10 * S), shadow)

	draw = ImageDraw.Draw(img)
	# Back bubble (gold), tail pointing down-left.
	bubble(draw, (52 * S, 62 * S, 292 * S, 202 * S),
		[(96 * S, 186 * S), (150 * S, 196 * S), (70 * S, 248 * S)], GOLD, GOLD_DARK)
	for i, x in enumerate((122, 172, 222)):
		draw.ellipse(((x - 15) * S, 117 * S, (x + 15) * S, 147 * S), fill=GOLD_DARK)
	# Front bubble (parchment), tail pointing down-right.
	bubble(draw, (112 * S, 168 * S, 352 * S, 308 * S),
		[(268 * S, 300 * S), (318 * S, 286 * S), (338 * S, 352 * S)], PARCHMENT, INK)
	# A thumbs score: green up-triangle and red down-triangle with bars.
	cx, cy = 232 * S, 238 * S
	draw.polygon([(cx - 76 * S, cy + 14 * S), (cx - 46 * S, cy - 30 * S), (cx - 16 * S, cy + 14 * S)], fill=GREEN)
	draw.polygon([(cx + 16 * S, cy - 14 * S), (cx + 76 * S, cy - 14 * S), (cx + 46 * S, cy + 30 * S)], fill=RED)
	draw.line([(cx, cy - 34 * S), (cx, cy + 34 * S)], fill=INK, width=6 * S)

	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
	print("wrote", OUT)


if __name__ == "__main__":
	main()
