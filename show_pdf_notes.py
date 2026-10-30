#!/usr/bin/env python3

import sys
import pymupdf

FONTSIZE = 9
LINE_SPACING = 1.2
LINE_HEIGHT = FONTSIZE * LINE_SPACING
MAX_WIDTH = 180
PADDING = 4
GAP = 10
ARROW_HEAD = 5
NOTE_COLOR = (0.6, 0.5, 0)
FONT = pymupdf.Font("helv")


def text_width(text):
    return FONT.text_length(text, FONTSIZE)


def wrap(content, width):
    """Split the note into lines no wider than width, breaking long words."""
    lines = []
    for paragraph in content.splitlines():
        line = ""
        for word in paragraph.split():
            if text_width(f"{line} {word}".strip()) <= width:
                line = f"{line} {word}".strip()
                continue
            if line:
                lines.append(line)
            while text_width(word) > width:
                cut = next(i for i in range(len(word) - 1, 0, -1) if text_width(word[:i]) <= width)
                lines.append(word[:cut])
                word = word[cut:]
            line = word
        lines.append(line)
    return lines


def layout_note(page, content):
    """Return the note's lines, cut to fit the page, and whether any were cut."""
    max_lines = int((page.rect.height - 2 * PADDING) / LINE_HEIGHT)

    # Only go wider than MAX_WIDTH if the note would otherwise overflow the page.
    for limit in (min(MAX_WIDTH, page.rect.width), page.rect.width):
        lines = wrap(content, limit - 2 * PADDING)
        if len(lines) <= max_lines:
            break

    return lines[:max_lines], len(lines) > max_lines


def overlap(box, obstacles):
    return sum((box & r).get_area() for r in obstacles if box.intersects(r))


def place_note(page, icon, width, height, notes, words):
    """Return the box beside the icon, kept on the page, that hides the least.

    Avoiding icons and other notes takes priority over avoiding page text, so
    the box stays beside its icon's spot and notes stay readable.
    """
    candidates = [
        (icon.x1 + GAP, icon.y0),  # right
        (icon.x0 - GAP - width, icon.y0),  # left
        (icon.x0, icon.y1 + GAP),  # below
        (icon.x0, icon.y0 - GAP - height),  # above
    ]
    boxes = []
    for x, y in candidates:
        x = max(0, min(x, page.rect.width - width))
        y = max(0, min(y, page.rect.height - height))
        boxes.append(pymupdf.Rect(x, y, x + width, y + height))
    return min(boxes, key=lambda box: (overlap(box, notes), overlap(box, words)))


def draw_arrow(page, box, tip):
    """Draw an arrow from the closest point on the box to tip, if tip is outside."""
    start = pymupdf.Point(
        max(box.x0, min(tip.x, box.x1)),
        max(box.y0, min(tip.y, box.y1)),
    )
    length = abs(tip - start)
    if length == 0:
        return

    head = min(ARROW_HEAD, length)
    direction = (tip - start) / length
    base = tip - direction * head
    side = pymupdf.Point(-direction.y, direction.x) * head / 2

    shape = page.new_shape()
    shape.draw_line(start, base)
    shape.draw_polyline([tip, base + side, base - side, tip])
    shape.finish(color=NOTE_COLOR, fill=NOTE_COLOR, closePath=False)
    shape.commit(overlay=True)


source, destination = sys.argv[1:3]
doc = pymupdf.open(source)

for number, page in enumerate(doc.pages(), 1):
    icons = [annot for annot in page.annots() or [] if annot.type[1] == "Text"]
    taken = [annot.rect for annot in icons]
    words = [pymupdf.Rect(word[:4]) for word in page.get_text("words")]

    for annot in icons:
        icon, content = annot.rect, annot.info.get("content", "")
        if not content.strip():
            continue

        lines, truncated = layout_note(page, content)
        if truncated:
            print(f"Warning: note on page {number} too long to fit, cut off")

        width = max(map(text_width, lines)) + 2 * PADDING
        height = len(lines) * LINE_HEIGHT + 2 * PADDING
        box = place_note(page, icon, width, height, taken, words)
        taken.append(box)

        page.draw_rect(box, color=NOTE_COLOR, fill=(1, 1, 0.85), overlay=True)
        draw_arrow(page, box, (icon.tl + icon.br) / 2)
        page.insert_text(
            (box.x0 + PADDING, box.y0 + PADDING + FONTSIZE),
            "\n".join(lines),
            fontsize=FONTSIZE,
            lineheight=LINE_SPACING,
            color=(0, 0, 0),
            overlay=True,
        )

        # The box now shows the note, so the sticky-note icon is redundant.
        page.delete_annot(annot)

doc.save(destination, garbage=4, deflate=True)
