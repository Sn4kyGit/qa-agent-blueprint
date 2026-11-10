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
YELLOW = (250, 204, 21)

try:
    title_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 44)
    h2_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 26)
    h3_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
    body_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 16)
    small_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
    tiny_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 11)
    mono_font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 14)
    mono_small = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 12)
    mono_tiny = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 11)
except:
    title_font = h2_font = h3_font = body_font = small_font = tiny_font = mono_font = mono_small = mono_tiny = ImageFont.load_default()

def gradient(draw, w, h):
    for y in range(h):
        r = int(11 + (25-11) * y / h)
        g = int(13 + (15-13) * y / h)
        b = int(18 + (30-18) * y / h)
        draw.line([(0, y), (w, y)], fill=(r, g, b))

def make_hero():
    W, H = 1200, 680
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    gradient(draw, W, H)

    draw.text((60, 45), "QA Agent Blueprint", font=title_font, fill=INK)
    draw.text((60, 105), "Turn Claude Code into a learning QA Manager", font=h2_font, fill=MUTED)

    badges = ["33 Skills", "9 Subagents", "4 Hooks", "2 MCP Servers", "Apache 2.0"]
    bx = 60
    for b in badges:
        bbox = draw.textbbox((0, 0), b, font=small_font)
        bw = bbox[2] - bbox[0] + 24
        draw.rounded_rectangle((bx, 155, bx + bw, 185), radius=15, fill=CARD, outline=BORDER)
        draw.text((bx + 12, 162), b, font=small_font, fill=MUTED)
        bx += bw + 12

    pipe_y = 245
    pipe_h = 90
    pipe_w = 150
    gap = 22
    start_x = 60

    steps = [
        ("JIRA Ticket", "SHOP-1234", VIOLET),
        ("Route", "Project + Product", FUCHSIA),
        ("Test", "Exploratory + CLI", ORANGE),
        ("Evidence", "Screenshots + Logs", TEAL),
        ("Report", "Comment + Transition", VIOLET),
        ("Learn", "Captured + Enforced", FUCHSIA),
    ]

    for i, (title, sub, color) in enumerate(steps):
        x = start_x + i * (pipe_w + gap)
        draw.rounded_rectangle((x, pipe_y, x + pipe_w, pipe_y + pipe_h), radius=14, fill=CARD, outline=color, width=2)
        draw.rounded_rectangle((x + 2, pipe_y + 2, x + pipe_w - 2, pipe_y + 6), radius=2, fill=color)
        draw.text((x + 14, pipe_y + 22), title, font=body_font, fill=INK)
        draw.text((x + 14, pipe_y + 52), sub, font=small_font, fill=MUTED)
        if i < len(steps) - 1:
            ax = x + pipe_w + 5
            ay = pipe_y + pipe_h // 2
            draw.polygon([(ax, ay), (ax + 14, ay - 7), (ax + 14, ay + 7)], fill=MUTED)

    stats_y = 400
    stats = [
        ("~7k", "Token Budget", VIOLET),
        ("46", "Eval Cases", FUCHSIA),
        ("152+17", "Tests", ORANGE),
        ("Security", "Audited", TEAL),
    ]
    sx = 60
    for val, label, color in stats:
        draw.rounded_rectangle((sx, stats_y, sx + 190, stats_y + 75), radius=14, fill=CARD, outline=BORDER)
        draw.text((sx + 18, stats_y + 14), val, font=h3_font, fill=color)
        draw.text((sx + 18, stats_y + 46), label, font=small_font, fill=MUTED)
        sx += 205

    draw.text((60, H - 55), "github.com/Sn4kyGit/qa-agent-blueprint", font=mono_small, fill=MUTED)
    draw.text((W - 280, H - 55), "Claude Code + opencode", font=small_font, fill=MUTED)
    img.save('docs/images/hero.png', 'PNG', optimize=True)
    print(f"hero.png: {os.path.getsize('docs/images/hero.png')} bytes")

def make_workflow():
    W, H = 1200, 720
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    gradient(draw, W, H)

    draw.text((60, 35), "How it works", font=title_font, fill=INK)
    draw.text((60, 90), "From JIRA ticket to verified result — enforced, not suggested", font=h3_font, fill=MUTED)

    input_x = 60
    input_y = 150
    draw.rounded_rectangle((input_x, input_y, input_x + 200, input_y + 70), radius=16, fill=CARD, outline=VIOLET, width=2)
    draw.text((input_x + 20, input_y + 15), "JIRA Ticket", font=h3_font, fill=INK)
    draw.text((input_x + 20, input_y + 45), "SHOP-1234", font=mono_font, fill=VIOLET)

    arrow_x = input_x + 210
    arrow_y = input_y + 30
    draw.polygon([(arrow_x, arrow_y), (arrow_x + 25, arrow_y - 10), (arrow_x + 25, arrow_y + 10)], fill=MUTED)

    pipe_x = 280
    pipe_y = 140
    pipe_w = 500
    pipe_h = 300

    steps = [
        ("1", "Read & Route", "Match ticket to project + product", VIOLET),
        ("2", "Check Readiness", "Deployed build, merge status, VPN", FUCHSIA),
        ("3", "Test", "Exploratory + regression (MCP or CLI)", ORANGE),
        ("4", "Produce Evidence", "Screenshots, logs, execution_summary.json", TEAL),
        ("5", "Report & Learn", "JIRA comment + captured learnings", GREEN),
    ]

    sy = pipe_y
    for num, title, desc, color in steps:
        cx = pipe_x + 30
        cy = sy + 20
        draw.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=color)
        draw.text((cx - 5, cy - 10), num, font=h3_font, fill=BG)
        draw.text((pipe_x + 65, sy + 5), title, font=body_font, fill=INK)
        draw.text((pipe_x + 65, sy + 30), desc, font=small_font, fill=MUTED)
        if num != "5":
            draw.line([(cx, cy + 18), (cx, cy + 38)], fill=BORDER, width=2)
        sy += 60

    arrow_x = pipe_x + pipe_w + 10
    arrow_y = pipe_y + pipe_h // 2
    draw.polygon([(arrow_x, arrow_y), (arrow_x + 25, arrow_y - 10), (arrow_x + 25, arrow_y + 10)], fill=MUTED)

    out_x = 830
    out_y = 140
    outputs = [
        ("Verdict", "PASS / FAIL / BLOCKED", GREEN),
        ("Evidence", "8 artifacts in run dir", TEAL),
        ("JIRA Report", "Comment + transition", VIOLET),
        ("Learnings", "Captured + declared", FUCHSIA),
    ]

    oy = out_y
    for title, desc, color in outputs:
        draw.rounded_rectangle((out_x, oy, out_x + 310, oy + 60), radius=14, fill=CARD, outline=color, width=1)
        draw.text((out_x + 16, oy + 10), title, font=body_font, fill=INK)
        draw.text((out_x + 16, oy + 35), desc, font=small_font, fill=MUTED)
        oy += 72

    insight_y = 500
    draw.rounded_rectangle((60, insight_y, W - 60, insight_y + 110), radius=16, fill=CARD, outline=BORDER, width=1)
    draw.text((85, insight_y + 15), "The key insight", font=h3_font, fill=INK)
    draw.text((85, insight_y + 48), "The agent knows YOUR project because it reads PROJECT.md (test users, environments,", font=small_font, fill=MUTED)
    draw.text((85, insight_y + 70), "deploy runbook) and PRODUCT.md (what differs per product). None of that is in the prompt —", font=small_font, fill=MUTED)
    draw.text((85, insight_y + 92), "it comes from files in your repo. Reviewable, diffable, shared via Git.", font=small_font, fill=MUTED)

    badge_y = 640
    badges_enforced = [
        ("Evidence", "enforced by Stop hook", TEAL),
        ("Learnings", "enforced by Stop hook", FUCHSIA),
        ("Shadow mode", "default: no JIRA writes", ORANGE),
        ("Security", "guard blocks secrets + self-escalation", VIOLET),
    ]
    bx = 60
    for title, desc, color in badges_enforced:
        bw = 260
        draw.rounded_rectangle((bx, badge_y, bx + bw, badge_y + 55), radius=12, fill=CARD, outline=color, width=1)
        draw.text((bx + 14, badge_y + 8), title, font=small_font, fill=color)
        draw.text((bx + 14, badge_y + 30), desc, font=small_font, fill=MUTED)
        bx += bw + 15

    img.save('docs/images/workflow.png', 'PNG', optimize=True)
    print(f"workflow.png: {os.path.getsize('docs/images/workflow.png')} bytes")

def make_before_after():
    W, H = 1200, 720
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    gradient(draw, W, H)

    draw.text((60, 35), "Before vs. After", font=title_font, fill=INK)
    draw.text((60, 90), "The same ticket, two very different workflows", font=h3_font, fill=MUTED)

    panel_y = 140
    panel_h = 520
    panel_w = 520

    left_x = 60
    draw.rounded_rectangle((left_x, panel_y, left_x + panel_w, panel_y + panel_h), radius=18, fill=(28, 16, 16), outline=(70, 28, 28), width=2)
    draw.text((left_x + 25, panel_y + 18), "WITHOUT Blueprint", font=h2_font, fill=RED)

    pains = [
        "Manual test planning (30-50% overhead)",
        "No evidence discipline — 'looks good!'",
        "Forgets between sessions",
        "Inconsistent bug reports",
        "No learning from past runs",
        "Token waste re-reading context",
        "No security guardrails",
        "Slow, manual, error-prone",
    ]
    py = panel_y + 75
    for p in pains:
        draw.text((left_x + 30, py), "X", font=body_font, fill=RED)
        draw.text((left_x + 55, py), p, font=small_font, fill=MUTED)
        py += 42

    draw.text((left_x + 25, panel_y + panel_h - 55), "Time per ticket:", font=small_font, fill=MUTED)
    draw.text((left_x + 25, panel_y + panel_h - 32), "~2-4 hours", font=h2_font, fill=RED)

    arrow_cx = left_x + panel_w + 10
    arrow_cy = panel_y + panel_h // 2
    draw.polygon([(arrow_cx, arrow_cy), (arrow_cx + 35, arrow_cy - 12), (arrow_cx + 35, arrow_cy + 12)], fill=VIOLET)
    draw.text((arrow_cx - 2, arrow_cy + 25), "improves", font=tiny_font, fill=VIOLET)

    right_x = 640
    draw.rounded_rectangle((right_x, panel_y, right_x + panel_w, panel_y + panel_h), radius=18, fill=(15, 22, 18), outline=(28, 70, 45), width=2)
    draw.text((right_x + 25, panel_y + 18), "WITH QA Agent Blueprint", font=h2_font, fill=GREEN)

    solutions = [
        "Autonomous test planning + execution",
        "Mandatory evidence — Stop hook enforces",
        "Learning loop — remembers what it learned",
        "Project-conformant bug reports",
        "Promotion: seen twice -> becomes a rule",
        "7k always-loaded budget, on-demand skills",
        "Security guard + shadow mode + audit",
        "Fast, consistent, auditable",
    ]
    sy = panel_y + 75
    for s in solutions:
        draw.text((right_x + 30, sy), "+", font=body_font, fill=GREEN)
        draw.text((right_x + 55, sy), s, font=small_font, fill=MUTED)
        sy += 42

    draw.text((right_x + 25, panel_y + panel_h - 55), "Time per ticket:", font=small_font, fill=MUTED)
    draw.text((right_x + 25, panel_y + panel_h - 32), "~15-30 min", font=h2_font, fill=GREEN)

    img.save('docs/images/before-after.png', 'PNG', optimize=True)
    print(f"before-after.png: {os.path.getsize('docs/images/before-after.png')} bytes")

def make_features():
    W, H = 1200, 850
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    gradient(draw, W, H)

    draw.text((60, 35), "33 Skills — the complete toolbox", font=title_font, fill=INK)
    draw.text((60, 90), "Every skill is a specialized workflow. Load on demand, token-efficient.", font=h3_font, fill=MUTED)

    categories = [
        ("Test Workflow", VIOLET, [
            "test-ticket", "retest-bug", "exploratory-testing",
            "test-automation", "recon", "scaffold-suite",
        ]),
        ("Analysis & Reports", FUCHSIA, [
            "failure-analysis", "bug-report", "report-to-jira",
            "qa-report", "perf-analysis", "qa-metrics",
        ]),
        ("Learning & Config", ORANGE, [
            "retro-learn", "skill-review", "whats-new",
            "onboard-project", "onboard-product", "re-board",
        ]),
        ("Security & Quality", TEAL, [
            "security-testing", "accessibility-testing", "visual-testing",
            "api-testing", "risk-based-testing", "release-readiness",
        ]),
        ("Specialists", GREEN, [
            "bug-reproduction", "test-reliability", "test-case-management",
            "webdriverio-testing", "demo", "qa-help",
        ]),
        ("Harness & Model", YELLOW, [
            "agentswitch", "model-setup",
        ]),
    ]

    cat_y = 140
    for cat_name, cat_color, skills in categories:
        draw.rounded_rectangle((60, cat_y, W - 60, cat_y + 34), radius=10, fill=CARD, outline=BORDER)
        draw.rounded_rectangle((60, cat_y, 70, cat_y + 34), radius=5, fill=cat_color)
        draw.text((82, cat_y + 8), cat_name, font=body_font, fill=cat_color)
        draw.text((W - 140, cat_y + 10), f"{len(skills)} skills", font=small_font, fill=MUTED)
        cat_y += 46
        
        chip_x = 80
        chip_y = cat_y
        for skill in skills:
            bbox = draw.textbbox((0, 0), skill, font=mono_small)
            chip_w = bbox[2] - bbox[0] + 20
            if chip_x + chip_w > W - 80:
                chip_x = 80
                chip_y += 36
            draw.rounded_rectangle((chip_x, chip_y, chip_x + chip_w, chip_y + 30), radius=15, fill=CARD, outline=cat_color, width=1)
            draw.text((chip_x + 10, chip_y + 7), skill, font=mono_small, fill=INK)
            chip_x += chip_w + 10
        
        cat_y = chip_y + 48

    draw.text((60, H - 55), "All in plain Markdown — reviewable, diffable, shared via Git", font=small_font, fill=MUTED)
    draw.text((W - 250, H - 55), "github.com/Sn4kyGit", font=mono_small, fill=MUTED)
    img.save('docs/images/features.png', 'PNG', optimize=True)
    print(f"features.png: {os.path.getsize('docs/images/features.png')} bytes")

make_hero()
make_workflow()
make_before_after()
make_features()
