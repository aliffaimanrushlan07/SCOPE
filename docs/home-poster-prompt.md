# Poster prompt for Home (S02)

Home used to carry a three-slide carousel previewing the awareness
infographics. It now carries one bundled poster: `mobile/assets/poster/home-poster.png`,
drawn by `_HomePoster` in `mobile/lib/screens/s02_home.dart`. The three
infographics themselves are unchanged and still live in the Awareness Hub (S04).

This file is the copy-paste prompt for Claude Design to draw a replacement
poster, plus the arithmetic behind its size so it can be rechecked when the
layout changes.

## Where the size comes from

| What | Value | Source |
| --- | --- | --- |
| Poster height | 190 logical px, fixed | `SizedBox(height: 190)` in `_HomePoster` |
| Poster width | screen width − 32 | `EdgeInsets.symmetric(horizontal: Gap.md)` on the Home scroll view |
| Corner radius | 16, hard-clipped | `ClipRRect` in `_HomePoster` |
| Scaling | `BoxFit.cover` — overflow is cropped, never letterboxed | `_HomePoster` |

The width tracks the device, so one poster cannot match every phone pixel for
pixel. It can match every phone's *aspect ratio* to within a few per cent,
which is what `BoxFit.cover` actually cares about:

| Device width (dp) | Poster box | Aspect |
| --- | --- | --- |
| 360 (common Android) | 328 × 190 | 1.726 |
| 375 (iPhone SE / mini) | 343 × 190 | 1.805 |
| 390 (iPhone 13–15) | 358 × 190 | 1.884 |
| 393 (Pixel 7/8) | 361 × 190 | 1.900 |
| 412 (large Android) | 380 × 190 | 2.000 |
| 430 (iPhone Pro Max) | 398 × 190 | 2.095 |

**Canvas: 1200 × 630 px** (aspect 1.905). It sits in the middle of that range,
so the worst crop on any listed phone is ~9%, and it is just over 3× the
largest box, so the downscale stays crisp.

Worst-case crop, and therefore the safe zone:

- At 1.726 (narrowest) the sides lose **56 px each**.
- At 2.095 (widest) the top and bottom lose **29 px each**.

Unlike the carousel this replaced, nothing is drawn on top of the poster — the
carousel's dark caption gradient went with it. The poster owns its full canvas
and is expected to carry its own wording.

## The prompt

```text
Design a poster image for the Home screen of SCOPE, a Malaysian
public-reporting mobile app for smoking violations. It is the only piece of
artwork on that screen, sitting between the app's logo header and three
navigation buttons, above a large MAKE A REPORT button.

CANVAS — these numbers are exact, do not round or "improve" them.
- Exactly 1200 × 630 px, landscape, aspect ratio 1.905:1.
- Opaque background, full bleed, sRGB. No transparency, no drop shadow
  outside the canvas, no mockup frame, no device bezel, no margin of white
  around the artwork.
- The app clips the image to a 16 px corner radius and scales it with
  BoxFit.cover, so the canvas edge is cropped, never letterboxed. Draw the
  background to all four edges.

SAFE ZONE — the app crops differently on every phone. Anything outside this
box may be cut off on some devices.
- Keep all text, icons, logos and load-bearing graphics inside the box from
  x = 80 to x = 1120 and y = 56 to y = 574.
- Decoration may bleed outside it — that is the right place for anything
  that can be cropped without losing meaning.
- Keep the four corners clear of content; they are rounded off.

TYPOGRAPHY — the poster is displayed at roughly 30% of its pixel size, in a
strip 190 px tall on a phone.
- Minimum type size anywhere on the canvas: 46 px. Nothing smaller, ever,
  including credits or footnotes.
- Headline: 90–130 px, bold.
- Supporting text: 46–60 px.
- Word count on the whole poster: at most 20 words. It must read in under
  two seconds while scrolling past.
- Use Inter (Google Fonts) or, failing that, a clean grotesque sans. No
  script, no condensed, no display faces.
- Every text-on-background pair must clear 4.5:1 contrast (3:1 for text
  above 24 px bold). State the ratios you used.

DO NOT draw the word SCOPE or the SCOPE logo into the poster. The app's own
logo header sits directly above it; repeating the mark reads as a mistake.

BRAND — use only these colours.
- Deep chrome #0B2F2C (full-bleed dark backgrounds)
- Primary teal #115E59 (the app's button and accent colour)
- Mark teal #0D9488 (shapes, rules and large bold numerals only — it is
  3.85:1 on the chrome, so it fails AA for body text)
- Off-white surface #F2F4F3, pure white #FFFFFF
- Ink #17211F, muted ink #5A6663
- Alert red #B3261E, amber #E65100, green #2E7D32 — sparingly, for state
A light tint of the mark teal is acceptable for on-dark supporting text
where #0D9488 would fail contrast; say which hex you used.

Flat, geometric, restrained. This is an official reporting tool used by a
member of the public who may be standing near the person they are
reporting — it should read as civic signage, not as a consumer app
promotion. No photographs of identifiable people, no stock-photo look, no
gradients-on-gradients, no 3D renders, no emoji, no glow effects.

DIAGRAMS — prefer one clear diagram or icon sequence over a block of text.
Line weight at least 8 px so it survives the downscale.

CONTENT — use ONLY the facts in the FACTS block below. Do not invent,
extrapolate or "fill in" statistics, percentages, fine amounts, section
numbers, act names or dates. If a fact you want is not in the block, leave
it out and say in your reply what you left out and why.

FACTS:
- SCOPE lets a member of the public report a smoking violation from their
  phone. A report carries a photo, a location and a timestamp.
- <add any further verified facts here, or delete this line>

IF THE POSTER ANIMATES
- Deliver a still frame as well, as a separate PNG at the same 1200 x 630.
  Home shows the still one when the device has "reduce motion" turned on,
  because a loop with no pause control is a WCAG 2.2.2 failure otherwise.
- The poster must make full sense as that still frame. Motion may draw the
  eye; it may not carry meaning of its own.
- Keep the moving region small and inside the safe zone, and keep the loop
  under two seconds.

DELIVERABLE
- A single self-contained HTML artifact.
- The poster itself is one inline <svg> with viewBox="0 0 1200 630" and
  width="1200" height="630" — vector, no raster images embedded, no external
  asset URLs.
- Below it, a "Download PNG" button that draws the SVG onto a 1200 × 630
  canvas and downloads it as home-poster.png. The exported file must be
  exactly 1200 × 630 px.
- Under that, a preview strip showing the SVG cropped to 328 × 190,
  358 × 190 and 398 × 190 with object-fit: cover and a 16 px radius, so the
  three worst-case phone crops can be checked at a glance.
- Do not add a caption, watermark, or your own signature to the poster.
```

Note the `FACTS` clause. A poster that states a fine amount or a health
statistic is making a legal or medical claim on behalf of the app, and a
generated one will look entirely plausible while being wrong.

## Installing the result

The poster is bundled, not uploaded — there is no admin control for it, and
changing it means shipping a build. Both files live in
`mobile/assets/poster/`, and because `pubspec.yaml` declares the directory
rather than each file, dropping them in is the whole job.

```sh
# from the repo root
cp ~/Downloads/<your-poster>.webp mobile/assets/poster/home-poster.webp
cp ~/Downloads/<your-still>.png   mobile/assets/poster/home-poster-still.png
```

The filenames are referenced by `_HomePoster`, so either keep them or change
both places together. A static poster needs only the first file — point the
widget at it and drop the reduced-motion branch.

Then hot restart (`R`, not `r`: Flutter caches decoded images) and check it on
a narrow device (a 360 dp Android) and a wide one (a Pro Max), the two ends of
the crop range in the table above.

## What is installed

| File | What it is |
| --- | --- |
| `home-poster.webp` | The poster. 1200 x 630, four frames at 350 ms, looping indefinitely. The motion is a camera reticle and a smoke plume in a 342 x 126 patch at +666,+78 — inside the safe zone. |
| `home-poster-still.png` | Its first frame, flattened to PNG8. Shown when the device asks for reduced motion. |

Pixel-art diner scene: a chalkboard reading "Nampak orang merokok? / Ambil
gambar & lapor. / Snap it & report it.", a seated smoker under a camera
reticle, and an officer photographing them. Both worst-case crops — 1.726 and
2.095 — keep the whole chalkboard, all four lines and both figures.

It departs from the prompt above in three ways, all deliberate choices by
whoever commissioned it rather than mistakes:

- **It animates.** The prompt asked for a static poster. This is why
  `_HomePoster` has a reduced-motion branch at all, and why the prompt now
  carries an `IF THE POSTER ANIMATES` clause.
- **Pixel art, and more words than the 20-word ceiling** — four lines,
  bilingual Malay and English. The smallest line measures about 40 px on the
  canvas against the 46 px floor the prompt sets, so it renders at roughly
  12 logical px on a 390 dp phone: legible, but the tightest thing on Home.
- **Roughly the bottom 40% is empty floor**, so the composition sits high in
  the 190 px band.

Pixel art is arguably more on-brand than the prompt's flat-geometric brief
suggests — the SCOPE mark is itself pixel art on a 32-unit grid, as
`brand/README.md` explains. If this style is now the house look for Home, the
BRAND paragraph in the prompt should say so rather than being contradicted by
the artwork sitting next to it.
