import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { Map, Marker } from '@vis.gl/react-google-maps'
import * as api from '../api/endpoints'
import { errorMessage, mediaUrl } from '../api/client'
import {
  Confidence,
  ErrorState,
  Loading,
  Notice,
  TopBar,
  formatDateTime,
} from '../components/ui'
import {
  PIN_ICON_ANCHOR,
  PIN_ICON_SIZE,
  PIN_ICON_URL,
} from '../components/clusterBands'

/**
 * D05 — Report Detail, READ-ONLY.
 *
 * There is no approve, reject, override, edit or delete control anywhere on
 * this page, and no endpoint behind one. That absence is the design, not an
 * omission: FR12 (manual review / override) was removed, and the AI decision
 * is final because it is made before submission.
 */
export default function ReportDetail() {
  const { reportId } = useParams()
  const [report, setReport] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [activePhoto, setActivePhoto] = useState(0)

  const load = useCallback(() => {
    setLoading(true)
    setError('')
    api
      .getReport(reportId)
      .then(setReport)
      .catch((err) => setError(errorMessage(err, 'This report could not be loaded.')))
      .finally(() => setLoading(false))
  }, [reportId])

  useEffect(load, [load])

  if (loading) return <Loading label="Loading report…" />
  if (error) return <ErrorState message={error} onRetry={load} />
  if (!report) return null

  const photo = report.photos[activePhoto]
  const position = { lat: Number(report.latitude), lng: Number(report.longitude) }

  return (
    <>
      <TopBar title={report.reference_no}>
        <Link to="/reports" className="btn">
          ← Back to reports
        </Link>
      </TopBar>

      <div className="page">
        {/* Shipped in the first commit, not added later: an officer must never
            be in doubt about whether this screen can change anything. */}
        <Notice title="READ-ONLY">
          Photo evidence is validated by the AI classifier before a report is
          submitted, so this report has already passed validation. You may view
          and export it. There is no approve, reject or override action —
          administrators do not verify reports.
        </Notice>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'minmax(0, 1.55fr) minmax(0, 1fr)',
            gap: 18,
            alignItems: 'start',
          }}
        >
          <section className="card" style={{ padding: 18 }}>
            <h3 style={{ fontSize: 15, marginBottom: 12 }}>Photo evidence</h3>

            {report.photos.length === 0 ? (
              <div className="empty">No photographs stored.</div>
            ) : (
              <>
                <a
                  href={mediaUrl(photo.storage_path)}
                  target="_blank"
                  rel="noreferrer"
                  title="Open full size"
                >
                  <img
                    src={mediaUrl(photo.storage_path)}
                    alt={`Evidence ${photo.sequence_no}`}
                    style={{
                      width: '100%',
                      maxHeight: 460,
                      objectFit: 'contain',
                      background: 'var(--surface-2)',
                      borderRadius: 8,
                      display: 'block',
                    }}
                  />
                </a>

                <div style={{ display: 'flex', gap: 10, marginTop: 12, flexWrap: 'wrap' }}>
                  {report.photos.map((item, index) => (
                    <button
                      key={item.storage_path}
                      onClick={() => setActivePhoto(index)}
                      style={{
                        padding: 0,
                        border:
                          index === activePhoto
                            ? '2px solid var(--brand)'
                            : '2px solid var(--line)',
                        borderRadius: 8,
                        overflow: 'hidden',
                        background: 'none',
                        lineHeight: 0,
                      }}
                    >
                      <img
                        src={mediaUrl(item.storage_path)}
                        alt={`Thumbnail ${item.sequence_no}`}
                        style={{ width: 74, height: 74, objectFit: 'cover' }}
                      />
                    </button>
                  ))}
                </div>

                <div
                  style={{
                    marginTop: 14,
                    display: 'flex',
                    alignItems: 'center',
                    gap: 14,
                    fontSize: 13,
                  }}
                >
                  <span className="muted">
                    Photo {photo.sequence_no} of {report.photos.length}
                  </span>
                  <Confidence value={photo.confidence_score} />
                  <span className="muted">
                    Captured {formatDateTime(photo.captured_at)}
                  </span>
                </div>
              </>
            )}
          </section>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
            <section className="card" style={{ padding: 18 }}>
              <h3 style={{ fontSize: 15, marginBottom: 12 }}>Location</h3>
              <Map
                // Sized inline, not via className: <Map> forwards one or the
                // other to the map element and drops `style` whenever
                // `className` is set, which silently collapses it to zero
                // height. This card has no overflow:hidden, so the rounding
                // has to clip here.
                style={{
                  height: 200,
                  width: '100%',
                  borderRadius: 'var(--radius)',
                  overflow: 'hidden',
                }}
                defaultCenter={position}
                defaultZoom={16}
                // Replaces Leaflet's scrollWheelZoom={false}: a wheel over a
                // 200px map should scroll the page, not zoom the map out from
                // under the officer reading it.
                gestureHandling="cooperative"
                disableDefaultUI
                zoomControl
                clickableIcons={false}
              >
                <LocationPin position={position} />
              </Map>

              <dl style={{ margin: '14px 0 0', fontSize: 13.5 }}>
                <Row label="Premise" value={report.premise_name || 'Not given'} />
                <Row label="Address" value={report.address_text || '—'} />
                <Row
                  label="Coordinates"
                  value={
                    <span className="mono">
                      {Number(report.latitude).toFixed(5)},{' '}
                      {Number(report.longitude).toFixed(5)}
                    </span>
                  }
                />
              </dl>
            </section>

            <section className="card" style={{ padding: 18 }}>
              <h3 style={{ fontSize: 15, marginBottom: 12 }}>Report details</h3>
              <dl style={{ margin: 0, fontSize: 13.5 }}>
                <Row
                  label="Reference"
                  value={<span className="mono">{report.reference_no}</span>}
                />
                <Row label="Reported" value={formatDateTime(report.reported_at)} />
                <Row label="Submitted" value={formatDateTime(report.submitted_at)} />
                <Row label="Photos" value={report.photos.length} />
                <Row
                  label="Reporter"
                  value={
                    <>
                      {report.reporter}
                      <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>
                        SCOPE holds no identifying information about reporters.
                      </div>
                    </>
                  }
                />
              </dl>
            </section>
          </div>
        </div>
      </div>
    </>
  )
}

/**
 * The report's location pin.
 *
 * Its own component so the google.maps constructors run at *its* render rather
 * than at ReportDetail's. <Map> renders children only once the API has loaded,
 * but the props of an element written inline in ReportDetail's JSX are built
 * when ReportDetail renders — long before window.google exists, which throws
 * "Cannot read properties of undefined (reading 'maps')" and takes the page
 * down with it.
 */
function LocationPin({ position }) {
  return (
    <Marker
      position={position}
      icon={{
        url: PIN_ICON_URL,
        scaledSize: new window.google.maps.Size(
          PIN_ICON_SIZE.width,
          PIN_ICON_SIZE.height,
        ),
        anchor: new window.google.maps.Point(
          PIN_ICON_ANCHOR.x,
          PIN_ICON_ANCHOR.y,
        ),
      }}
    />
  )
}


function Row({ label, value }) {
  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '116px 1fr',
        gap: 10,
        padding: '7px 0',
        borderBottom: '1px solid var(--line)',
      }}
    >
      <dt className="muted">{label}</dt>
      <dd style={{ margin: 0 }}>{value}</dd>
    </div>
  )
}
