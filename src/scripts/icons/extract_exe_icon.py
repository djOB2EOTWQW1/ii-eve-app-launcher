#!/usr/bin/env python3
"""Extract the embedded icon from a Windows PE (.exe) file to a PNG.

Usage:
    extract_exe_icon.py <exe_path> <out_png>

Prints the output path on success, exits non-zero on failure.
"""
import os
import sys

from icoextract import IconExtractor, IconExtractorError
from PIL import Image


def extract(exe_path: str, out_png: str) -> int:
    try:
        extractor = IconExtractor(exe_path)
    except IconExtractorError as e:
        print(f"no icon: {e}", file=sys.stderr)
        return 2

    buf = extractor.get_icon(num=0)
    buf.seek(0)

    img = Image.open(buf)
    if hasattr(img, "ico"):
        sizes = sorted(img.ico.sizes(), key=lambda s: s[0] * s[1])
        frame = img.ico.getimage(sizes[-1])
    else:
        frame = img

    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    frame.convert("RGBA").save(out_png, format="PNG")
    print(out_png)
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: extract_exe_icon.py <exe> <out.png>", file=sys.stderr)
        return 64
    return extract(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    sys.exit(main())
