# Eval photos

Real cookbook pages photographed on an iPhone (1500 × 2000, JPEG), personal use only — remove before any public release of this repository.

- `<stem>.jpg` — an ingredients page. Its hand-checked extraction lives at `fixtures/expected/<stem>.json`.
- `negatives/<stem>-photo-page.jpg` — the facing photo page of the same recipe: no ingredient list (some show a sliver of cut-off text). The eval expects `no_recipe_found` / `unreadable` for these; they are not part of the recall / exact-match figures.

| Stem | Book style | Yield | Lines |
|---|---|---|---|
| fish-filo-parcel-and-beans | "7 a day" (green) | Serves 4 | 10 |
| golden-chicken-peppers-and-rice | "7 a day" | Serves 2 | 9 |
| smashed-flatbread-burger | "7 a day" | Serves 1 | 7 |
| chickpea-arrabbiata | "7 a day" | Serves 1 | 7 |
| beef-rendang | LEON curry (two sections) | Serves 4 | 22 |
| gym-bunny-curry | LEON curry | Serves 4 | 15 |
| chicken-chettinad | LEON curry (two sections) | Serves 4 | 23 |
| nilgiri-curry | LEON curry | Serves 4 | 21 |
| easy-salmon-en-croute | 5-ingredients style (margin photos, nutrition table) | Serves 4 | 8 |
| cauli-chicken-pot-pie | 5-ingredients style | Serves 4 | 8 |
| keema-pau | Bombay café book ("To serve" section) | Serves 3–4 | 21 |
| salli-boti | Bombay café book (sub-recipe page refs) | Serves 4–6 | 17 |
| phaldari-kofta | Bombay café book (two sections, "Continued overleaf") | Serves 4 generously | 20 |
| lamb-boti-kabab | Bombay café book (three sections) | Serves 4–6 | 18 |
| gulab-jamun | Bombay café book (five sections) | Serves 14–16 | 10 |
| cheese-and-masala-sticks | Bombay café book (yield with no noun) | Makes 16–20 | 6 |
| kejriwal | Bombay café book ("1 or 2" ranges) | Serves 1 | 8 |
| pot-roasted-poussins-agro-dolce | blue side-column book (knobs, wineglasses, slices) | serves 4 | 14 |
| squid-with-black-pudding-stuffing | blue side-column book (dual units, alternatives) | serves 4 | 14 |
| potato-rosti | blue side-column book | serves 4 | 7 |
| black-angel-tagliarini | blue side-column book (one line with an alternative, split three ways) | serves 4 | 13 |
| proper-blokes-sausage-fusilli | blue side-column book | serves 4 | 13 |
| bacon-wrapped-chicken-with-orzo | supermarket recipe card (packs, branded lines) | Serves 2 | 7 |

298 ingredient lines in total (entries after splitting "salt and pepper" / "1 teaspoon each cumin and coriander seeds" / "2 whole green chillies, plus an extra 10g").

The 13 pages from keema-pau down were shot as HEIC on 2026-10-02 and converted with `sips` to 1500 × 2000 JPEG, since `sharp` cannot decode HEIC. Their expected files were drafted by Opus 5 and hand-checked; IMG_2176 was a second shot of the salli-boti page and is not used.
