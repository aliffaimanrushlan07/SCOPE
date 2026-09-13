import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Map, useMap } from '@vis.gl/react-google-maps'
import { GoogleMapsOverlay } from '@deck.gl/google-maps'
import { HeatmapLayer } from '@deck.gl/aggregation-layers'
import * as api from '../api/endpoints'
import { errorMessage } from '../api/client'
import { ErrorState, Loading, TopBar } from '../components/ui'
import { CLUSTER_BANDS } from '../components/clusterBands'

const KUALA_LUMPUR = { lat: 3.139, lng: 101.6869 }
const MAP_ID = import.meta.env.VITE_GOOGLE_MAPS_MAP_ID

/**
 * The ramp is derived from the section 10.4 cluster bands rather than picked
 * afresh, so the page keeps one palette and the density gradient inherits the
 * bands' monotonically decreasing lightness — still legible to a colour-blind
 * officer and still readable printed in black and white.
 */
const rgb = (hex) => [
  parseInt(hex.slice(1, 3), 16),
  parseInt(hex.slice(3, 5), 16),
  parseInt(hex.slice(5, 7), 16),
]

const COLOR_RANGE = [[255, 241, 209], ...CLUSTER_BANDS.map((b) => rgb(b.fill))]

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
  const [clusters, setClusters] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

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

  const total = clusters.reduce((sum, c) => sum + c.count, 0)

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
    ],
    [clusters],
  )

  return (
    <>
      <TopBar title="Hotspot Map">
        <PeriodSelect value={days} onChange={setDays} />
      </TopBar>

      <div className="page">
        {loading ? (
          <Loading label="Loading hotspots…" />
        ) : error ? (
          <ErrorState message={error} onRetry={load} />
        ) : (
          <>
            <div className="card" style={{ padding: 14, display: 'flex', gap: 26 }}>
              <Stat label="Clusters" value={clusters.length} />
              <Stat label="Reports plotted" value={total} />
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden', position: 'relative' }}>
              <SizedMap layers={layers} />

              <Legend />

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
    <div ref={ref} style={{ height: 560, width: '100%' }}>
      {sized && (
        <Map
          mapId={MAP_ID}
          defaultCenter={KUALA_LUMPUR}
          defaultZoom={12}
          gestureHandling="greedy"
          disableDefaultUI
          zoomControl
          style={{ height: '100%', width: '100%' }}
        >
          <DeckGLOverlay layers={layers} />
        </Map>
      )}
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

function Legend() {
  const ramp = COLOR_RANGE.map((c) => `rgb(${c.join(',')})`).join(', ')

  return (
    <div
      className="card"
      style={{
        position: 'absolute',
        right: 16,
        bottom: 26,
        zIndex: 1000,
        padding: 12,
        fontSize: 12.5,
      }}
    >
      <div style={{ fontWeight: 650, marginBottom: 8 }}>Report density</div>
      <div
        style={{
          width: 148,
          height: 12,
          borderRadius: 6,
          background: `linear-gradient(to right, ${ramp})`,
          border: '1px solid var(--line)',
        }}
      />
      <div
        className="muted"
        style={{ display: 'flex', justifyContent: 'space-between', marginTop: 5 }}
      >
        <span>Sparse</span>
        <span>Dense</span>
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
