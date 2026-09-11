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
 * Count is encoded THREE ways at once: diameter, fill colour and the numeral
 * inside. The redundancy is deliberate — it keeps the map readable for
 * colour-blind officers and survives black-and-white printing of the report,
 * because lightness decreases monotonically across the four bands.
 */
export const CLUSTER_BANDS = [
  { band: 1, label: '1 – 4', fill: '#FFD166', ink: '#3A2E12', size: 36 },
  { band: 2, label: '5 – 9', fill: '#F4A259', ink: '#33220F', size: 46 },
  { band: 3, label: '10 – 19', fill: '#E76F51', ink: '#FFFFFF', size: 58 },
  { band: 4, label: '20 +', fill: '#B33F2B', ink: '#FFFFFF', size: 72 },
]
