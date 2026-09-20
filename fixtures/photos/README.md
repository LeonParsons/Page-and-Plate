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

130 ingredient lines in total (entries after splitting "salt and pepper" / "1 teaspoon each cumin and coriander seeds").
