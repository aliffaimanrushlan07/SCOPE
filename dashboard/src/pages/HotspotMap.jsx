import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Map, useMap } from '@vis.gl/react-google-maps'
import { GoogleMapsOverlay } from '@deck.gl/google-maps'
import { LayerExtension } from '@deck.gl/core'
import { HeatmapLayer } from '@deck.gl/aggregation-layers'
import { ScatterplotLayer } from '@deck.gl/layers'
import * as api from '../api/endpoints'
import { errorMessage } from '../api/client'
import { ErrorState, InfoPopover, Loading, TopBar } from '../components/ui'
import { CLUSTER_BANDS } from '../components/clusterBands'

/**
 * Fades each cluster circle radially: solid at the centre, easing to fully
 * transparent at the rim. `geometry.uv` is the scatterplot's unit position, so
 * its length is 0 at the centre and 1 at the edge. The solid core (first 25%)
 * keeps the numeral readable.
 */
class RadialFade extends LayerExtension {
  getShaders() {
    return {
      inject: {
        'fs:DECKGL_FILTER_COLOR': `
          float rFade = length(geometry.uv);
          color.a *= 1.0 - smoothstep(0.25, 1.0, rFade);
        `,
      },
    }
  }
}

const KUALA_LUMPUR = { lat: 3.139, lng: 101.6869 }
const MAP_ID = import.meta.env.VITE_GOOGLE_MAPS_MAP_ID

/**
 * The ramp is derived from the section 10.4 cluster bands rather than picked
 * afresh, so the page keeps one palette and the density gradient inherits the
 * bands' monotonically decreasing lightness — still legible to a colour-blind
 * officer and still readable printed in black and white.
 *
 * The bands run fully saturated (bright yellow → orange → red-orange → deep
 * red) so frequency reads at a glance. A pale stop is prepended below band 1:
 * deck.gl interpolates across the whole range, and without it the thin edge of
 * every blob lands on saturated yellow, which makes a single scattered report
 * shout as loudly as a real cluster. The pale stop lets sparse areas fade out
 * instead.
 */
const rgb = (hex) => [
  parseInt(hex.slice(1, 3), 16),
  parseInt(hex.slice(3, 5), 16),
  parseInt(hex.slice(5, 7), 16),
]

const COLOR_RANGE = [[255, 247, 194], ...CLUSTER_BANDS.map((b) => rgb(b.fill))]

/**
 * The band a cluster's own count falls in. The API already sends `band`
 * alongside `count` (see the D03 clusters endpoint), so this is only the
 * fallback for a row that arrives without one — the band scale is defined in
 * one place and the two must not disagree.
 */
const bandFor = (cluster) =>
  CLUSTER_BANDS[(cluster.band ?? 1) - 1] ?? CLUSTER_BANDS[0]

/** Colour filter: one option per colour band, plus All. */
const COLOR_FILTERS = [
  { key: 'all', label: 'All', bands: [1, 2, 3, 4], dot: null },
  { key: 'yellow', label: 'Yellow', bands: [1], dot: CLUSTER_BANDS[0].fill },
  { key: 'orange', label: 'Orange', bands: [2], dot: CLUSTER_BANDS[1].fill },
  { key: 'red', label: 'Red (10–19)', bands: [3], dot: CLUSTER_BANDS[2].fill },
  { key: 'darkred', label: 'Dark red (20+)', bands: [4], dot: CLUSTER_BANDS[3].fill },
]

/** Width of the legend's swatch column — the largest swatch, so all four fit. */
const SWATCH_COLUMN = Math.max(...CLUSTER_BANDS.map((b) => b.size)) / 2.6

/**
 * D03 — Hotspot Map (FR09).
 *
 * Rendered as a density heatmap over Google Maps. Google removed
 * `google.maps.visualization.HeatmapLayer` from the Maps JavaScript API in
 * v3.65 (deprecated May 2025, unavailable May 2026) and it now throws on
 * construction, so the density layer is deck.gl's HeatmapLayer drawn through a
 * GoogleMapsOverlay — the replacement Google itself points to.
 *
 * The overlay is left in overlaid mode rather than interleaved: interleaved
 * mode composites into the vector map's own WebGL context, which the
 * screen-space aggregation layers do not reliably survive.
 *
 * Filters are period only. There is no violation type filter — the field was
 * removed from the data model — and no status filter, because no status exists.
 */
export default function HotspotMap() {
  const [days, setDays] = useState(365)
  const [allClusters, setClusters] = useState([])
  const [colorFilter, setColorFilter] = useState('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [hover, setHover] = useState(null)

  const load = useCallback(() => {
    setLoading(true)
    setError('')
    api
      .clusters({ days })
      .then(setClusters)
      .catch((err) => setError(errorMessage(err, 'Hotspot data could not be loaded.')))
      .finally(() => setLoading(false))
  }, [days])

  useEffect(load, [load])

  const clusters = useMemo(() => {
    const { bands } = COLOR_FILTERS.find((f) => f.key === colorFilter)
    return allClusters.filter((c) => bands.includes(c.band ?? 1))
  }, [allClusters, colorFilter])

  const total = clusters.reduce((sum, c) => sum + c.count, 0)

  /**
   * Three layers, and the division of labour between them is the whole point.
   *
   * The heatmap shows WHERE reports concentrate. Its colour cannot be read as a
   * count: it aggregates in screen space within `radiusPixels`, so the value
   * behind a pixel is a sum over neighbouring clusters, and under SUM
   * aggregation deck.gl rescales the colour domain by metres-per-pixel on every
   * zoom. The same orange therefore means different totals at different zooms.
   *
   * The circles carry the counts. Each one is coloured, sized and from
   * the cluster's OWN count via the section 10.4 band, so colour there does map
   * to a stated range — which is what the legend documents. Counts belong on
   * this layer and nowhere else, shown as a label on hover.
   *
   * Drawing order matters: the API returns clusters by count descending, so the
   * largest circles are drawn first and smaller ones land on top of them rather
   * than disappearing underneath.
   */
  const layers = useMemo(
    () => [
      new HeatmapLayer({
        id: 'hotspots',
        data: clusters,
        getPosition: (c) => [c.longitude, c.latitude],
        getWeight: (c) => c.count,
        colorRange: COLOR_RANGE,
        radiusPixels: 48,
        intensity: 1,
        threshold: 0.05,
        opacity: 0.75,
        pickable: false,
      }),
      new ScatterplotLayer({
        id: 'cluster-counts',
        data: clusters,
        getPosition: (c) => [c.longitude, c.latitude],
        getFillColor: (c) => [...rgb(bandFor(c).fill), bandFor(c).alpha ?? 255],
        extensions: [new RadialFade()],
        getRadius: (c) => bandFor(c).size / 2,
        radiusUnits: 'pixels',
        stroked: false,
        opacity: 0.95,
        pickable: true,
        onHover: (info) =>
          setHover(info.object ? { x: info.x, y: info.y, count: info.object.count } : null),
      }),
    ],
    [clusters],
  )

  return (
    <>
      <TopBar
        title="Hotspot Map"
        info={
          <InfoPopover>
            Shows where reports concentrate. Each circle is a cluster of nearby
            reports: its colour and size show how many (yellow 1–4, orange 5–9,
            red 10–19, dark red 20+), and hovering it shows the exact count. The
            glow behind is a relative density view. Use the colour buttons to
            filter clusters, the +/− buttons to zoom, and the period selector to
            change the date range.
          </InfoPopover>
        }
      >
        <PeriodSelect value={days} onChange={setDays} />
      </TopBar>

      <div className="page" style={{ padding: 12, gap: 10 }}>
        {loading ? (
          <Loading label="Loading hotspots…" />
        ) : error ? (
          <ErrorState message={error} onRetry={load} />
        ) : (
          <>
            <div className="card" style={{ padding: '8px 14px', display: 'flex', gap: 26, alignItems: 'center' }}>
              <Stat label="Clusters" value={clusters.length} />
              <Stat label="Reports plotted" value={total} />
              <div
                role="group"
                aria-label="Filter clusters by colour"
                style={{ marginLeft: 'auto', display: 'flex', gap: 6, alignItems: 'center' }}
              >
                {COLOR_FILTERS.map((f) => (
                  <button
                    key={f.key}
                    type="button"
                    aria-pressed={colorFilter === f.key}
                    onClick={() => {
                      setHover(null)
                      setColorFilter(f.key)
                    }}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 6,
                      padding: '6px 12px',
                      borderRadius: 999,
                      border: '1px solid var(--line)',
                      background: colorFilter === f.key ? '#16191b' : 'transparent',
                      color: colorFilter === f.key ? '#fff' : 'inherit',
                      fontSize: 12.5,
                      fontWeight: 600,
                      cursor: 'pointer',
                    }}
                  >
                    {f.dot && (
                      <span
                        aria-hidden="true"
                        style={{ width: 10, height: 10, borderRadius: '50%', background: f.dot }}
                      />
                    )}
                    {f.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden', position: 'relative' }}>
              <SizedMap layers={layers} />

              <Legend />

              {hover && (
                <div
                  role="tooltip"
                  style={{
                    position: 'absolute',
                    left: hover.x,
                    top: hover.y,
                    transform: 'translate(-50%, calc(-100% - 14px))',
                    zIndex: 1000,
                    pointerEvents: 'none',
                    padding: '5px 10px',
                    borderRadius: 6,
                    background: '#16191b',
                    color: '#fff',
                    fontSize: 12.5,
                    fontWeight: 600,
                    whiteSpace: 'nowrap',
                  }}
                >
                  {hover.count} {hover.count === 1 ? 'report' : 'reports'}
                </div>
              )}

              {clusters.length === 0 && (
                <div
                  style={{
                    position: 'absolute',
                    inset: 0,
                    display: 'grid',
                    placeItems: 'center',
                    pointerEvents: 'none',
                  }}
                >
                  <div className="card" style={{ padding: '14px 18px', fontSize: 14 }}>
                    No reports in this period.
                  </div>
                </div>
              )}
            </div>
          </>
        )}
      </div>
    </>
  )
}

/**
 * Google Maps latches its size at construction. Mounted into a container that
 * is still zero-width, it initialises degraded — it paints a narrow strip,
 * `getBounds()` stays null and `getRenderingType()` never leaves UNINITIALIZED,
 * and it does not recover when the container is later sized. deck.gl then
 * refuses to attach at all, because its `_createOverlay` returns early on an
 * UNINITIALIZED map and never retries. Measuring first and mounting the map
 * only once the box is real avoids the whole class of problem.
 */
function SizedMap({ layers }) {
  const ref = useRef(null)
  const [sized, setSized] = useState(false)

  useEffect(() => {
    const el = ref.current
    if (!el) return undefined

    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect
      if (width > 0 && height > 0) setSized(true)
    })
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  return (
    <div ref={ref} style={{ height: 'max(360px, calc(100vh - 175px))', width: '100%' }}>
      {sized && (
        <Map
          mapId={MAP_ID}
          defaultCenter={KUALA_LUMPUR}
          defaultZoom={12}
          gestureHandling="greedy"
          disableDefaultUI
          zoomControl={false}
          minZoom={MIN_ZOOM}
          maxZoom={MAX_ZOOM}
          style={{ height: '100%', width: '100%' }}
        >
          <DeckGLOverlay layers={layers} />
          <ZoomButtons />
        </Map>
      )}
    </div>
  )
}

/**
 * Custom +/- zoom buttons, replacing Google's default control so they match the
 * dashboard. One click is one zoom level (a doubling or halving of scale): fine
 * enough to keep your bearings, coarse enough to get from city to street in a
 * few clicks. The 10–19 range keeps the view between city-wide and street level.
 */
const MIN_ZOOM = 10
const MAX_ZOOM = 19

function ZoomButtons() {
  const map = useMap()
  const [zoom, setZoom] = useState(null)

  useEffect(() => {
    if (!map) return undefined
    setZoom(map.getZoom() ?? null)
    const l = map.addListener('zoom_changed', () => setZoom(map.getZoom() ?? null))
    return () => l.remove()
  }, [map])

  const step = (delta) => {
    if (!map || zoom == null) return
    map.setZoom(Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, Math.round(zoom) + delta)))
  }

  const btn = (label, aria, delta, disabled) => (
    <button
      type="button"
      aria-label={aria}
      disabled={disabled}
      onClick={() => step(delta)}
      style={{
        width: 36,
        height: 36,
        fontSize: 20,
        fontWeight: 600,
        lineHeight: 1,
        border: 'none',
        background: 'transparent',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.35 : 1,
      }}
    >
      {label}
    </button>
  )

  return (
    <div
      className="card"
      style={{
        position: 'absolute',
        top: 16,
        right: 16,
        zIndex: 1000,
        display: 'flex',
        flexDirection: 'column',
        padding: 0,
        overflow: 'hidden',
      }}
    >
      {btn('+', 'Zoom in', 1, zoom != null && zoom >= MAX_ZOOM)}
      <div style={{ height: 1, background: 'var(--line)' }} />
      {btn('−', 'Zoom out', -1, zoom != null && zoom <= MIN_ZOOM)}
    </div>
  )
}

/**
 * deck.gl is imperative, so the overlay is attached by hand.
 *
 * The attach is deferred until the map reports a rendering type. deck.gl's
 * `_createOverlay` returns early and never retries when it is handed a map
 * still reporting UNINITIALIZED, which leaves the overlay silently unattached
 * — the map renders, the heatmap simply never appears. `useMap()` hands us the
 * instance well before Google has settled that, so attaching on the first
 * effect loses the race. Waiting for `renderingtype_changed` (with an `idle`
 * fallback for the case where the type was already settled and the event never
 * fires) also guarantees the projection is live, which the overlay's draw path
 * dereferences without a null check.
 */
function DeckGLOverlay({ layers }) {
  const map = useMap()
  const [overlay, setOverlay] = useState(null)

  useEffect(() => {
    if (!map) return undefined

    let instance = null

    const attach = () => {
      if (instance) return
      if (map.getRenderingType() === google.maps.RenderingType.UNINITIALIZED) return
      instance = new GoogleMapsOverlay({ interleaved: false })
      instance.setMap(map)
      setOverlay(instance)
    }

    attach()
    const listeners = [
      map.addListener('renderingtype_changed', attach),
      google.maps.event.addListenerOnce(map, 'idle', attach),
    ]

    return () => {
      listeners.forEach((l) => l.remove())
      if (instance) instance.finalize()
      setOverlay(null)
    }
  }, [map])

  useEffect(() => {
    if (overlay) overlay.setProps({ layers })
  }, [overlay, layers])

  return null
}

/**
 * The legend documents what the CIRCLES mean, because they are the only thing
 * on this map whose colour maps to a stated number of reports. It deliberately
 * does not put counts against the heatmap gradient: that colour is relative and
 * zoom-dependent (see the layer comments), so a numeric key there would be
 * wrong. The glow gets one honest line of prose instead.
 *
 * Swatch diameters are the band sizes scaled down, so the legend shows the
 * size encoding too — the same redundancy the map relies on.
 */
function Legend() {
  return (
    <div
      className="card"
      style={{
        position: 'absolute',
        right: 16,
        bottom: 26,
        zIndex: 1000,
        padding: '12px 14px',
        fontSize: 12.5,
        maxWidth: 210,
      }}
    >
      <div style={{ fontWeight: 650, marginBottom: 9 }}>Reports per cluster</div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
        {CLUSTER_BANDS.map((b) => (
          <div key={b.band} style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
            {/* Fixed-width column so the swatches stay centred on one axis and
                the labels line up, despite each swatch being a different size. */}
            <span
              aria-hidden="true"
              style={{
                flex: `0 0 ${SWATCH_COLUMN}px`,
                display: 'grid',
                placeItems: 'center',
              }}
            >
              <span
                style={{
                  width: b.size / 2.6,
                  height: b.size / 2.6,
                  borderRadius: '50%',
                  background: `radial-gradient(circle, ${b.fill} 25%, transparent 100%)`,
                  opacity: (b.alpha ?? 255) / 255,
                }}
              />
            </span>
            <span>
              {b.label} {b.band === 1 ? 'reports' : ''}
            </span>
          </div>
        ))}
      </div>

      <div
        className="muted"
        style={{ marginTop: 10, paddingTop: 9, borderTop: '1px solid var(--line)', lineHeight: 1.4 }}
      >
        The glow behind the circles shows where reports concentrate. Its shade is
        relative to the current view, so hover a circle to read its count.
      </div>
    </div>
  )
}

export function PeriodSelect({ value, onChange }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(Number(e.target.value))}
      style={{
        padding: '8px 11px',
        border: '1px solid var(--line)',
        borderRadius: 8,
        background: 'var(--white)',
      }}
    >
      <option value={7}>Last 7 days</option>
      <option value={30}>Last 30 days</option>
      <option value={90}>Last 90 days</option>
      <option value={365}>Last 12 months</option>
    </select>
  )
}

function Stat({ label, value }) {
  return (
    <div>
      <div className="muted" style={{ fontSize: 12 }}>
        {label}
      </div>
      <div style={{ fontSize: 22, fontWeight: 650 }}>{value}</div>
    </div>
  )
}
