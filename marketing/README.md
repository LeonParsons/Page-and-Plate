# Marketing assets

App Store screenshots and the cookbook pages they were shot against. The listing copy lives in
`docs/APPSTORE.md`.

```
screenshots/iphone-6.9/   seven frames, 1320 x 2868 (iPhone 17 Pro Max, native)
screenshots/ipad-13/      three frames, 2064 x 2752 (iPad Pro 13-inch, native)
screenshots/raw/          the unframed device captures the frames are built from
pages/                    the cookbook pages, as HTML — our own recipes, not anyone's book
tools/                    html2png.swift, makeframes.py, makeipad.py
SCREENSHOT-BRIEF.md       hand this to anyone redesigning the frames
```

All ten frames are RGB with no alpha channel, which Apple requires.

**The raw captures are committed now** (2026-09-29), which they were not before: they lived beside the scripts
as working files and were lost, and they cannot be recovered from the finished frames — `object-fit: cover`
puts the screen in at about 84% on iPhone and 87% on iPad, minus a sliver of width, under a border and rounded
corners, and the crop differs per frame with how each headline wraps. Reshooting them cost nothing only because
both simulators still held the library; that will not always be true. **Commit them whenever they are reshot.**
Names match what `makeframes.py` and `makeipad.py` expect, so the scripts still run from that folder.

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

All were **reshot 2026-09-29**, on the iPhone 17 Pro Max and iPad Pro 13-inch (M5) simulators, against
the copy as it stands today. The previous set was shot 2026-09-23 and had gone stale in two ways: frame 1 read
"17 of 20 free scans left" from the pre-2026-09-23 limits, and it carried the capture help text that was
reversed on 2026-09-29 (see `docs/DECISIONS.md`).

**Three frames got better content rather than just a refresh**, because the old captures showed the top of a
screen where the claim is proved further down:

- **Frame 2 ("It reads the list for you")** now shows the extracted ingredient rows themselves — `1 tin
  (400 g)`, `1½ tsp`, and `Feta — 200 g` read off `200g/7oz`, each with the printed line beneath it.
- **Frame 3 ("a quarter tin stays a quarter tin")** now has `Chopped tomatoes — ¼ tin (400 g)` and
  `Olive oil — 2 tbsp · doesn't scale` in shot, under the ×¼ scaling.
- **Frame 5 / iPad 3 ("one shop")** show the real merges: `Butter beans — 5 tins (400 g)` across two recipes,
  `Garlic — 9½–11 cloves` across three, and olive oil marked `staple` and unticked.

The week is Monday 4 portions, Wednesday 2, Thursday 6, so "each meal at its own portions" is visible rather
than asserted.

## The household frame, and how it is possible at all

Frame 5 is the household — the thing the listing leads with, and for a while the one screen with no frame.
A simulator cannot host a household: hosting needs an iCloud account and a subscription, and the Simulator has
neither. Shooting it on real phones works, but it cannot be *re*shot when copy changes without two people, two
Apple Accounts and a live share — and the first attempt came off a phone whose plan held pages from real
published cookbooks, which is exactly what the section above rules out.

So the app seeds it. `HouseholdDemoSeed` (`#if DEBUG`, in `ios/RecipeBasket/Sharing/`) writes the same
`SharedRecipe` / `SharedMeal` / `SharedMemberRow` rows the sync engine writes, projected from this device's own
library through `SharedWeekProjection` — the same call the real projection makes. Every pixel is the real UI
rendering real rows; only their provenance is faked. **Settings → Seed demo household (debug)**, then shoot the
Plan tab.

Two things it has to get right, both learned the hard way:

- **Sara's recipes need ids of their own.** Joining a household runs `projectLibrary`, which upserts this
  device's recipes into it keyed on the library recipe's id. A demo row reusing that id is found, taken for
  this device's copy and rewritten with this device's (empty) `authorID` — so the row survives and only
  "Added by Sara" quietly disappears, which is the entire point of the frame.
- **Set "Your name" first.** It is what the Settings frame shows, and it is blank on a fresh simulator.

## Before these go to App Store Connect

1. The iPad export sheet sits as a form sheet over the plan and does not use the width well. It is honest,
   and it does at least show the week behind the list, but it is the weakest of the ten.
2. There is no iPad household frame. **The iPad simulator's installed build predates `HouseholdDemoSeed`**
   (installed 13:25 on 2026-09-29, where the iPhone's is 14:11), so Settings there has no "Seed demo
   household (debug)" row at all — that is why it cannot simply be shot. Install the current build on the
   iPad first, set "Your name", then seed.

## Reshooting

The three cookbook pages go into the simulator's photo library first (`html2png.swift`, then
`simctl addmedia`). To put the same library on the iPad without scanning it again — which costs scans and
real money — copy the app's data container across rather than repeating the flow by hand:

```bash
SRC=$(xcrun simctl get_app_container <iphone-udid> com.leonparsons.RecipeBasket data)
DST=$(xcrun simctl get_app_container <ipad-udid>   com.leonparsons.RecipeBasket data)
cp -R "$SRC/Library/Application Support" "$DST/Library/Application Support"
cp -R "$SRC/Documents" "$DST/Documents"
```

Install and launch the app on the destination once first, so the container exists, and terminate it before
copying. The default Reminders list does not travel (the list id is per device), so pick it again in the
export sheet.
