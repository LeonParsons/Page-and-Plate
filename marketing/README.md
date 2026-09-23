# Marketing assets

App Store screenshots and the cookbook pages they were shot against. The listing copy lives in
`docs/APPSTORE.md`.

```
screenshots/iphone-6.9/   six frames, 1320 x 2868 (iPhone 17 Pro Max, native)
screenshots/ipad-13/      three frames, 2064 x 2752 (iPad Pro 13-inch, native)
pages/                    the cookbook pages, as HTML — our own recipes, not anyone's book
tools/                    html2png.swift, makeframes.py, makeipad.py
```

All nine are RGB with no alpha channel, which Apple requires.

## Why the pages are ours

`fixtures/photos/` holds real cookbook pages and is marked personal-use-only. Those cannot appear in store
screenshots — it is someone else's book in our marketing. The pages in `pages/` were written and designed for
this, and the recipes are chosen to exercise the scaler: a 3–4 range, a 1½ tsp that lands on the SPEC §11 tie
case, two tin sizes, `200g/7oz` dual units, an unscalable "for frying", a "handful", and a salt-and-pepper
pair. Ingredients deliberately overlap between the three so the week-export frame has real merges to show.

## Regenerating

`html2png.swift` renders an HTML file to a PNG at an exact pixel size, via WKWebView's PDF output rather than
`takeSnapshot` (which crashes inside WebKit when run from a `swift` script). The layout is authored at CSS
size and `pageZoom` renders it at the scale, so text stays sharp instead of being upscaled.

```bash
# a cookbook page, to put in a simulator's photo library
swift marketing/tools/html2png.swift marketing/pages/88-smoky-butter-beans.html 559 868 2 page.png
xcrun simctl addmedia "iPhone 17 Pro Max" page.png

# the frames, once the app captures are in place beside the scripts
python3 marketing/tools/makeframes.py    # iPhone
python3 marketing/tools/makeipad.py      # iPad
```

Captures come from `xcrun simctl io <device> screenshot`, which writes at native resolution — that is what
guarantees Apple's accepted dimensions rather than resizing afterwards.

## Before these go to App Store Connect

1. **The free-scan count.** Frame 1 reads "17 of 20 free scans left" because the build was made with
   `ScanAllowance.freeScans = 20`, the release value. The repo is back to 100 for Leon's private use, so
   rebuild with 20 before reshooting anything.
2. The iPad export sheet sits as a small form sheet over the plan and does not use the width well. It is
   honest, but it is the weakest of the nine.
