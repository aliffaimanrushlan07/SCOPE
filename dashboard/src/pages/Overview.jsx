import { useCallback, useEffect, useState } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import * as api from '../api/endpoints'
import { errorMessage } from '../api/client'
import { ErrorState, Loading, TopBar, formatDate } from '../components/ui'
import { PeriodSelect } from './HotspotMap'

/**
 * D02 — Overview & Analytics (FR13).
 *
 * Four panels: total reports, reports over time, top hotspot locations, and
 * the period comparison.
 *
 * Three panels from the original design are deliberately ABSENT: average AI
 * confidence, pending-review count and verified count. All three described a
 * verification workflow that no longer exists, and reinstating any of them
 * would reintroduce the contradiction the revision removed.
 *
 * There is also no "by premise type" breakdown. Premise type was removed from
 * the data model in favour of an optional free-text premise name, and free
 * text supplied by an unidentified reporter cannot support reliable grouping.
 */
export default function Overview() {
  const [days, setDays] = useState(30)
  const [granularity, setGranularity] = useState('day')
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [exporting, setExporting] = useState(false)

  const load = useCallback(() => {
    setLoading(true)
    setError('')
    api
      .overview({ days, granularity })
      .then(setData)
      .catch((err) => setError(errorMessage(err, 'Analytics could not be loaded.')))
      .finally(() => setLoading(false))
  }, [days, granularity])

  useEffect(load, [load])

  const handleExport = async () => {
    setExporting(true)
    try {
      await api.downloadCsv({})
    } catch (err) {
      setError(errorMessage(err, 'The export could not be produced.'))
    } finally {
      setExporting(false)
    }
  }

  return (
    <>
      <TopBar title="Overview">
        <select
          value={granularity}
          onChange={(e) => setGranularity(e.target.value)}
          style={{
            padding: '8px 11px',
            border: '1px solid var(--line)',
            borderRadius: 8,
            background: 'var(--white)',
          }}
        >
          <option value="day">By day</option>
          <option value="week">By week</option>
          <option value="month">By month</option>
        </select>
        <PeriodSelect value={days} onChange={setDays} />
        <button className="btn" onClick={handleExport} disabled={exporting}>
          {exporting ? 'Preparing…' : '↓ Export CSV'}
        </button>
      </TopBar>

      <div className="page">
        {loading ? (
          <Loading label="Loading analytics…" />
        ) : error ? (
          <ErrorState message={error} onRetry={load} />
        ) : (
          <>
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(210px, 1fr))',
                gap: 16,
              }}
            >
              <StatCard label="Total reports (all time)" value={data.total_reports} />
              <StatCard
                label={`Reports in last ${days} days`}
                value={data.period_total}
                delta={data.percentage_change}
              />
              <StatCard
                label="Previous period"
                value={data.previous_period_total}
                muted
              />
            </div>

            <section className="card" style={{ padding: 18 }}>
              <h3 style={{ fontSize: 15, marginBottom: 4 }}>Reports over time</h3>
              <p className="muted" style={{ fontSize: 12.5, marginTop: 0, marginBottom: 14 }}>
                Temporal trend, for patrol scheduling.
              </p>
              {data.reports_over_time.length === 0 ? (
                <div className="empty">No reports in this period.</div>
              ) : (
                <ResponsiveContainer width="100%" height={260}>
                  <BarChart
                    data={data.reports_over_time.map((point) => ({
                      label: formatDate(point.period),
                      count: point.count,
                    }))}
                    margin={{ top: 4, right: 8, bottom: 4, left: 0 }}
                  >
                    <CartesianGrid stroke="#dfe4e6" vertical={false} />
                    <XAxis
                      dataKey="label"
                      tick={{ fontSize: 11, fill: '#6b767c' }}
                      tickLine={false}
                      axisLine={{ stroke: '#dfe4e6' }}
                    />
                    {/* Anchored at zero explicitly. Left to infer its own
                        domain, recharts collapses it when every value in the
                        period is equal — which renders zero-height bars. It is
                        also simply correct for a count chart: a bar axis that
                        does not start at zero misrepresents magnitude. */}
                    <YAxis
                      allowDecimals={false}
                      domain={[0, (max) => Math.max(1, Math.ceil(max))]}
                      tick={{ fontSize: 11, fill: '#6b767c' }}
                      tickLine={false}
                      axisLine={false}
                      width={34}
                    />
                    <Tooltip
                      cursor={{ fill: '#f4f6f7' }}
                      contentStyle={{
                        border: '1px solid #dfe4e6',
                        borderRadius: 8,
                        fontSize: 13,
                      }}
                    />
                    {/* Animation disabled: under React 19, recharts 3's entry
                        animation can stall at frame zero and leave every bar
                        rendered at zero height. A static chart is also the
                        right call for a report figure that gets screenshotted. */}
                    <Bar
                      dataKey="count"
                      /* --chart-bar. Inlined because recharts writes fill as
                         an SVG attribute, which does not resolve var(). */
                      fill="#0d9488"
                      radius={[3, 3, 0, 0]}
                      isAnimationActive={false}
                      maxBarSize={64}
                    />
                  </BarChart>
                </ResponsiveContainer>
              )}
            </section>

            <section className="card" style={{ padding: 18 }}>
              <h3 style={{ fontSize: 15, marginBottom: 4 }}>Top hotspot locations</h3>
              <p className="muted" style={{ fontSize: 12.5, marginTop: 0, marginBottom: 14 }}>
                Grouped by coordinate, not by premise name — a name supplied by
                an unidentified reporter cannot support reliable grouping.
              </p>
              {data.top_locations.length === 0 ? (
                <div className="empty">No locations in this period.</div>
              ) : (
                <TopLocations locations={data.top_locations} />
              )}
            </section>
          </>
        )}
      </div>
    </>
  )
}

function StatCard({ label, value, delta, muted }) {
  return (
    <div className="card" style={{ padding: 16 }}>
      <div className="muted" style={{ fontSize: 12.5 }}>
        {label}
      </div>
      <div
        style={{
          fontSize: 30,
          fontWeight: 650,
          marginTop: 6,
          color: muted ? 'var(--muted)' : 'var(--ink)',
        }}
      >
        {value}
      </div>
      {delta != null && (
        <div className="muted" style={{ fontSize: 12.5, marginTop: 2 }}>
          {delta > 0 ? '▲' : delta < 0 ? '▼' : '■'} {Math.abs(delta)}% vs previous
          period
        </div>
      )}
    </div>
  )
}

function TopLocations({ locations }) {
  const max = Math.max(...locations.map((l) => l.count))
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
      {locations.map((location) => (
        <div key={`${location.latitude},${location.longitude}`}>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              fontSize: 13.5,
              marginBottom: 4,
              gap: 12,
            }}
          >
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {location.label}
            </span>
            <strong>{location.count}</strong>
          </div>
          <div style={{ height: 7, background: 'var(--surface-2)', borderRadius: 4 }}>
            <div
              style={{
                width: `${(location.count / max) * 100}%`,
                height: '100%',
                background: 'var(--ink-2)',
                borderRadius: 4,
              }}
            />
          </div>
        </div>
      ))}
    </div>
  )
}
