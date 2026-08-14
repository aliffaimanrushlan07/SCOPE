import { useCallback, useEffect, useState } from 'react'
import { MapContainer, Marker, Popup, TileLayer } from 'react-leaflet'
import * as api from '../api/endpoints'
import { errorMessage } from '../api/client'
import { ErrorState, Loading, TopBar } from '../components/ui'
import { CLUSTER_BANDS, clusterIcon } from '../components/leafletIcons'
import 'leaflet/dist/leaflet.css'

const KUALA_LUMPUR = [3.139, 101.6869]

/**
 * D03 — Hotspot Map (FR09).
 *
 * Note the deliberate difference from the public map at S06: administrators
 * get clusters resolvable to a location, the public gets a heatmap with no
 * individual pins. Precision for enforcement, privacy for everyone else.
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
              <MapContainer
                center={KUALA_LUMPUR}
                zoom={12}
                style={{ height: 560, width: '100%' }}
              >
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />
                {clusters.map((cluster) => (
                  <Marker
                    key={`${cluster.latitude},${cluster.longitude}`}
                    position={[cluster.latitude, cluster.longitude]}
                    icon={clusterIcon(cluster.count, cluster.band)}
                  >
                    <Popup>
                      <strong>
                        {cluster.count} report{cluster.count === 1 ? '' : 's'}
                      </strong>
                      <br />
                      <span className="mono">
                        {cluster.latitude.toFixed(3)}, {cluster.longitude.toFixed(3)}
                      </span>
                    </Popup>
                  </Marker>
                ))}
              </MapContainer>

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

function Legend() {
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
      <div style={{ fontWeight: 650, marginBottom: 8 }}>Reports in cluster</div>
      {CLUSTER_BANDS.map((band) => (
        <div
          key={band.band}
          style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 5 }}
        >
          <span
            style={{
              width: 17,
              height: 17,
              borderRadius: '50%',
              background: band.fill,
              border: '2px solid #fff',
              boxShadow: '0 0 0 1px var(--line)',
            }}
          />
          {band.label}
        </div>
      ))}
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
