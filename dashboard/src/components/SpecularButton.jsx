import { useRef, useEffect } from 'react'
import { Renderer, Program, Mesh, Triangle, Color } from 'ogl'
import './SpecularButton.css'

/**
 * Button with a specular rim highlight that turns toward the pointer, adapted
 * from React Bits' <SpecularButton /> (https://reactbits.dev). It is the login
 * submit, so the effect must never get in the way of the button itself:
 *
 *  - No WebGL 2 → plain CSS button. Upstream dereferences a null context and
 *    throws, which would blank the login page.
 *  - prefers-reduced-motion → the moving highlight is off; only the static
 *    edge stroke is drawn.
 *  - The frame loop stops rendering once the highlight has faded out, so an
 *    idle login page is not redrawing the button every frame.
 */

const PAD = 20

const VERT = `#version 300 es
in vec2 position;
void main() {
  gl_Position = vec4(position, 0.0, 1.0);
}
`

const FRAG = `#version 300 es
precision highp float;

uniform vec2 uCenter;
uniform vec2 uHalfSize;
uniform float uRadius;
uniform float uAngle;
uniform float uPx;
uniform vec3 uLineColor;
uniform vec3 uBaseColor;
uniform float uIntensity;
uniform float uShineSize;
uniform float uShineFade;
uniform float uThickness;
uniform float uBaseWidth;

out vec4 fragColor;

float sdRoundedRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float shapeSDF(vec2 p) { return sdRoundedRect(p, uHalfSize, uRadius); }

float gaussianLine(float d, float sigma) {
  float x = d / (sigma + 1e-6);
  float k = mix(1.0, 1.6, smoothstep(0.0, 1.5, x));
  return exp(-k * x * x);
}

void main() {
  vec2 p = gl_FragCoord.xy - uCenter;
  float d = shapeSDF(p);
  vec2 L = vec2(cos(uAngle), sin(uAngle));

  // Dark base stroke hugging the edge for a sense of thickness
  float base = (1.0 - smoothstep(0.0, uBaseWidth, abs(d))) * 0.45;

  // Symmetric specular: the edges facing toward/away from the light both
  // catch a streak. The angular window (size + fade) is measured with an
  // elliptical normal so it varies continuously along straight edges.
  vec2 nEll = normalize(p / (uHalfSize * uHalfSize) + 1e-6);
  float phi = acos(clamp(abs(dot(nEll, L)), 0.0, 1.0));
  float rim = 1.0 - smoothstep(uShineSize - uShineFade, uShineSize + uShineFade + 1e-4, phi);
  float line = gaussianLine(d, uThickness);
  float edgeClamp = 1.0 - smoothstep(0.5 * uPx, 3.0 * uPx, abs(d));
  float hi = line * rim * edgeClamp * uIntensity;

  vec3 col = uBaseColor * base + uLineColor * hi;
  float a = clamp(base + hi, 0.0, 1.0);
  fragColor = vec4(col, a);
}
`

const createRenderer = (dpr) => {
  try {
    const renderer = new Renderer({ webgl: 2, alpha: true, premultipliedAlpha: true, antialias: true, dpr })
    // ogl quietly falls back to WebGL 1 (or a null context), and the shader
    // is GLSL ES 3.00, so anything short of WebGL 2 cannot draw it.
    if (renderer.gl && renderer.isWebgl2) return renderer
    renderer.gl?.getExtension('WEBGL_lose_context')?.loseContext()
  } catch {
    // Context creation can throw under strict GPU policies; fall through.
  }
  return null
}

const SpecularButton = ({
  children = 'Get Started',
  size = 'lg',
  radius = 18,
  tint = '#ffffff',
  tintOpacity = 0,
  blur = 0,
  textColor = '#f5f5f5',
  lineColor = '#ffffff',
  baseColor = '#525252',
  intensity = 1,
  shineSize = 10,
  shineFade = 40,
  thickness = 1,
  speed = 0.35,
  followMouse = true,
  proximity = 250,
  autoAnimate = false,
  disabled = false,
  onClick,
  className = '',
  type = 'button',
}) => {
  const btnRef = useRef(null)
  const fxRef = useRef(null)
  const propsRef = useRef({})

  propsRef.current = { radius, lineColor, baseColor, intensity, shineSize, shineFade, thickness, speed, followMouse, proximity, autoAnimate }

  useEffect(() => {
    const btn = btnRef.current
    const fx = fxRef.current
    if (!btn || !fx) return

    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    const renderer = createRenderer(dpr)
    if (!renderer) return

    const gl = renderer.gl
    gl.clearColor(0, 0, 0, 0)
    gl.enable(gl.BLEND)
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)

    const geometry = new Triangle(gl)
    if (geometry.attributes.uv) delete geometry.attributes.uv

    const program = new Program(gl, {
      vertex: VERT,
      fragment: FRAG,
      uniforms: {
        uCenter: { value: [0, 0] },
        uHalfSize: { value: [1, 1] },
        uRadius: { value: 0 },
        uAngle: { value: 2.4 },
        uPx: { value: dpr },
        uLineColor: { value: [1, 1, 1] },
        uBaseColor: { value: [0.32, 0.32, 0.32] },
        uIntensity: { value: 1 },
        uShineSize: { value: 0.17 },
        uShineFade: { value: 0.7 },
        uThickness: { value: 1 },
        uBaseWidth: { value: dpr },
      },
    })

    const mesh = new Mesh(gl, { geometry, program })
    fx.appendChild(gl.canvas)

    let angle = 2.4
    let idleAngle = 2.4
    let bright = 0
    let last = performance.now()
    let raf = 0

    const lineC = new Color()
    const baseC = new Color()

    const draw = () => {
      const p = propsRef.current
      lineC.set(p.lineColor)
      baseC.set(p.baseColor)
      program.uniforms.uAngle.value = angle
      program.uniforms.uRadius.value = Math.min(p.radius, Math.min(sizeRef.w, sizeRef.h) / 2) * dpr
      program.uniforms.uLineColor.value = [lineC.r, lineC.g, lineC.b]
      program.uniforms.uBaseColor.value = [baseC.r, baseC.g, baseC.b]
      program.uniforms.uIntensity.value = p.intensity * bright
      program.uniforms.uShineSize.value = (p.shineSize * Math.PI) / 180
      program.uniforms.uShineFade.value = (p.shineFade * Math.PI) / 180
      program.uniforms.uThickness.value = p.thickness * dpr
      renderer.render({ scene: mesh })
    }

    const sizeRef = { w: 1, h: 1 }
    const resize = () => {
      // Fractional size + explicit center keep the SDF pinned to the exact
      // CSS border, instead of drifting up to a pixel from offsetWidth rounding.
      const rect = btn.getBoundingClientRect()
      const w = rect.width
      const h = rect.height
      sizeRef.w = w
      sizeRef.h = h
      renderer.setSize(w + PAD * 2, h + PAD * 2)
      program.uniforms.uCenter.value = [(PAD + w / 2) * dpr, (PAD + h / 2) * dpr]
      program.uniforms.uHalfSize.value = [(w / 2) * dpr, (h / 2) * dpr]
      // setSize clears the canvas, so redraw even when the loop is stopped.
      draw()
    }
    const ro = new ResizeObserver(resize)
    ro.observe(btn)
    resize()

    // Light angle steers toward the pointer (anywhere on the page) and falls
    // back to a slow sweep when the pointer hasn't moved yet.
    let pointerAngle = null
    let proximityT = 0
    const onPointerMove = (e) => {
      const rect = btn.getBoundingClientRect()
      const cx = rect.left + rect.width / 2
      const cy = rect.top + rect.height / 2
      const dx = Math.max(rect.left - e.clientX, 0, e.clientX - rect.right)
      const dy = Math.max(rect.top - e.clientY, 0, e.clientY - rect.bottom)
      const dist = Math.hypot(dx, dy)
      // Over the button itself the light settles on the diagonal (framing the
      // corners) and gently sways with the cursor position within the button.
      if (dist === 0) {
        const nx = (e.clientX - cx) / (rect.width / 2)
        const ny = (cy - e.clientY) / (rect.height / 2)
        pointerAngle = Math.atan2(2 / rect.height, -2 / rect.width) + nx * 0.3 + ny * 0.15
      } else {
        pointerAngle = Math.atan2(cy - e.clientY, e.clientX - cx)
      }
      const t = Math.max(0, 1 - dist / Math.max(propsRef.current.proximity, 1))
      proximityT = t * t * (3 - 2 * t)
      if (proximityT > 0 || bright > 0) start()
    }
    window.addEventListener('pointermove', onPointerMove)

    const update = (now) => {
      const dt = Math.min((now - last) / 1000, 0.05)
      last = now
      const p = propsRef.current

      idleAngle += p.speed * dt
      const steer = p.followMouse && pointerAngle != null && (!p.autoAnimate || proximityT > 0)
      const target = steer ? pointerAngle : idleAngle
      const diff = ((target - angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI
      angle += diff * (1 - Math.exp(-dt * 7))

      // Shine fades in with pointer proximity unless autoAnimate keeps it on
      const brightTarget = p.autoAnimate ? 1 : proximityT
      bright += (brightTarget - bright) * (1 - Math.exp(-dt * 8))

      // Fully faded with nothing pulling it back: draw the settled frame and
      // park the loop until the pointer moves again.
      if (brightTarget === 0 && bright < 0.001) {
        bright = 0
        draw()
        raf = 0
        return
      }

      draw()
      raf = requestAnimationFrame(update)
    }

    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')
    function start() {
      if (raf !== 0 || reducedMotion.matches) return
      last = performance.now()
      raf = requestAnimationFrame(update)
    }
    const stop = () => {
      if (raf !== 0) cancelAnimationFrame(raf)
      raf = 0
    }
    const onMotionPreference = () => {
      if (reducedMotion.matches) {
        stop()
        bright = 0
        draw()
      } else {
        start()
      }
    }
    reducedMotion.addEventListener('change', onMotionPreference)

    if (propsRef.current.autoAnimate) start()

    return () => {
      stop()
      ro.disconnect()
      window.removeEventListener('pointermove', onPointerMove)
      reducedMotion.removeEventListener('change', onMotionPreference)
      if (gl.canvas.parentNode === fx) fx.removeChild(gl.canvas)
      gl.getExtension('WEBGL_lose_context')?.loseContext()
    }
  }, [])

  return (
    <button
      ref={btnRef}
      type={type}
      disabled={disabled}
      onClick={onClick}
      className={`specular-button specular-button--${size}${className ? ` ${className}` : ''}`}
      style={{
        '--sb-radius': `${radius}px`,
        '--sb-tint': tint,
        '--sb-tint-opacity': tintOpacity,
        '--sb-blur': `${blur}px`,
        '--sb-text-color': textColor,
      }}
    >
      <span ref={fxRef} className="specular-button__fx" aria-hidden="true" />
      <span className="specular-button__label">{children}</span>
    </button>
  )
}

export default SpecularButton
