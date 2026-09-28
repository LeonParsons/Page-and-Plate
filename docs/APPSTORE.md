# App Store listing — Page & Plate

Everything to paste into App Store Connect, plus the featuring nomination. Character counts are checked by
`docs/appstore-counts.py`; run it after any edit here.

**Before this goes live:** the real terms and privacy URLs are still outstanding — `Subscription/Products.swift`
points at example.com — and the two subscriptions still have to be created in App Store Connect.

**The plan is no longer called "Unlimited"** (Leon, 2026-09-28). It carried a real ceiling of 25 scans a week
that is deliberately never shown (rule 9b), and typed recipes are now free and genuinely unlimited, so the word
claimed the wrong thing in both directions — and App Review reads a subscription name as a claim. The
subscription is simply what you buy to scan recipes; nothing needs an adjective.

---

## App name — 30 max

```
Page & Plate
```

12 characters. Deliberately left short: the subtitle carries the search terms, and a bare name reads more
confident on a product page. If discovery turns out to need help, `Page & Plate: Cookbook Scan` (28) is the
fallback — but try the clean name first and watch the numbers.

## Subtitle — 30 max

```
Scan cookbooks, plan, shop
```

Verb first, and the three things the app actually does. Indexed for search alongside the name, which is why
"scan", "cookbooks", "plan" and "shop" do not appear again in the keyword field.

## Promotional text — 170 max

Editable without shipping a build, so this is the field to change for a seasonal push.

```
Photograph a page from any cookbook. Page & Plate reads the ingredients, scales them to the portions you want, and sends the week's shopping straight to Reminders.
```

## Keywords — 100 max

Comma-separated, no spaces — a space costs a character and buys nothing. Nothing here repeats the name or
subtitle, which Apple already indexes.

```
recipe,ingredients,grocery,shopping,meal,planner,scale,portions,servings,cooking,baking,kitchen,ocr
```

## Description — 4000 max

```
You already own the cookbooks. Page & Plate is for cooking from them.

Photograph the ingredient list on the page. The app reads it — quantities, units, tins, ranges, "serves 4" — and shows you what it found so you can correct anything before it is saved. The method stays in the book, where it belongs; Page & Plate notes the book and page so you can find your way back.

SCALED PROPERLY

Recipe serves four and you are cooking for one? Every quantity follows, rounded the way a cook would round it. A quarter of a tin stays a quarter of a tin rather than turning into 100 grams. Half a teaspoon is half a teaspoon, not 0.375. Nothing is converted into units your book did not use, and "2 tbsp oil, for frying" does not shrink just because you are making less.

The arithmetic is done in code, not guessed by a model, and it is covered by tests.

PLAN THE WEEK

Put recipes on the days you will cook them. Each meal carries its own number of portions, so Monday for two and Thursday for six live happily in the same week. Move meals between days, reorder them, and see at a glance what you have already shopped for.

ONE SHOP

Tap Shop and the whole week becomes a single list in Apple Reminders. Lines that genuinely match — same ingredient, same unit, same tin size — are added together, so three recipes calling for onions give you one line. Everything else stays separate, because guessing that "red onion" and "onion" are the same thing is how you end up at the shop missing something. Staples you always have in are left unticked. Prefer to send it somewhere else? Share the list as plain text instead.

QUIET BY DESIGN

No account. No sign-in. Your recipes and photographs stay on your device. Page & Plate never reads, changes or deletes the reminders you already have — it only adds.

WHAT IT IS NOT

This is for books, not browsers. Page & Plate does not import recipes from websites or social media, and it does not store method text.

TRY IT FREE

Your first seven scans are free. A scan is one photographed recipe; a failed read does not count. A monthly or yearly subscription covers everything you cook in a week, and you can cancel any time from your Apple account settings.
```

## What's New — 4000 max (version 1.0)

```
First release.

Photograph a cookbook page, scale the recipe to the portions you want, plan the week, and send the whole shop to Reminders in one tap.
```

## In-app purchases

Both sit in the subscription group **Page & Plate**.

| Product | Display name (30) | Description (45) | UK price |
|---|---|---|---|
| `com.leonparsons.RecipeBasket.unlimited.monthly` | `Monthly` | `Scan and share, billed monthly` | £1.99 |
| `com.leonparsons.RecipeBasket.unlimited.yearly` | `Yearly` | `Scan and share, billed yearly` | £14.99 |

Prices confirmed 2026-09-28 and matching `ios/RecipeBasket.storekit`.

The product IDs keep the old working name. They are never shown to anyone, and changing them now would orphan
the existing StoreKit configuration.

---

## Featuring nomination

Submitted in App Store Connect under **App Launch**. Minimum two weeks' lead, but the editorial team plans
collections eight to twelve weeks out, so submit **about three months before the target date**. Needs an
Account Holder, Admin, App Manager or Marketing role.

### What's launching

```
Page & Plate turns a photographed cookbook page into a scaled ingredient list and a week's shopping.

Point it at the ingredient list on the page. It reads the quantities, units, tin sizes, ranges and the stated yield, and hands them back for a quick check before saving. Set the portions you actually want and every quantity follows — and it follows the way a cook thinks rather than the way a calculator does. A quarter of a 400g tin is shown as a quarter of a tin, because that is what you do in the kitchen. Half a teaspoon is half a teaspoon. Nothing is silently converted into units the book did not use.

From there, recipes go onto the days of a week, each meal at its own number of portions, and the whole week exports to Apple Reminders as one shopping list. Lines are only combined when they genuinely match — same ingredient, same unit, same package size — because a wrong merge sends you home without an onion.
```

### Why it is worth a look

```
It is built around one deliberate constraint: the model reads the page, and never does arithmetic. Every scaling, rounding and formatting decision happens in tested code, pinned to a suite of hand-checked fixtures. That is an unusual line to draw in an app that leans on a model, and it is the reason the numbers can be trusted — the interesting failure mode in this category is not a misread word, it is a confidently wrong quantity.

The design is drawn rather than assembled: a paper-and-ink palette, a serif display face, and a mark of a plate holding an open book, drawn in code so it stays sharp at every size. It is an app about printed books and it is meant to feel like one.

It is also deliberately small. No account, no sign-in, no library of other people's recipes to scroll. Your photographs and your recipes stay on your device, and the app never reads or changes the reminders you already have — it only adds to them.
```

### The story

```
I built this for my own kitchen. I cook from books rather than from the internet, and almost every Sunday I was doing the same tedious thing: working out what two thirds of a recipe for four looks like, writing the answers in the margin, and then copying a shopping list out by hand for whatever I had planned that week. The maths is not hard, it is just relentless, and it is exactly the kind of work a phone should absorb.

What I did not want was another app that wants my recipes. The books are the point. The app's job is to get out of the way between the page and the shop.
```

### Accessibility — verify before claiming

Do not paste this section until it is checked on a device. What is true today:

- All text uses Dynamic Type; the display face scales with it via `relativeTo:`.
- Every brand colour was chosen against measured contrast ratios rather than by eye — body and accent text
  clear 4.5:1 in both light and dark. The previous accent failed at 3.2:1, which is what prompted the change.
- Controls are standard SwiftUI, so VoiceOver and Voice Control get the system behaviour.

**Not yet verified:** a real VoiceOver pass, and layout at the largest accessibility text sizes. Claim neither
until you have sat with the phone and checked.

---

## Still outstanding

1. ~~Reserve **Page & Plate** in App Store Connect.~~ Done 2026-09-23, against the existing bundle id
   `com.leonparsons.RecipeBasket`. The hold lapses after 90 days without a build, so **6 January 2027**
   is the date a build has to exist by.
2. ~~Decide whether the plan keeps the name **Unlimited**.~~ Settled 2026-09-28: it does not. The word
   claimed a ceiling that exists and an unlimitedness that typed recipes now genuinely have. Nothing
   user-facing says it any more. Still reshoot frame 1: it reads "17 of 20 free scans left" from the old
   limits.
3. Real prices for both plans, and the two subscriptions created in App Store Connect with the product
   ids above.
4. Real terms and privacy URLs — `Subscription/Products.swift` still points at example.com.
5. ~~Screenshots.~~ Nine frames shot 2026-09-23; see `marketing/README.md` for what is still weak.
6. ~~A large-type pass.~~ Done 2026-09-23: Leon walked the recipe screen, export sheet, Settings, Review
   and the paywall on an iPad at the largest accessibility text size, and nothing broke. Code-side fixes
   landed the same day (see `docs/DECISIONS.md`).
   **Still open: a deliberate VoiceOver session.** The accessibility paragraph in the nomination claims
   VoiceOver support to Apple, so it stays marked do-not-send until someone has actually navigated the
   export sheet with it and confirmed each row announces "Ticked" / "Not ticked".
7. **Set `ALLOW_SANDBOX_ENTITLEMENTS` to `"false"` in `api/wrangler.jsonc` and redeploy.** It is `"true"`
   so that development and TestFlight purchases — which are always Sandbox transactions — verify at all.
   Left true in production, an Apple sandbox account is a free unlimited subscription. This is the last
   thing to flip before a public release, *after* TestFlight is finished with.
8. **App Attest switches, both in `api/wrangler.jsonc`.** `APPATTEST_DEVELOPMENT` must become `"false"`
   for any TestFlight or App Store build — a distributed build attests with a different aaguid, and every
   attestation is refused until this matches. `REQUIRE_ATTESTATION` must become `"true"` to actually close
   the hole it exists for, but only once every install in the wild has attested; before that it locks
   people out. Turn the first on with the build, the second a release later.
9. **Push the CloudKit schema to production.** It is created in the development environment on first run;
   a build shipped against it would sync into nothing. App Store Connect → the iCloud container →
   Deploy Schema Changes.
