/**
 * How the two map screens draw their data: the D05 location pin and the D03
 * band scale.
 *
 * The pin is an inline SVG data URI rather than a file, which spares the
 * dashboard a binary asset and any question of how a bundler resolves its
 * path.
 */

const PIN_SVG = `
<svg xmlns="http://www.w3.org/2000/svg" width="26" height="38" viewBox="0 0 26 38">
  <path d="M13 0C5.8 0 0 5.8 0 13c0 9.2 13 25 13 25s13-15.8 13-25C26 5.8 20.2 0 13 0z"
        fill="#16191b"/>
  <circle cx="13" cy="13" r="5" fill="#ffffff"/>
</svg>`

/**
 * The pin as a plain data URI plus its geometry, rather than a Leaflet icon
 * object. PIN_ICON_ANCHOR is the pin's point — the tip that has to sit on the
 * coordinate rather than beside it — stated next to the artwork that defines
 * it so the marker does not inherit whatever anchoring a map library happens
 * to default to.
 */
export const PIN_ICON_URL = `data:image/svg+xml;base64,${btoa(PIN_SVG)}`
export const PIN_ICON_SIZE = { width: 26, height: 38 }
export const PIN_ICON_ANCHOR = { x: 13, y: 38 }

/**
 * D03 cluster scale — section 10.4.
 *
 * A bright thermal ramp: saturated yellow through orange and red-orange to a
 * deep red at the top. The high saturation is the point — an officer scanning
 * the map should see where the reports concentrate without reading the legend
 * first.
 *
 * Count is still encoded THREE ways at once: diameter, fill colour and the
 * numeral inside. The redundancy keeps the map readable for colour-blind
 * officers and survives black-and-white printing of the report, because
 * relative luminance still decreases monotonically across the four bands
 * (0.75 → 0.39 → 0.24 → 0.12) even though every step is now fully saturated.
 *
 * Inks are dark on bands 1–3 and white on band 4; each clears WCAG AA for
 * normal text on its own fill (9.9:1, 6.9:1, 5.1:1, 6.2:1).
 */
export const CLUSTER_BANDS = [
  { band: 1, label: '1 – 4', fill: '#FFE01B', ink: '#3D2F05', size: 26, alpha: 130 },
  { band: 2, label: '5 – 9', fill: '#FF8A00', ink: '#331A00', size: 46 },
  { band: 3, label: '10 – 19', fill: '#FF3B14', ink: '#2B0C02', size: 58 },
  { band: 4, label: '20 +', fill: '#C1121F', ink: '#FFFFFF', size: 72 },
]
