# App Store listing — Page & Plate

Everything to paste into App Store Connect, plus the featuring nomination. Character counts are checked by
`docs/appstore-counts.py`; run it after any edit here.

**Where it stands (2026-10-04):** version 1.0 is built, uploaded and submitted, and App Review has asked for
more information under Guideline 2.1. That is item 18 below, which also records the two App Store Connect gaps
the request turned up: the Paid Apps Agreement waiting on banking, and the subscriptions not submitted with the
version. The rest of the App Store Connect side is in: both subscriptions at their real prices with Billing
Grace Period on, the age rating and App Privacy answers, and the live terms and privacy URLs that
`Subscription/Products.swift` points at.

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
| `Pageandplatemonthly` | `Monthly` | `Scan and share a plan, billed monthly` | £1.99 |
| `Pageandplateyearly` | `Yearly` | `Scan and share a plan, billed yearly` | £19.99 |

Prices confirmed 2026-09-28 and matching `ios/RecipeBasket.storekit`.

**The product IDs are `Pageandplatemonthly` and `Pageandplateyearly`** (2026-10-07), because that is what App
Store Connect holds. When the plans were created, the intended `com.leonparsons.RecipeBasket.unlimited.monthly` and
`.yearly` went into the **Reference Name** field and these into **Product ID**, and a product ID can never be edited
or reused. The app asked for IDs that did not exist, so StoreKit returned nothing and the paywall said
"Subscription Unavailable". The code now follows App Store Connect in three places that must agree:
`Subscription/Products.swift`, `ios/RecipeBasket.storekit`, and `PRODUCT_IDS` in `api/src/app.ts`. The Worker
refuses a purchase of any other product. Nobody ever sees a product ID, so the odd shape costs nothing; the
reference names can be tidied to "Monthly" and "Yearly" at any time, since that field is editable.

## App Review notes — 4000 max

Pasted into **App Store Connect → the version → App Review Information → Notes**, and since 2026-10-04 also the
**reply** to App Review's Guideline 2.1 request (item 18). It answers that request's six questions in Apple's own
numbering, and Apple asked for the same answers in both places. Not visible to customers, editable at any time.
Apple's limit for Notes is 4000 **bytes**, not characters (App Store Connect Help, checked 2026-09-29), and the
reply box takes 4000 characters, so this block is deliberately plain ASCII — no en dashes, curly quotes or
ellipsis characters, which cost two or three bytes each and would make `appstore-counts.py` disagree with the form.

It began because **a reviewer cannot reach the household on their own**, and the listing leads with it. They have
one Apple Account, a household needs two, hosting is behind the subscription, and `HouseholdDemoSeed` is
`#if DEBUG`, so the build they receive has no demo household. The second recording (**App Review screen
recording**, below) is what shows them the member's side.

```
Answers to the Guideline 2.1 questions, numbered as asked; also our reply. We are resubmitting 1.0 with its two subscriptions, which the first submission lacked.

1. SCREEN RECORDINGS
Two recordings of the submitted build from TestFlight, attached to our reply and in App Review Information:
- Recording 1, iPhone 17 Pro, iOS 27.0.1, from launch: scanning, review, scaling, the week, shopping to Reminders, typing a recipe in, subscribing, sharing a household.
- Recording 2, a second iPhone and Apple Account: accepting the invite, editing the shared week, leaving.
Accounts: none. No registration, no login, nothing to delete.
Shared content: nothing is public. A household is iCloud sharing with people the host invites; nobody else can join. No profiles, feeds, messages or search. Members see the week, meal notes, recipe titles and ingredients, each person's chosen name and a 240-pixel page thumbnail. The host can remove anyone or stop sharing, and anyone can leave; both recordings show it.
Paid: scanning after 7 free scans, and hosting a household.

2. PURPOSE AND AUDIENCE
For adults who cook from cookbooks they own, and their households. The recipe serves four; the cook is feeding one, or six. The app reads a photographed page's ingredients and yield, the user checks them, and every quantity scales to the portions wanted. A week of recipes becomes one shopping list in Apple Reminders, planned together by the household. Nothing is aimed at children.

3. SETUP
No setup or credentials needed.
Sample pages, recipes we wrote: https://leonparsons.github.io/Page-and-Plate/review/ - save one to Photos, then Recipes > + > Scan a recipe > Choose photos > Extract.
- Recipes tab: + > Scan a recipe, or Type one in (free, unlimited, no scan spent). Ingredients are always shown for review before Save.
- A recipe: "I want" scales it; More (...) > Add to plan.
- Plan tab: the week; Shop sends it to Reminders, or Share as text.
- Settings: the gear at the top of either tab, or in its (...) menu.
Subscription: 7 free scans per device, then GBP 1.99 a month or GBP 19.99 a year (Settings > Subscribe...). Typing recipes never needs it. Subscribers have a fair-use ceiling of 25 scans in any rolling 7 days, against automated abuse. It is far above real cooking and not shown to users as a number, so nothing calls the subscription unlimited.
Household: needs iCloud. Hosting needs the subscription; joining is free. With one account: subscribe, fill in Settings > Your household > Your name, tap "Share with your household..." for Apple's invite sheet. Accepting needs a second account and device: see recording 2, or ask us for a live demonstration.

4. EXTERNAL SERVICES
- Google Gemini API (Gemini 3.8 Flash) reads the ingredients from the page photo; Anthropic Claude API (Claude Sonnet 5) is the fallback if Gemini fails. Only our proxy calls them, only when the user taps Extract. We never store or log images, and neither provider trains on them.
- Cloudflare Workers runs that proxy; Cloudflare KV keeps per-device scan counts.
- Apple: StoreKit (subscriptions; the only payment processor), iCloud and CloudKit (sync and household sharing, in users' own iCloud), App Attest, EventKit (Reminders), VisionKit (scanner).
No sign-in, analytics, advertising or tracking services.

5. REGIONS
United Kingdom only; please test purchases with a UK sandbox account. Every feature works the same throughout; English only.

6. REGULATION AND THIRD-PARTY MATERIAL
Not a regulated industry. The app contains and downloads no third-party content: no recipes, cookbook text or images. Users photograph books they own, for their own use. It keeps the ingredients, yield, title and page number, never the method. Page photos stay on the device and in the user's own iCloud; household members see only the 240-pixel thumbnail, too small to read. Every recipe in our screenshots and sample pages was written by us, and the recordings scan one of the sample pages.
```

**The fair-use paragraph stays** (Leon, 2026-09-29). Rule 9b keeps the 25-in-7-days ceiling from the user — in
the app and in the Worker's error body — and it still does; a reviewer is not a user. App Review reads a
subscription's description as a claim, so a ceiling they find for themselves, on a subscription whose listing
says it covers the week's cooking, is a misleading-subscription rejection. Disclosed here it costs nothing;
found there it costs a submission. **This is not a licence to soften rule 9b anywhere else** — App Review
Information is not a user-facing surface, and nothing in the app or the Worker learned a number from it.

**The household is not user-generated content** (2026-10-04), in the sense Guideline 1.2 uses: filtering,
reporting and blocking exist for content that reaches people who did not choose it. A household is private
iCloud sharing with the people its host invites — `CloudSharingSheet` offers `.allowPrivate` only, so an invite
works for the person it was sent to and nobody else. There are no profiles, feeds, messages or search. The
controls a household does have are removal (the host, through Apple's sharing sheet) and leaving (any member),
so the answer names them and both recordings show them. If App Review reads it differently it will say so, and
a way to report a shared recipe or meal note is the likely ask.

**Also before submitting:** `ALLOW_SANDBOX_ENTITLEMENTS` must still be `"true"` in `api/wrangler.jsonc`.
Every App Review purchase is a Sandbox transaction and `api/src/entitlement.ts` refuses one when the flag is
false, so a reviewer would subscribe and then be told they had no scans left after 7 — see item 7, which reads
"before public release" and means *after approval*, not before review.

## App Review screen recording

App Review asked for one on 2026-10-04 (item 18), and the answer above promises it, so this is the script. Record
on a physical iPhone on the **latest iOS**, starting on the Home Screen, with **the build you will submit,
installed from TestFlight**. Since 2026-10-07 that is a new build carrying the real product IDs, not the one first
submitted. An Xcode build would use the development CloudKit environment and the local StoreKit file, so it would
not be the app App Review has.

### Before recording

- **The paywall works in TestFlight.** Settings → Subscribe… lists Monthly £1.99 and Yearly £19.99. "Subscription
  Unavailable — the subscription is unavailable in the current storefront" means the App Store returned no
  products. Check, in order: the Paid Apps Agreement is Active (Business → Agreements; it is not while banking is
  processing); both plans have a review screenshot under Review Information, without which App Store Connect will
  not put them in a submission and the sandbox may not offer them; and any Sandbox Apple Account signed in on the
  phone (Settings → Developer) is in the United Kingdom. A Debug build installed with `devicectl` answers the last
  one directly: Settings → **Check the App Store (debug)** shows the storefront the phone is shopping in and what
  came back for both plan IDs.
- **Fresh free scans.** The trial is kept in the Keychain, which survives deleting the app and is shared by Xcode
  and TestFlight builds. The Worker counts against the phone's attested key, or its device id. So a phone used for
  development has none left, and "Reset scans (debug)" alone does not help. To start over:
  1. Install a Debug build with `devicectl`.
  2. Turn on Airplane Mode, so the development build does no CloudKit work against the store.
  3. Open Settings → **Start over as a new device (debug)**, which forgets the tally, the device id and the
     attested key. Then force-quit.
  4. Turn Airplane Mode off and reinstall from TestFlight.

  Settings then reads "7 of 7 free scans left", and the first scan attests a fresh production key. Do not scan
  again before recording: every scan spends one.
- **Not subscribed**, so the purchase can be shown: Settings says **Subscribe…**. A TestFlight subscription renews
  daily, at most six times. Cancel an old one under Manage subscription. A lapse ends any household the phone
  hosts on that build, by design.
- **A second phone and a second Apple Account**, on the same build. That person is an internal TestFlight tester:
  an App Store Connect user with the Developer or Marketing role, added to the internal group.
- **The CloudKit production schema** has `SharedRecipe`, `SharedMeal`, `SharedMember` and the `CD_` types, or the
  household does nothing (CloudKit Console → Deploy Schema Changes).
- Do Not Disturb on both phones. Print the page-88 sample. Settings → Show welcome screen, then swipe the app
  away, so the recording opens on the welcome screen.

### Recording 1 — the host's iPhone

1. Home Screen → tap the icon → welcome → **Get started**.
2. Recipes → + → **Scan a recipe** ("7 of 7 free scans left") → Book "Page & Plate samples", Page 88 → **Scan
   pages** → the printed page → **Extract 1 page**.
3. Review: scroll the rows, correct one, **Save**.
4. **I want** 1: the tomatoes become ¼ tin and the oil for frying "doesn't scale". More (…) → **Add to plan…** →
   a day.
5. Plan: **Add meal** on another day; swipe → **Move**.
6. **Shop**: allow Reminders, pick a list (staples unticked), add. Show the list in Reminders, then come back.
7. Recipes → + → **Type one in** → **Save**. No scan is spent.
8. Settings → **Subscribe…** → Monthly → buy. Then "Enough for the week", Restore purchases, Manage subscription.
9. Your household → **Your name** → **Share with your household…** → invite the second phone by Messages.
10. Once the second phone has added a meal: Plan shows "Added by …". Then Settings → the member's row → **Manage
    your household…** → the member → **Remove Access** (cancel), and **Stop sharing and take the plan back**
    (cancel). Do this before the member leaves.

### Recording 2 — the member's iPhone

1. Home Screen → Messages → tap the invite. The app opens on the host's week.
2. Settings → **Your name**.
3. Plan → **Add meal** → one of the host's recipes → a day.
4. Settings → Your plans → swipe the host's plan → **Leave** → confirm.

### Sending it

AirDrop both recordings to the Mac and watch them through for notifications or anything private. If a file is too
large to attach, use QuickTime → Export As → 1080p, or `avconvert --preset Preset1920x1080 --source in.MOV
--output out.mp4`. Then:

1. App Store Connect → App Review → the submission with App Review's message → **Resolve** → **Reply to App
   Review**: paste the notes block, attach both recordings, and Reply.
2. On the same submission, hold the pointer over **iOS App 1.0** and click the delete button (–). It is the
   submission's only item, so the submission moves to Completed. That is why the reply comes first: App Review's
   message thread goes with it.
3. On the version page (iOS App 1.0), choose the new build under **Build**, paste the same block into App Review
   Information → Notes, put the recordings under Attachment, and Save. Then click **Add for Review** and choose
   the existing draft that holds the subscription group and both plans.
4. App Review → that draft: it should list iOS App 1.0, the group, Monthly and Yearly. Click **Submit for
   Review**.

The version has to go to the plans, not the other way round. Since 15 July 2026, subscriptions go to review from
Monetization → Subscriptions → **Add for Review**, which puts them in a draft submission. A first subscription
has to share a submission with an app version, and a submission with Unresolved Issues takes no new items (App
Store Connect Help, "Manage a submission with unresolved issues").

If the iOS version differs from the block's "iOS 27.0.1", change the block first.

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
   ~~**One thing left:** `legal/index.html` is also the **Support URL** and carried no contact route of its
   own.~~ Done 2026-10-02: it opens with a Support heading and the email.
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
8. **App Attest switches, both in `api/wrangler.jsonc`.** ~~`APPATTEST_DEVELOPMENT` must become `"false"`
   for any TestFlight or App Store build.~~ Done and deployed 2026-10-02, before the first upload. TestFlight
   and App Store builds attest in production whatever the entitlement says. A build run from Xcode is now
   refused when it attests a new key, and scans unattested. `REQUIRE_ATTESTATION` must become `"true"` to actually close
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
    **App Review notes** above, counted by `appstore-counts.py` against Apple's 4000-*byte* limit. Rewritten
    2026-10-04 as the answer to App Review's 2.1 request, with the fair-use paragraph kept: see item 18.
11. ~~**Age rating questionnaire and the App Privacy answers**~~ Both answered 2026-09-29 (Leon), "Data Not
    Collected" throughout — the app has no accounts, and CloudKit private and shared databases are not
    developer collection. These were the two that block a submission outright.
12. ~~**Gemini goes live with the next Worker deploy.**~~ Done 2026-10-02 (Leon): secret set, policy published,
    deployed, a scan verified from his phone, and a Google Cloud budget alert in place. The steps are kept for a
    redeploy from scratch (2026-10-02: Gemini 3.8 Flash reads the page, Claude Sonnet 5 is the backup; see
    `docs/DECISIONS.md`). Deploying the config without step 2 refuses every scan as `server_misconfigured`.
    1. In Google AI Studio, check that the project behind `GEMINI_API_KEY` has **billing enabled** (paid tier).
       The free tier lets Google train on users' pages, and Google's terms allow only paid use for users in the
       UK, the EEA or Switzerland.
    2. Set the secret from `api/`, piped from `.dev.vars` so it is never pasted or shown:
       `grep '^GEMINI_API_KEY=' .dev.vars | cut -d= -f2- | tr -d '\n' | npx wrangler secret put GEMINI_API_KEY`.
       `ANTHROPIC_API_KEY` stays: it is the backup now.
    3. Merge to `main` and push, so GitHub Pages publishes the privacy policy that names Google and Anthropic.
       The policy promises a change is published before it takes effect.
    4. `npm run deploy`, then `curl https://recipe-basket-api.recipe-basket-api.workers.dev/health` should
       answer `gemini-3.8-flash` with `claude-sonnet-5` behind it. Scan one page from the phone.
    5. Put a **budget alert** on the Google Cloud billing account, alongside the Anthropic Console's spend limit.
13. **The App Privacy answers stay "Data Not Collected"; nothing to change in App Store Connect.** Apple's
    "collect" covers the developer and its "third-party partners", which Apple defines as vendors whose code is
    in the app. Gemini and Claude are called from the Worker, which keeps nothing. That is Leon's reading
    (2026-10-02), not a ruling: revisit it if Apple's wording changes or a reviewer asks.
14. **The App Review notes name the AI services.** Their PRIVACY paragraph above says which, and when a photo
    is sent. Guideline 5.1.2(i) asks for disclosure and explicit permission before personal data goes to
    third-party AI. Leon decided on 2026-10-02
    to ship without an in-app consent step. If App Review cites 5.1.2(i), the fix is a one-time sheet before the
    first Extract that names both services and links the privacy policy.
15. **Google's terms bar apps "likely to be accessed by" under-18s.** Leon judged on 2026-10-02 that Page &
    Plate is not one. Keep the listing, the screenshots and the age-rating answers consistent with that: nothing
    aimed at children. If that ever changes, Gemini has to go. Anthropic allows apps that serve minors,
    provided they add safeguards.
16. **Gemini 3.8 Flash's price doubles on 1 January 2027**, from $0.75 / $3.75 to $1.50 / $7.50 per million
    tokens: about 0.75¢ a scan becomes about 1.5¢, against about 2.1¢ for Sonnet at low effort. Update
    `PRICING` in `api/src/eval/metrics.ts` that day, and weigh whether the saving still pays for a second
    provider.
17. ~~**A privacy manifest.**~~ Added 2026-10-02: `ios/RecipeBasket/PrivacyInfo.xcprivacy`. App Store Connect
    refuses an upload whose code calls a required-reason API without declaring why (ITMS-91053), and the app
    uses `UserDefaults` (reason `CA92.1`, its own data only). No tracking and no collected data, matching
    item 11. Any new required-reason API needs an entry there before it ships.
18. **App Review asked for more information (Guideline 2.1, 2026-10-04).** It is the standard request for a new
    developer account. Apple wants a screen recording from launch on a physical device on the latest iOS, the
    app's purpose and audience, setup and sample files, the external services, any regional differences, and
    any regulated or third-party material. The answers go in a reply and in Notes.
    - The answer is the **App Review notes** block above, which doubles as the reply.
    - The recording is scripted under **App Review screen recording**.
    - The sample pages are `review/`, served at `https://leonparsons.github.io/Page-and-Plate/review/`. They are
      the three `marketing/pages/` recipes, rendered by `html2png.swift`.

    The TestFlight build showed two gaps on the way, and either one would have failed the review itself:
    - **The paywall read "Subscription Unavailable".** The Paid Apps Agreement was not Active, because the
      banking details were still processing (App Store Connect said about 24 hours from 2026-10-04). The
      sandbox, which is TestFlight and App Review alike, returns no products until it is Active.
    - **The two subscriptions were never submitted with 1.0.** App Store Connect showed "Unable to Submit for
      Review: new subscription groups must be submitted with an auto-renewable subscription from within that
      group". Since 15 July 2026 they go to review from Monetization → Subscriptions → Add for Review, which
      first refused them for want of a review screenshot each (taken from the simulator, which shows the local
      StoreKit prices) and then put them in a new draft. They could not join 1.0, whose submission has Unresolved
      Issues and so takes no new items. 1.0 has to move into their draft instead (**Sending it**, above).

    - **With both of those fixed, the paywall still read "Subscription Unavailable".** Check the App Store (debug)
      showed "Storefront: USA" and no plans. The sandbox tester signed in on the phone had the United States as its
      region, which is the default for a new tester, and the app is sold only in the UK. The fix is
      to change the tester's Country or Region to the United Kingdom (Users and Access → Sandbox), then sign out
      and back in on the phone. A reviewer on a US sandbox account would hit the same wall, so the answer's
      Regions item now asks App Review to buy with a UK sandbox account.
    - **With the storefront fixed, still nothing came back, because the IDs did not exist.** App Store Connect had
      the product ID and reference name swapped (see **In-app purchases**, above), so the app had always asked
      for two products App Store Connect did not have. No waiting could have fixed it. The code switched to the
      real IDs on 2026-10-07, and the submitted build, which has the old ones compiled in, is replaced by a new
      one.

    Leon's phone also had no free scans left in TestFlight, from development. **Start over as a new device
    (debug)** in Settings is the fix.

    Still to do, in order:
    1. ~~The agreement shows Active.~~ Done 2026-10-04.
    2. ~~Both plans complete, and in a draft submission.~~ Done 2026-10-04.
    3. A new build with the real IDs is uploaded and chosen for 1.0, and the Worker deployed with them.
    4. TestFlight's paywall lists £1.99 and £19.99.
    5. Record.
    6. Send it in the order under **App Review screen recording → Sending it**: reply first, then move 1.0, with the new
       build, into the plans' draft and submit.
