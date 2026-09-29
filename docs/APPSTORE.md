# App Store listing — Page & Plate

Everything to paste into App Store Connect, plus the featuring nomination. Character counts are checked by
`docs/appstore-counts.py`; run it after any edit here.

**Before this goes live:** as of 2026-09-29 the App Store Connect side is set up — both subscriptions exist
at their real prices with Billing Grace Period on, the age rating and App Privacy answers are in, and the
terms and privacy URLs are live and pointed at by `Subscription/Products.swift`. **What is left is a build:**
nothing has ever been archived or uploaded, and that one step gates TestFlight, the App Attest switch and the
CloudKit production schema.

**The listing now sells the household** (11c-iii). Every length-limited field was written before sharing
existed and pitched scanning alone — which stopped being the whole story when typed recipes became free and
unlimited. `python3 docs/appstore-counts.py` passes; it caught the promotional text and the keywords going over
on the first attempt, which is what it is for.

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
Scan cookbooks, plan together
```

Verb first. "Together" is the word doing the new work: sharing is what the subscription buys and the reason
somebody picks this over a notes app. Indexed for search alongside the name, which is why "scan", "cookbooks"
and "plan" do not appear again in the keyword field.

## Promotional text — 170 max

Editable without shipping a build, so this is the field to change for a seasonal push.

```
Photograph a page from any cookbook. Page & Plate reads the ingredients, scales them to the portions you want, and shops for the week — planned with your household.
```

## Keywords — 100 max

Comma-separated, no spaces — a space costs a character and buys nothing. Nothing here repeats the name or
subtitle, which Apple already indexes.

```
recipe,ingredients,grocery,shopping,meal,planner,portions,servings,family,household,partner,share
```

## Description — 4000 max

```
You already own the cookbooks. Page & Plate is for cooking from them.

Photograph the page. The app reads it — quantities, units, tins, ranges, "serves 4" — and shows you what it found so you can correct anything before it is saved. The method stays in the book, where it belongs; Page & Plate notes the book and page so you can find your way back.

SCALED PROPERLY

Recipe serves four and you are cooking for one? Every quantity follows, rounded the way a cook would round it. A quarter of a tin stays a quarter of a tin rather than turning into 100 grams. Half a teaspoon is half a teaspoon, not 0.375. Nothing is converted into units your book did not use, and "2 tbsp oil, for frying" does not shrink just because you are making less.

The arithmetic is done in code, not guessed by a model, and it is covered by tests.

PLAN THE WEEK

Put recipes on the days you will cook them. Each meal carries its own number of portions, so Monday for two and Thursday for six live happily in the same week. Move meals between days, reorder them, and see at a glance what you have already shopped for. Start the week on the day you shop, whichever day that is.

Leave a note on a meal — who is out, who is coming — so the portions make sense to everyone looking.

COOK TOGETHER

Share the week with your household and everyone sees the same plan: partner, kids, whoever is cooking on Thursday. Anyone can add a meal, change the portions, move it to another day or take it off.

Everyone's recipes go into the household, so you cook from each other's books. A recipe belongs to whoever scanned it and leaves with them if they go — nobody loses a library they built.

What the others see is the week, the titles and the ingredients. They never see your photographs of the page.

ONE SHOP

Tap Shop and the whole week becomes a single list in Apple Reminders. Lines that genuinely match — same ingredient, same unit, same tin size — are added together, so three recipes calling for onions give you one line. Everything else stays separate, because guessing that "red onion" and "onion" are the same thing is how you end up at the shop missing something. Staples you always have in are left unticked. Prefer to send it somewhere else? Share the list as plain text instead.

QUIET BY DESIGN

No account. No sign-in. Your recipes and photographs stay on your device and in your own iCloud. Sharing uses your Apple Account and nobody else's servers — we never hold a copy. Page & Plate never reads, changes or deletes the reminders you already have; it only adds.

WHAT IT IS NOT

This is for books, not browsers. Page & Plate does not import recipes from websites or social media, and it does not store method text.

TRY IT FREE

Your first seven scans are free. A scan is one photographed recipe; a failed read does not count. You can also type a recipe in yourself, as many as you like, without a subscription.

A monthly or yearly subscription covers everything you cook in a week and lets you share a plan with your household. Cancel any time from your Apple account settings.
```

## What's New — 4000 max (version 1.0)

```
First release.

Photograph a cookbook page, scale the recipe to the portions you want, plan the week, and send the whole shop to Reminders in one tap. Share the week with your household and cook from each other's books.
```

## In-app purchases

Both sit in the subscription group **Page & Plate**.

| Product | Display name (30) | Description (45) | UK price |
|---|---|---|---|
| `com.leonparsons.RecipeBasket.unlimited.monthly` | `Monthly` | `Scan and share a plan, billed monthly` | £1.99 |
| `com.leonparsons.RecipeBasket.unlimited.yearly` | `Yearly` | `Scan and share a plan, billed yearly` | £19.99 |

Prices confirmed 2026-09-28 and matching `ios/RecipeBasket.storekit`.

The product IDs keep the old working name. They are never shown to anyone, and changing them now would orphan
the existing StoreKit configuration.

## App Review notes — 4000 max

Pasted into **App Store Connect → the version → App Review Information → Notes** at submission. Not visible to
customers, editable at any time. Apple's limit is 4000 **bytes**, not characters (App Store Connect Help,
checked 2026-09-29), so this block is deliberately plain ASCII — no en dashes, curly quotes or ellipsis
characters, which cost two or three bytes each and would make `appstore-counts.py` disagree with the form.

It exists because **a reviewer cannot reach the household on their own** and the listing leads with it. They
have one Apple Account; a household needs two, hosting is behind the subscription, and `HouseholdDemoSeed` —
the thing that made marketing frame 5 possible — is `#if DEBUG`, so there is no demo household in the build
they receive. Unexplained, that is a paywall in front of the headline feature with no way to finish the
journey: a plausible rejection rather than an unfair one.

```
Page & Plate turns a photograph of a cookbook page into a scaled ingredient list, plans a week of meals, and sends the whole shop to Reminders.

There is no account and no sign-in anywhere in the app, so there are no credentials to give you. Everything below works on a fresh install.

WHAT NEEDS NO SETUP

On "My recipes", the + menu offers "Scan a recipe" (photograph any recipe page) and "Type one in" (enter one by hand, which is free and unlimited and useful if no cookbook is nearby). Extracted ingredients are always shown for confirmation before anything is saved. Scale the portions on the recipe screen, add meals to days on the Week tab, then export to Reminders.

Settings is in the toolbar overflow menu ("...") on "My recipes".

SCANS AND THE SUBSCRIPTION

The first 7 scans on a device are free. After that, scanning needs the subscription (GBP 1.99 monthly or GBP 19.99 yearly). Typing a recipe in never spends a scan and never needs the subscription.

Subscribers also have a fair-use ceiling of 25 scans in any rolling 7 days, which exists to stop automated abuse of the extraction service. It is well above real cooking use and is not presented to users as a number, which is why nothing in the app or the listing calls the subscription "unlimited".

THE HOUSEHOLD, AND WHY ONE ACCOUNT CANNOT SEE ALL OF IT

A household is CloudKit sharing of the user's own data: one week that everyone edits, and a catalogue that is the union of everyone's recipes. It needs iCloud signed in on the device. Without it, Settings shows "Not signed in" and there is no household.

Hosting a household requires the subscription. Joining one is free, deliberately: one person subscribes and their household cooks from it.

With a single Apple Account you can reach everything up to acceptance:

1. Settings, then "Subscribe...", and buy either plan.
2. In Settings, under "Your household", fill in "Your name". iOS 17 removed the API that told apps a user's name, so the app asks for it; it is what the household sees beside a shared recipe.
3. Tap "Share with your household...". Apple's own share sheet opens with a real invite link.

That exercises hosting, the share and the invite. Accepting the invite needs a second Apple Account on a second device, and there is no demo or mock household in a release build, so the member side cannot be simulated for you. If you would like to see it, please email the contact address above and we will arrange a demonstration or provide a second test account.

PERMISSIONS

Reminders: requested the first time a shopping list is exported, and used only to add reminders. The app never reads, changes or deletes anything already in Reminders.

Camera: the document scanner, for photographing a page. Photo library: optional, for a page already photographed.

PRIVACY

No accounts, no analytics, no tracking, no advertising. Recipes, page photos and the week are kept in the user's own private iCloud database, and a shared household week in the shared CloudKit database. Never on our servers. A page photo is sent to our extraction proxy, which passes it to an AI model and returns the ingredients; images are not stored or logged.

Thank you for reviewing.
```

**The fair-use paragraph stays** (Leon, 2026-09-29). Rule 9b keeps the 25-in-7-days ceiling from the user — in
the app and in the Worker's error body — and it still does; a reviewer is not a user. App Review reads a
subscription's description as a claim, so a ceiling they find for themselves, on a subscription whose listing
says it covers the week's cooking, is a misleading-subscription rejection. Disclosed here it costs nothing;
found there it costs a submission. **This is not a licence to soften rule 9b anywhere else** — App Review
Information is not a user-facing surface, and nothing in the app or the Worker learned a number from it.

**Also before submitting:** `ALLOW_SANDBOX_ENTITLEMENTS` must still be `"true"` in `api/wrangler.jsonc`.
Every App Review purchase is a Sandbox transaction and `api/src/entitlement.ts` refuses one when the flag is
false, so a reviewer would subscribe and then be told they had no scans left after 7 — see item 7, which reads
"before public release" and means *after approval*, not before review.

---

## Featuring nomination

Submitted in App Store Connect under nomination type **App Launch**. Needs an Account Holder, Admin, App
Manager or Marketing role.

**Checked against Apple's own documentation 2026-09-29, and the shape of this section changed as a result.**
It previously held three long essays under invented headings; the real form is a 60-character name, a
1,000-character description and a 500-character "Helpful Details" box, plus structured fields. The old copy
ran to about 3,150 characters across fields that take 1,500, so it could not have been pasted in. Apple
documents a **minimum lead time of three weeks** and asks for plans "as early as possible"; the "eight to
twelve weeks" figure this section used to quote is not in Apple's documentation and is not repeated here.
`python3 docs/appstore-counts.py` now counts these three fields too.

### Nomination name — 60 max

Only to recognise the nomination later; Apple's editorial team does not read it as a pitch.

```
Page & Plate 1.0 launch — cookbook scanning
```

### Nomination description — 1000 max

The pitch. Leads with what the app does in one line, because an editor reads a great many of these.

```
Page & Plate turns a photographed cookbook page into a scaled ingredient list and a week's shopping.

Photograph the page. It reads the quantities, units, tin sizes, ranges and the stated yield, and hands them back to check before saving. Set the portions you want and every quantity follows — rounded the way a cook rounds, not the way a calculator does. A quarter of a 400g tin stays a quarter of a tin. Half a teaspoon stays half a teaspoon. Nothing is converted into units the book never used.

Recipes go onto the days of a week, each meal at its own portions, and the whole week exports to Apple Reminders as one shopping list. Lines are combined only when they genuinely match — same ingredient, same unit, same tin size — because a wrong merge sends you home without an onion.

A household shares one week and cooks from each other's books, carried over the members' own iCloud accounts. No accounts of ours, no sign-in, no library of other people's recipes.
```

### Helpful details — 500 max

Apple asks here for what makes the app stand out: the unique approach, or what went on behind it. **It is the
one field written in a person's voice** — the description has already said what the app does, and an editor
reading a great many of these is looking for the reason it exists. So this one is the kitchen it came from,
and the technical constraint is left to earn its place as the *answer* to that problem rather than as a boast
about the build. Rewritten 2026-09-29 (Leon): the previous version led with the constraint and put the person
in a closing line, which had it the wrong way round.

```
Built by one person, for his own kitchen. He owned the cookbooks and rarely cooked from them: every recipe served four, he cooked for one, and each week meant halving at the counter and copying the list out by hand. The books stayed shut.

So the arithmetic is the part this app takes seriously. The model only reads the page; every sum is done in tested code, against fixtures checked by hand. A misread word a cook catches. A wrong quantity gets all the way home from the shop.
```

The mark being drawn in code, and the paper-and-ink palette, are gone from this field on purpose — both are
visible in the screenshots and the supplemental URL, and neither is worth the characters the origin needs.

### The structured fields

| Field | Value |
|---|---|
| Nomination type | App Launch (cannot be edited after submission) |
| Related apps | Page & Plate's Apple ID, from App Store Connect |
| Platforms | iOS (iPhone), iOS (iPad) |
| Publish date | The release date, at least three weeks out |
| Relevant countries or regions | GBR at minimum — widen it if the release does |
| Localization | en-GB |
| Launching in certain markets first? | Answer honestly; a UK-only start is a "Yes" |
| New In-App Event? | No |
| Pre-order? | No |
| Supplemental materials | https://leonparsons.github.io/Page-and-Plate/ (up to 5 URLs) |

### Accessibility — verify before claiming

**What this actually gates: nothing in the submission.** No accessibility claim is made anywhere in the
listing or the nomination today — **Helpful details** is the origin story and the arithmetic, and at 479 of 500
characters it has no room for one. So the VoiceOver session does not block submitting, and does not block the
nomination either. It gates *adding* the claim, and the better reason to do it is the app.

What is true today, and safe to say:

- All text uses Dynamic Type; the display face scales with it via `relativeTo:`.
- Every brand colour was chosen against measured contrast ratios rather than by eye — body and accent text
  clear 4.5:1 in both light and dark. The previous accent failed at 3.2:1, which is what prompted the change.
- Controls are standard SwiftUI, so VoiceOver and Voice Control get the system behaviour.
- Large type was walked on a real iPad at the largest accessibility size (2026-09-23) and nothing broke.

**Parked, deliberately** (Leon, 2026-09-29). The five code-visible faults were fixed; the device session was
not done and is not planned. Nothing needs it: no field claims accessibility, so there is nothing unverified
being said to Apple. **The rule that matters is the one below — claim it only after sitting with the phone.**
The script is kept because it is cheap to keep, not because it is owed.

#### The mechanical half — Accessibility Inspector, on the simulator

Xcode → Open Developer Tool → Accessibility Inspector, point it at the simulator, run its audit on each
screen. It finds unlabelled elements, small hit regions, clipped text and contrast failures without anyone
having to hear anything, and it runs where the household cannot: the simulator has no iCloud.

The same checks exist as `XCUIApplication.performAccessibilityAudit(for:)` (iOS 17, Xcode 15; types
`contrast`, `elementDetection`, `hitRegion`, `sufficientElementDescription`, `dynamicType`, `textClipped`,
`trait`). **There is no UI test target** — `ios/project.yml` has only `RecipeBasketTests`
(`bundle.unit-test`) — so this would mean a new `bundle.ui-testing` target and a regenerate. Worth it only if
the audit is to run on every change rather than once.

#### The half that needs a human — VoiceOver, on a phone

Settings → Accessibility → VoiceOver, and set Accessibility Shortcut to VoiceOver first so a triple-click of
the side button gets out of it. Swipe right to advance, double-tap to activate, two-finger swipe up to read
from the top. The household screens need a real phone anyway (no iCloud on the simulator); **`Seed demo
household (debug)` in Settings** covers the shared week without a second person, but the plans list and the
member rows need a real share, because the member rows read `share?.participants`.

Walk these, and write down what is actually said:

1. **Export sheet** — the one item 6 named. Each row should be a single element: label "flour, 200g, staple",
   value "Ticked" / "Not ticked", hint "Double tap to leave out". Listen for the tick **and** `.isSelected`
   double-announcing ("Selected… Ticked"), which is the likely flaw, not a missing label.
2. **The list picker** inside it — fixed 2026-09-29; the tick is hidden and the row carries `.isSelected`.
   The list in use should say "Selected"; the others should not.
3. **Recipe form, pages column** (iPad width) — fixed 2026-09-29; it was an `.onTapGesture`, invisible to
   VoiceOver, so the page could be seen and never opened. Now a Button: each page should say "Page 1 photo,
   Button" and open the viewer on a double-tap. **Check this on an iPad**, which is the only place the
   column renders.
4. **`PageThumbnail`** — fixed 2026-09-29; decorative in the component now, so it should be skipped
   everywhere it appears, except where a container labels it (`HomeView`, `PageThumbnailStrip`).
5. **Ingredient rows** in the recipe form — a `.plain` Button round `IngredientRowView` plus a chevron. Does
   it say "Button", and is it clear a double-tap edits?
6. **Star rating** — container `.contain`, label "Rated 3 of 5", value "3 stars", each star its own button
   ("Rate 4 stars", "Clear rating"). Check a rating can actually be **set**, not just read.
7. **Planner rows** — combined, so listen for the order: title, "for 4", "Has a note", "Added to Reminders".
8. **Shared week, unavailable row** — should read "Chickpea arrabbiata. Recipe not available, so it can't be
   cooked or shopped for." Check the swipe action "Remove" is offered through the Actions rotor.
9. **Plans list** (`SharePlanSection.planRow`) — fixed 2026-09-29; it said "Showing, Selected". Should now
   be "My plan, You share this one, Selected, Button", once.
10. **Member rows** (`SharePlanSection`) — fixed 2026-09-29; combined now, so a member should be one stop:
    "Sara, 3 recipes, 2 in your plan". Needs a real share — the debug seed does not fabricate participants.
11. **Welcome screen and the app mark** — decorative art is `accessibilityHidden(true)`; confirm nothing
    reads as "Image".

**Items 2, 3, 4, 9 and 10 were fixed on 2026-09-29** — they were visible in the code and needed no device to
believe, so the session verifies them rather than finding them. Everything else here is still open, and the
ones only ears settle are order, redundancy, and whether the tick in the export sheet is discoverable at all.
Items 9 and 10 need a phone in a real household. Then say only what was walked.

---

## Still outstanding

1. ~~Reserve **Page & Plate** in App Store Connect.~~ Done 2026-09-23, against the existing bundle id
   `com.leonparsons.RecipeBasket`. The hold lapses after 90 days without a build, so **6 January 2027**
   is the date a build has to exist by.
2. ~~Decide whether the plan keeps the name **Unlimited**.~~ Settled 2026-09-28: it does not. The word
   claimed a ceiling that exists and an unlimitedness that typed recipes now genuinely have. Nothing
   user-facing says it any more. Still reshoot frame 1: it reads "17 of 20 free scans left" from the old
   limits.
3. ~~Real prices for both plans, and the two subscriptions created in App Store Connect with the product
   ids above.~~ Done 2026-09-29 (Leon): both products exist at £1.99 monthly and £19.99 yearly, and
   **Billing Grace Period is on** — the real protection for a household, since `atRisk` is only the backstop.
   A build has still never been uploaded, so none of this has been exercised against a real purchase yet;
   that happens on the first TestFlight pass.
4. ~~Real terms and privacy URLs.~~ Written 2026-09-28 and living in `legal/` in this repository, served by
   GitHub Pages at `https://leonparsons.github.io/Page-and-Plate/legal/` — versioned alongside the behaviour
   they describe, because a privacy policy that drifts from the app is worse than none.
   Pushed and Pages turned on 2026-09-28; all three URLs verified returning 200 the same day.
   **One thing left:** `legal/index.html` links to both pages but carries no contact route of its own, and it
   is also the **Support URL**. A reviewer landing there should see the email without clicking through.
5. ~~Screenshots.~~ Nine frames, **reshot 2026-09-29** against the current copy and the current limits — the
   2026-09-23 set showed "17 of 20 free scans left" and the capture help text that was reversed the same day.
   Three of them now prove their headline in the picture rather than near it. See `marketing/README.md`.
   ~~**Still missing: a household frame**, which the listing now leads with.~~ Shot 2026-09-29 and now
   **frame 5 of seven**, "Cook together" — the shared week with "Added by Sara" on two meals and the reader's
   own on a third. A simulator cannot host a household, so the app seeds one: `HouseholdDemoSeed` (`#if DEBUG`)
   writes the same rows the sync engine writes, projected from this device's own library. That also means the
   frame can be **reshot whenever copy changes**, which a frame needing two phones and two Apple Accounts
   could not. See `marketing/README.md`.
6. ~~A large-type pass.~~ Done 2026-09-23: Leon walked the recipe screen, export sheet, Settings, Review
   and the paywall on an iPad at the largest accessibility text size, and nothing broke. Code-side fixes
   landed the same day (see `docs/DECISIONS.md`).
   ~~**A deliberate VoiceOver session.**~~ **Parked 2026-09-29, and not a blocker** — which the earlier
   wording here got wrong. It said the nomination claims VoiceOver support; it does not. No accessibility
   claim is made in any field, and **Helpful details** is 479 of 500 characters, so there is no room for one
   without cutting what is there. The session gates *adding* the claim, and there are five things worth
   fixing in the app either way, and those five were fixed the same day. The script is kept under
   **Accessibility — verify before claiming** above if it is ever wanted; the only live rule is that no
   accessibility claim goes into any field until someone has sat with the phone.
7. **Set `ALLOW_SANDBOX_ENTITLEMENTS` to `"false"` in `api/wrangler.jsonc` and redeploy.** It is `"true"`
   so that development and TestFlight purchases — which are always Sandbox transactions — verify at all.
   Left true in production, an Apple sandbox account is a free unlimited subscription. This is the last
   thing to flip before a public release, *after* TestFlight is finished with.
8. **App Attest switches, both in `api/wrangler.jsonc`.** `APPATTEST_DEVELOPMENT` must become `"false"`
   for any TestFlight or App Store build — a distributed build attests with a different aaguid, and every
   attestation is refused until this matches. `REQUIRE_ATTESTATION` must become `"true"` to actually close
   the hole it exists for, but only once every install in the wild has attested; before that it locks
   people out. Turn the first on with the build, the second a release later.
   **"Before a public release" means after approval, not before review.** Every App Review purchase is a
   Sandbox transaction, so with `ALLOW_SANDBOX_ENTITLEMENTS` already false the reviewer's own subscription is
   refused by the Worker and they run out of scans after 7 while paying — and the same is true of every future
   update's review, which is the real argument for leaving it true for good and closing the hole with
   `REQUIRE_ATTESTATION` instead.
9. **Push the CloudKit schema to production.** It is created in the development environment on first run;
   a build shipped against it would sync into nothing. App Store Connect → the iCloud container →
   Deploy Schema Changes. The schema has grown a lot since it was last looked at —
   `SharedMember`, `SharedMeal.note` and `systemFields` on both shared types — so deploy after the final build
   is made, not before.
10. ~~**App Review notes explaining how to test sharing.**~~ Drafted 2026-09-29 and living in
    **App Review notes** above, counted by `appstore-counts.py` against Apple's 4000-*byte* limit.
    **Still to do:** paste it into App Store Connect at submission (App Review Information → Notes), fill in
    the contact name, email and phone beside it, and decide whether the fair-use paragraph stays — the
    section says why it is there and why it is a judgement call.
11. ~~**Age rating questionnaire and the App Privacy answers**~~ Both answered 2026-09-29 (Leon), "Data Not
    Collected" throughout — the app has no accounts, and CloudKit private and shared databases are not
    developer collection. These were the two that block a submission outright.
