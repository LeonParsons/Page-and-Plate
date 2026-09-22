#!/usr/bin/env python3
"""Check every App Store field in docs/APPSTORE.md against Apple's character limits.

    python3 docs/appstore-counts.py

Run it after editing the listing. A field that is one character over is rejected at upload, and finding that
out in App Store Connect is a slow way to learn it.
"""

import pathlib
import re
import sys

DOC = pathlib.Path(__file__).parent / "APPSTORE.md"

# Heading (as written in the doc) -> limit. The fenced block under each heading is the field.
LIMITS = {
    "App name": 30,
    "Subtitle": 30,
    "Promotional text": 170,
    "Keywords": 100,
    "Description": 4000,
    "What's New": 4000,
}

# Table fields, checked separately: (label, value, limit)
TABLE_FIELDS = [
    ("IAP display name (monthly)", "Unlimited Monthly", 30),
    ("IAP display name (yearly)", "Unlimited Yearly", 30),
    ("IAP description (monthly)", "Unlimited cookbook scans, billed monthly", 45),
    ("IAP description (yearly)", "Unlimited cookbook scans, billed yearly", 45),
]


def fields(text):
    """Yield (heading, first fenced block) for each '## Heading — N max' section."""
    sections = re.split(r"^## ", text, flags=re.MULTILINE)[1:]
    for section in sections:
        heading = section.split("\n", 1)[0]
        name = heading.split(" — ")[0].strip()
        if name not in LIMITS:
            continue
        block = re.search(r"```\n(.*?)\n```", section, flags=re.DOTALL)
        if block:
            yield name, block.group(1)


def main():
    text = DOC.read_text()
    failures = []

    checked = set()
    for name, value in fields(text):
        limit = LIMITS[name]
        count = len(value)
        checked.add(name)
        status = "ok " if count <= limit else "OVER"
        if count > limit:
            failures.append(f"{name}: {count} > {limit}")
        print(f"  [{status}] {name:<20} {count:>5} / {limit}")

    for name, value, limit in TABLE_FIELDS:
        count = len(value)
        status = "ok " if count <= limit else "OVER"
        if count > limit:
            failures.append(f"{name}: {count} > {limit}")
        print(f"  [{status}] {name:<20} {count:>5} / {limit}")

    missing = set(LIMITS) - checked
    if missing:
        failures.append(f"no fenced block found for: {', '.join(sorted(missing))}")

    if failures:
        print("\nFAILED:")
        for failure in failures:
            print(f"  - {failure}")
        sys.exit(1)
    print("\nAll fields within Apple's limits.")


if __name__ == "__main__":
    main()
