import L from 'leaflet'

/**
 * Leaflet's default marker resolves its images relative to the CSS file, which
 * breaks under a bundler. Defining the icons inline as SVG data URIs avoids the
 * broken-image marker entirely and keeps the dashboard free of binary assets.
 */

const PIN_SVG = `
<svg xmlns="http://www.w3.org/2000/svg" width="26" height="38" viewBox="0 0 26 38">
  <path d="M13 0C5.8 0 0 5.8 0 13c0 9.2 13 25 13 25s13-15.8 13-25C26 5.8 20.2 0 13 0z"
        fill="#16191b"/>
  <circle cx="13" cy="13" r="5" fill="#ffffff"/>
</svg>`

export const pinIcon = L.icon({
  iconUrl: `data:image/svg+xml;base64,${btoa(PIN_SVG)}`,
  iconSize: [26, 38],
  iconAnchor: [13, 38],
  popupAnchor: [0, -34],
})

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

export function clusterIcon(count, band) {
  const spec = CLUSTER_BANDS.find((b) => b.band === band) ?? CLUSTER_BANDS[0]
  return L.divIcon({
    className: '',
    html: `<div class="cluster" style="
      width:${spec.size}px;height:${spec.size}px;
      background:${spec.fill};color:${spec.ink};
      font-size:${Math.round(spec.size * 0.34)}px;">${count}</div>`,
    iconSize: [spec.size, spec.size],
    iconAnchor: [spec.size / 2, spec.size / 2],
  })
}
