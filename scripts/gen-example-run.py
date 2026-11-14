#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

os.makedirs('docs/images', exist_ok=True)
BG = (11, 13, 18)
CARD = (25, 28, 40)
BORDER = (40, 45, 60)
INK = (238, 240, 246)
MUTED = (154, 161, 181)
VIOLET = (139, 92, 246)
FUCHSIA = (224, 69, 123)
ORANGE = (255, 138, 92)
TEAL = (45, 212, 191)
GREEN = (74, 222, 128)
RED = (248, 113, 113)

try:
    title_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 38)
    h2_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    h3_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 17)
    body_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 14)
    small_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 12)
    mono_font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 12)
    mono_small = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 11)
except:
    title_font = h2_font = h3_font = body_font = small_font = mono_font = mono_small = ImageFont.load_default()

W, H = 1200, 630
img = Image.new('RGB', (W, H), BG)
draw = ImageDraw.Draw(img)

for y in range(H):
    r = int(11 + (25-11) * y / H)
    g = int(13 + (15-13) * y / H)
    b = int(18 + (30-18) * y / H)
    draw.line([(0, y), (W, y)], fill=(r, g, b))

# Header
draw.text((60, 35), "Example Run — fictional demo project", font=title_font, fill=INK)
draw.text((60, 85), "What you get when you hand it a JIRA ticket", font=h3_font, fill=MUTED)

# LEFT: JIRA Ticket
left_x = 60
left_y = 130
draw.rounded_rectangle((left_x, left_y, left_x + 280, left_y + 90), radius=16, fill=CARD, outline=VIOLET, width=2)
draw.text((left_x + 20, left_y + 12), "JIRA Ticket", font=h3_font, fill=INK)
draw.text((left_x + 20, left_y + 42), "SHOP-1234", font=mono_font, fill=VIOLET)
draw.text((left_x + 20, left_y + 65), "Checkout button not working", font=small_font, fill=MUTED)

# CENTER: Evidence files
center_x = 380
center_y = 130
draw.rounded_rectangle((center_x, center_y, center_x + 400, center_y + 240), radius=16, fill=CARD, outline=BORDER)
draw.text((center_x + 20, center_y + 12), "Evidence Produced", font=h3_font, fill=INK)

evidence_items = [
    ("execution_summary.json", TEAL),
    ("screenshots/checkout-fail.png", ORANGE),
    ("failure-analysis.md", FUCHSIA),
    ("run.json", VIOLET),
    ("verdict.json", GREEN),
]
ey = center_y + 50
for item, color in evidence_items:
    draw.ellipse((center_x + 25, ey + 4, center_x + 37, ey + 16), fill=color)
    draw.text((center_x + 55, ey), item, font=mono_small, fill=INK)
    ey += 36

# RIGHT: JIRA proposal + Learning
right_x = 820
right_y = 130
draw.rounded_rectangle((right_x, right_y, right_x + 320, right_y + 110), radius=16, fill=CARD, outline=FUCHSIA, width=2)
draw.text((right_x + 20, right_y + 12), "JIRA Proposal", font=h3_font, fill=INK)
draw.text((right_x + 20, right_y + 42), "Shadow mode: ON", font=body_font, fill=FUCHSIA)
draw.text((right_x + 20, right_y + 70), "Comment drafted, not posted", font=small_font, fill=MUTED)

draw.rounded_rectangle((right_x, right_y + 130, right_x + 320, right_y + 220), radius=16, fill=CARD, outline=GREEN, width=2)
draw.text((right_x + 20, right_y + 145), "Learning Captured", font=h3_font, fill=INK)
draw.text((right_x + 20, right_y + 175), "1 new entry in _inbox.md", font=small_font, fill=GREEN)
draw.text((right_x + 20, right_y + 198), "seen: 2 → promote to rule", font=small_font, fill=MUTED)

# Footer
footer_y = 520
draw.rounded_rectangle((60, footer_y, W - 60, footer_y + 65), radius=16, fill=CARD, outline=BORDER)
draw.text((85, footer_y + 22), "\"No evidence, no verdict.\" — every run produces proof.", font=body_font, fill=INK)

img.save('docs/images/example-run.png', 'PNG', optimize=True)
print(f"example-run.png: {os.path.getsize('docs/images/example-run.png')} bytes")
