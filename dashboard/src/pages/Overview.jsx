import { useCallback, useEffect, useState } from 'react'
import { addDays, endOfMonth, format, parseISO } from 'date-fns'
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
import { ErrorState, InfoPopover, Loading, TopBar } from '../components/ui'
import PatrolTiming from '../components/PatrolTiming'
import { PeriodSelect } from './HotspotMap'

/**
 * D02 — Overview & Analytics (FR13).
 *
 * Five panels: total reports, reports over time, top hotspot locations, the
 * period comparison, and patrol timing (when violations happen, by day and
 * time of day, for all locations or one hotspot).
 *
 * Opens on weekly buckets over the last 12 months: the trend an officer plans
 * patrols from, rather than a month of single days.
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
  const [days, setDays] = useState(365)
  const [granularity, setGranularity] = useState('week')
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

  // Selected hotspot for the timing panel; null means all locations. Cleared
  // when a period change drops it from the top-locations list it came from.
  const [selected, setSelected] = useState(null)
  const [timing, setTiming] = useState(null)
  const [timingError, setTimingError] = useState('')

  useEffect(() => {
    if (
      selected &&
      data &&
      !data.top_locations.some((l) => sameLocation(l, selected))
    ) {
      setSelected(null)
    }
  }, [data, selected])

  useEffect(() => {
    let cancelled = false
    setTimingError('')
    api
      .timing({ days, latitude: selected?.latitude, longitude: selected?.longitude })
      .then((result) => !cancelled && setTiming(result))
      .catch(
        (err) =>
          !cancelled && setTimingError(errorMessage(err, 'Patrol timing could not be loaded.')),
      )
    return () => {
      cancelled = true
    }
  }, [days, selected])

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
      <TopBar
        title="Overview"
        info={
          <InfoPopover>
            A summary of smoking-violation reports for the selected period:
            totals compared with the previous period, how reports trend over
            time, and when patrols are most needed. Use the period and interval
            selectors to change the range and grouping. This page is read-only.
          </InfoPopover>
        }
      >
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
                gap: 10,
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
                      label: bucketLabel(point.period, granularity),
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
              <PartialNote series={data.reports_over_time} granularity={granularity} />
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
                <TopLocations
                  locations={data.top_locations}
                  selected={selected}
                  onSelect={(location) =>
                    setSelected(sameLocation(location, selected) ? null : location)
                  }
                />
              )}
            </section>

            <section className="card" style={{ padding: 18 }}>
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'flex-start',
                  gap: 12,
                  flexWrap: 'wrap',
                  marginBottom: 14,
                }}
              >
                <div>
                  <h3 style={{ fontSize: 15, margin: '0 0 4px' }}>When violations happen</h3>
                  <p className="muted" style={{ fontSize: 12.5, margin: 0 }}>
                    By day and time of day the violation was photographed — for
                    deciding when to patrol or monitor.
                  </p>
                </div>
                <select
                  aria-label="Location"
                  value={selected ? locationKey(selected) : ''}
                  onChange={(e) =>
                    setSelected(
                      data.top_locations.find((l) => locationKey(l) === e.target.value) ?? null,
                    )
                  }
                  style={{
                    padding: '8px 11px',
                    border: '1px solid var(--line)',
                    borderRadius: 8,
                    background: 'var(--white)',
                    maxWidth: 320,
                  }}
                >
                  <option value="">All locations</option>
                  {data.top_locations.map((location) => (
                    <option key={locationKey(location)} value={locationKey(location)}>
                      {location.label} ({location.count})
                    </option>
                  ))}
                </select>
              </div>
              {timingError ? (
                <ErrorState message={timingError} />
              ) : !timing ? (
                <Loading label="Loading patrol timing…" />
              ) : (
                <PatrolTiming timing={timing} />
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
    <div className="card stat-card" style={{ padding: 16 }}>
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

const locationKey = (location) => `${location.latitude},${location.longitude}`
const sameLocation = (a, b) => Boolean(a && b) && locationKey(a) === locationKey(b)

function bucketLabel(period, granularity) {
  const date = parseISO(period)
  return format(date, granularity === 'month' ? 'MMM yyyy' : 'd MMM')
}

/**
 * Flags a final bar that is still filling up. Without it, a month or week
 * that has only just begun reads as a sudden drop in violations.
 */
function PartialNote({ series, granularity }) {
  if (granularity === 'day' || series.length === 0) return null
  const start = parseISO(series[series.length - 1].period)
  const end = granularity === 'week' ? addDays(start, 6) : endOfMonth(start)
  const today = new Date()
  if (today < start || today > addDays(end, 1)) return null

  const sameMonth = start.getMonth() === today.getMonth()
  const range = `${format(start, sameMonth ? 'd' : 'd MMM')}–${format(today, 'd MMM')}`
  const text =
    granularity === 'week'
      ? `Week of ${format(start, 'd MMM')} is week to date (${range}).`
      : `${format(start, 'MMMM')} is month to date (${range}).`
  return (
    <p className="muted" style={{ fontSize: 12.5, margin: '10px 0 0' }}>
      {text}
    </p>
  )
}

function TopLocations({ locations, selected, onSelect }) {
  const max = Math.max(...locations.map((l) => l.count))
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      {locations.map((location) => (
        <button
          type="button"
          key={locationKey(location)}
          onClick={() => onSelect(location)}
          aria-pressed={sameLocation(location, selected)}
          style={{
            all: 'unset',
            display: 'block',
            cursor: 'pointer',
            padding: '6px 8px',
            margin: '0 -8px',
            borderRadius: 8,
            background: sameLocation(location, selected) ? 'var(--surface)' : 'transparent',
            boxShadow: sameLocation(location, selected) ? 'inset 3px 0 0 var(--brand)' : 'none',
          }}
        >
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
        </button>
      ))}
    </div>
  )
}
