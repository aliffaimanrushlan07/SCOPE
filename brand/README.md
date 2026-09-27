# SCOPE brand artwork

Source artwork for the app and dashboard icons. Everything under `mobile/`
and `dashboard/` that carries the brand is generated from these files.

| File | What it is |
| --- | --- |
| `scope-icon.*` | The bare mark: a magnifying glass over a lit cigarette. 32-unit grid. |
| `scope-app-icon.*` | The mark on a rounded white tile with a mint border, for launcher icons. 36-unit grid. |
| `scope-logo-horizontal.*` | Mark and wordmark side by side. |
| `scope-logo-stacked.*` | Mark above the wordmark. Used for the Flutter splash. |
| `scope-wordmark.svg` | SCOPE lettering alone. |
| `sheet.png` | Contact sheet showing the set together. |

## Generate from the PNGs, not the SVGs

The PNG exports are the source of truth. This is not the usual advice, so
it is worth being explicit about why.

These SVGs are pixel art: each art pixel is its own one-unit `<rect>`, about
1240 of them per lockup. ImageMagick's renderer scales those inconsistently.
Rendering `scope-logo-stacked.svg` draws the wordmark band at 1/16 scale,
leaving 432 pixels of `#0D9488` where a correct render has 110,592 — the
wordmark silently vanishes. The mark alone comes out with 17.7% of its pixels
wrong.

The exports are pixel-exact: 16-18 unique colours, against the 655-706 a
resampled render produces. So:

- **Do not** rasterise these SVGs with ImageMagick. Check any other
  rasteriser against an export before trusting it.
- Scale only by **integer multiples** through a nearest-neighbour filter, or
  the pixel grid turns to mush. `-filter point` in ImageMagick.
- The exports bake the background to white. For transparency, flood-fill
  inward from a one-pixel border; the mark's interior white is not connected
  to the outside, so it survives.

## Regenerating the app icons

Replace the six files in `mobile/assets/branding/`, then let the project's
own tooling produce every native size:

```sh
cd mobile
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

That rewrites the Android `mipmap-*` and `drawable-*` sets, all 22 iOS
`AppIcon` sizes, and the launch images. Do not hand-edit those.

The Android adaptive foreground needs the mark at roughly 56% of its canvas
so it clears the 66% safe zone; the 192px export at 3x gives exactly the
576px-in-1024px that the current `app_icon_foreground.png` uses.

## Known gap

There is no white knockout variant. `scope_mark_white.png` in both apps is a
copy of the colour mark, which stays legible on the navy chrome but is not a
true on-dark treatment. If one is ever drawn, point `ScopeLogo(onDark: true)`
and the dashboard's `scopeMarkWhite` import at it.
