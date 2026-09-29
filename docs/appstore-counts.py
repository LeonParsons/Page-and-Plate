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
    # The featuring nomination's own fields, which are `###` headings under "## Featuring nomination".
    # Apple's limits, from the nominations template (checked 2026-09-29).
    "Nomination name": 60,
    "Nomination description": 1000,
    "Helpful details": 500,
    # App Review Information -> Notes. Apple states this one in *bytes* (App Store Connect Help, checked
    # 2026-09-29), so it is counted as UTF-8 below rather than as characters.
    "App Review notes": 4000,
}

# Fields whose limit Apple expresses in bytes rather than characters. Identical for ASCII; an en dash or a
# curly quote costs three bytes and one character, which is how a field passes here and is refused at upload.
BYTE_FIELDS = {"App Review notes"}

# The in-app purchase table's columns, by header, -> limit. **Read from the document**, not copied here: these
# were hardcoded, drifted from the table they were meant to be checking, and went on reporting "ok" for strings
# that had not been in the listing for weeks. A checker that checks something other than the document is worse
# than no checker.
IAP_COLUMNS = {
    "Display name": 30,
    "Description": 45,
}


def fields(text):
    """Yield (heading, first fenced block) for each '## Heading — N max' section.

    Third-level headings count too: the nomination's fields sit under "## Featuring nomination", and its
    description used to be three essays totalling roughly twice what Apple's form accepts — unnoticed because
    nothing counted it.
    """
    sections = re.split(r"^#{2,3} ", text, flags=re.MULTILINE)[1:]
    for section in sections:
        heading = section.split("\n", 1)[0]
        name = heading.split(" — ")[0].strip()
        if name not in LIMITS:
            continue
        block = re.search(r"```\n(.*?)\n```", section, flags=re.DOTALL)
        if block:
            yield name, block.group(1)


def iap_rows(text):
    """Yield (label, value, limit) for every cell of the in-app purchase table."""
    table = re.search(r"^## In-app purchases\n(.*?)(?=^## |\Z)", text, flags=re.DOTALL | re.MULTILINE)
    if not table:
        return
    rows = [
        [cell.strip() for cell in line.strip().strip("|").split("|")]
        for line in table.group(1).splitlines()
        if line.strip().startswith("|")
    ]
    if len(rows) < 3:
        return
    # Row 0 is the header, row 1 the |---| separator, the rest are products.
    headers = [re.sub(r"\s*\(\d+\)$", "", header) for header in rows[0]]
    for row in rows[2:]:
        product = row[0].strip("`").rsplit(".", 1)[-1]
        for header, cell in zip(headers, row):
            if header not in IAP_COLUMNS:
                continue
            yield f"IAP {header.lower()} ({product})", cell.strip("`"), IAP_COLUMNS[header]


def main():
    text = DOC.read_text()
    failures = []

    checked = set()
    for name, value in fields(text):
        limit = LIMITS[name]
        unit = "bytes" if name in BYTE_FIELDS else "chars"
        count = len(value.encode("utf-8")) if name in BYTE_FIELDS else len(value)
        checked.add(name)
        status = "ok " if count <= limit else "OVER"
        if count > limit:
            failures.append(f"{name}: {count} > {limit} {unit}")
        print(f"  [{status}] {name:<22} {count:>5} / {limit} {unit}")

    iap = list(iap_rows(text))
    if not iap:
        failures.append("no in-app purchase table found")
    for name, value, limit in iap:
        count = len(value)
        status = "ok " if count <= limit else "OVER"
        if count > limit:
            failures.append(f"{name}: {count} > {limit}")
        print(f"  [{status}] {name:<28} {count:>5} / {limit}")

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
