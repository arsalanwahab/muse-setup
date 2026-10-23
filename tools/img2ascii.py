#!/usr/bin/env python3
"""img2ascii — convert an image to ASCII art.

    python3 img2ascii.py logo.png --width 80
    python3 img2ascii.py logo.png --width 80 --color
"""

from __future__ import annotations

import argparse
import sys

from PIL import Image

RAMP = " .:-=+*#%@"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--width", type=int, default=80)
    ap.add_argument("--color", action="store_true", help="24-bit ANSI colour")
    ap.add_argument("--invert", action="store_true")
    args = ap.parse_args()

    # Terminal cells are about twice as tall as they are wide.
    img = Image.open(args.image).convert("RGB")
    height = max(1, int(img.height / img.width * args.width * 0.5))
    img = img.resize((args.width, height))

    ramp = RAMP[::-1] if args.invert else RAMP
    last = None
    for y in range(height):
        row = []
        for x in range(args.width):
            r, g, b = img.getpixel((x, y))
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            ch = ramp[min(len(ramp) - 1, int(lum * len(ramp)))]
            if args.color and ch != " ":
                row.append(f"\x1b[38;2;{r};{g};{b}m{ch}\x1b[0m")
            else:
                row.append(ch)
        print("".join(row))


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError:
        sys.exit("image not found")
