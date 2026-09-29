# App Store screenshots — brief

For whoever is designing the store frames. Everything you need is in this folder; nothing here needs the app
or a simulator.

## The app

**Page & Plate.** You photograph a page of a cookbook you own. It reads the ingredients and the yield, you
confirm them, and it scales the recipe to the number of portions you actually want — then puts the shopping
for a whole planned week into Apple Reminders in one tap. A household can share one week and cook from
everyone's books.

The thing that makes it different, and the thing the screenshots have to sell: **it does the arithmetic
properly.** A quarter of a tin stays a quarter of a tin. Three recipes sharing garlic merge into one line.

## What's in `screenshots/raw/`

Unretouched device captures at native resolution — no frames, no text, no scaling. Eleven files: nine you
need, two spares.

| File | Screen | What it has to prove |
|---|---|---|
| `shot1.png` | New recipe, a page loaded, "Extract 1 page" ready | You photograph a page and that's the whole input |
| `review-via-edit.png` | The ingredient form, parsed rows | It read the page: `1 tin (400 g)`, `1½ tsp`, `Feta — 200 g` off `200g/7oz`, each with the printed line underneath |
| `shot3b.png` | A recipe scaled to ×¼ | `Chopped tomatoes — ¼ tin (400 g)` and `Olive oil — 2 tbsp · doesn't scale`, under the ×¼ |
| `shot4.png` | The week planner | Mon 4 servings, Wed 2, Thu 6 — each meal at its own portions |
| `household.png` | A shared week | "Added by Sara" on two meals, the reader's own on a third, and a note bubble |
| `shot5.png` | The week's export sheet | The merges: `Butter beans — 5 tins (400 g)` across two recipes, `Garlic — 9½–11 cloves` across three, olive oil marked `staple` and unticked |
| `shot6.png` | The recipe library | Real books and page numbers — these are recipes you own, not a web database |
| `ipad2.png` | iPad planner | The whole week at a glance |
| `ipad4.png` | iPad scaled recipe | Same ×¼ proof, wider |
| `ipad6.png` | iPad export sheet | **The weak one** — a form sheet over the plan; it doesn't use the width |
| `shot1-empty.png` | *Spare.* New recipe with nothing loaded | Use if a barer first frame works better |

## Apple's requirements

- **iPhone 6.9"**: 1320 × 2868. Up to 10 frames; the first 3 are what people see without scrolling.
- **iPad 13"**: 2064 × 2752. Up to 10.
- **RGB, no alpha channel.** The raws carry an (opaque) alpha channel because that's how the simulator writes
  them — flatten it on export or the upload is rejected.
- No device bezel is required. The current frames don't use one.

Whatever the layout, the finished frame must be exactly those pixel sizes. The current ones are built at CSS
size and rendered at 3× (iPhone) and 2× (iPad) so type stays sharp rather than being upscaled.

## The current frames, for reference only

In `screenshots/iphone-6.9/` and `screenshots/ipad-13/`. Headline above, screen below in a rounded container.
They are being redone — treat them as what the copy was trying to say, not as a layout to match.

| # | Headline | Subline |
|---|---|---|
| 1 | Photograph the page. That's it. | Ingredients and servings, read off the paper. |
| 2 | It reads the list for you. | Quantities, units and servings, straight off the page. |
| 3 | Cooking for one? | Every line follows — and a quarter tin stays a quarter tin. |
| 4 | Plan the week. | Every meal at its own number of portions. |
| 5 | Cook together. | One week your household shares, and everyone's books to cook from. |
| 6 | One shop for the whole week. | Straight into a Reminders list. Staples left out. |
| 7 | The books you already own. | No accounts, no web clipping, no database to subscribe to. |

## Brand

Display face **Fraunces** (headlines); body is the system face. The app's own palette, which the frames draw
on — all of it lives in `ios/RecipeBasket/Brand.swift`:

| | Light | Note |
|---|---|---|
| Accent ("tomato") | `#B23A1B` | Chosen to clear 4.5:1 on paper *and* carry white on top |
| Secondary ("ochre") | `#8A5D18` | |
| Paper | `#FAF7F0` | The app's background |
| Ink | `#23201B` | Body text |
| Ink, secondary | `#5C554A` | Sublines |
| Rule | `#E6DED0` | Hairlines |
| Frame background | `#F4EFE5` | The current frames' surround, slightly warmer than paper |

Contrast was measured rather than eyeballed; an earlier accent failed at 3.2:1. Please keep text on background
at 4.5:1 or better.

## Two rules that are not negotiable

1. **The cookbook pages in these shots are ours.** They were written and designed for this — see
   `marketing/pages/`. Real published cookbook pages must never appear in store screenshots; that is someone
   else's book in our marketing. Don't substitute stock cookbook photography for the same reason.
2. **Don't invent numbers.** Every quantity on screen is what the app actually computed. If a frame needs
   different figures, ask — they can be reshot, but they can't be edited in a graphics program.

## Known gaps

- **No iPad household frame.** The iPad simulator's build predates the demo-household seeder, so it has no
  household to show. Reshootable once that build is refreshed — see `marketing/README.md`.
- **`review-via-edit.png` is the edit screen, not the post-scan review screen.** Same view, same parsed rows,
  same printed lines; the navigation bar says "Edit recipe / Cancel / Save" rather than the review chrome.
  Reaching the real one costs a live scan. Say the word if the difference matters for frame 2.
- **`ipad6.png` is honest but weak** — the export sheet sits over the plan as a form sheet and wastes the
  width. Worth knowing before you build a frame around it.

## Reshooting

`marketing/README.md` has the whole pipeline: the cookbook pages are HTML rendered to PNG, dropped into a
simulator's photo library, and the captures come from `xcrun simctl io <device> screenshot`, which writes at
native resolution. The status bar in these was set to 9:41 with full bars via `simctl status_bar override`.
