import * as React from "react";
import { motion, useReducedMotion, useScroll, useTransform, type MotionValue } from "motion/react";

/*
 * Site-wide deep-space backdrop, fixed behind every page:
 * - a cloud nebula drawn once from SVG fractal noise, tinted in the brand blue,
 * - three star layers at different depths that drift at different speeds as the page scrolls,
 * - two sparse layers that twinkle out of phase, and the odd shooting star.
 * Stars are SVG patterns built from a seeded PRNG, so server and client render the same markup.
 * Everything that moves is transform/opacity only and stops under prefers-reduced-motion.
 */

type Star = { x: number; y: number; r: number; o: number; c: string };

/** mulberry32: tiny deterministic PRNG so the sky is identical on every render. */
function rng(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Mostly white, some blue-white, a few warm: the spread of real star colours, kept cool overall.
const TINTS = ["#ffffff", "#ffffff", "#e3f0ff", "#cfe6ff", "#ffffff", "#fff1dc"];

function makeStars(seed: number, count: number, tile: number, [rMin, rMax]: [number, number], [oMin, oMax]: [number, number]): Star[] {
  const next = rng(seed);
  return Array.from({ length: count }, () => ({
    x: +(next() * tile).toFixed(1),
    y: +(next() * tile).toFixed(1),
    r: +(rMin + next() ** 2 * (rMax - rMin)).toFixed(2),
    o: +(oMin + next() * (oMax - oMin)).toFixed(2),
    c: TINTS[Math.floor(next() * TINTS.length)],
  }));
}

type LayerSpec = { id: string; tile: number; speed: number; stars: Star[]; glow?: boolean; className?: string };

const LAYERS: LayerSpec[] = [
  { id: "far", tile: 760, speed: 0.03, stars: makeStars(3, 230, 760, [0.35, 0.8], [0.25, 0.6]) },
  { id: "mid", tile: 1040, speed: 0.07, stars: makeStars(17, 90, 1040, [0.6, 1.15], [0.45, 0.85]) },
  { id: "near", tile: 1380, speed: 0.13, stars: makeStars(41, 22, 1380, [0.9, 1.5], [0.8, 1]), glow: true },
  { id: "tw-a", tile: 980, speed: 0.07, stars: makeStars(59, 26, 980, [0.8, 1.3], [0.85, 1]), glow: true, className: "cosmos-twinkle" },
  { id: "tw-b", tile: 1180, speed: 0.1, stars: makeStars(71, 22, 1180, [0.8, 1.3], [0.85, 1]), glow: true, className: "cosmos-twinkle cosmos-twinkle-late" },
];

function StarLayer({ spec, scrollY, still }: { spec: LayerSpec; scrollY: MotionValue<number>; still: boolean }) {
  // Wrap the offset by one tile: the pattern repeats with that period, so the loop is seamless.
  const y = useTransform(scrollY, (v) => (still ? 0 : -((v * spec.speed) % spec.tile)));
  const pid = `cosmos-${spec.id}`;
  return (
    <motion.svg
      aria-hidden
      // Own compositor layer: without it every scroll frame repaints the whole sky (measured ~69 vs ~114 fps).
      className={`absolute inset-x-0 top-0 w-full ${still ? "" : "will-change-transform"} ${spec.className ?? ""}`}
      style={{ y, height: `calc(100% + ${spec.tile}px)` }}
    >
      <defs>
        <pattern id={pid} width={spec.tile} height={spec.tile} patternUnits="userSpaceOnUse">
          {spec.stars.map((s, i) => (
            <React.Fragment key={i}>
              {spec.glow && <circle cx={s.x} cy={s.y} r={s.r * 4} fill={s.c} opacity={s.o * 0.12} />}
              <circle cx={s.x} cy={s.y} r={s.r} fill={s.c} opacity={s.o} />
            </React.Fragment>
          ))}
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill={`url(#${pid})`} />
    </motion.svg>
  );
}

/** Wispy nebula: fractal noise used as a mask over soft blue shapes, so the clouds have real texture. */
function Nebula() {
  return (
    <svg aria-hidden className="absolute inset-0 h-full w-full" viewBox="0 0 1600 1000" preserveAspectRatio="xMidYMid slice">
      <defs>
        <filter id="cosmos-noise" x="0" y="0" width="100%" height="100%">
          <feTurbulence type="fractalNoise" baseFrequency="0.0021 0.0034" numOctaves="5" seed="11" />
          {/* White, with alpha pushed up from the noise's red channel: high-contrast wisps, not fog. */}
          <feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  2.6 0 0 0 -1.1" />
        </filter>
        <filter id="cosmos-dust" x="0" y="0" width="100%" height="100%">
          <feTurbulence type="fractalNoise" baseFrequency="0.006 0.009" numOctaves="4" seed="4" />
          <feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  3.2 0 0 0 -1.7" />
        </filter>
        <mask id="cosmos-clouds">
          <rect width="1600" height="1000" fill="#fff" filter="url(#cosmos-noise)" />
        </mask>
        <mask id="cosmos-fine">
          <rect width="1600" height="1000" fill="#fff" filter="url(#cosmos-dust)" />
        </mask>
        <radialGradient id="cosmos-band">
          <stop offset="0" stopColor="#5cb8ff" stopOpacity="0.55" />
          <stop offset="0.45" stopColor="#2463d6" stopOpacity="0.32" />
          <stop offset="1" stopColor="#0b2a66" stopOpacity="0" />
        </radialGradient>
        <radialGradient id="cosmos-core">
          <stop offset="0" stopColor="#bfe3ff" stopOpacity="0.5" />
          <stop offset="0.35" stopColor="#38a9ff" stopOpacity="0.28" />
          <stop offset="1" stopColor="#123a8a" stopOpacity="0" />
        </radialGradient>
        <radialGradient id="cosmos-deep">
          <stop offset="0" stopColor="#1a3f9e" stopOpacity="0.35" />
          <stop offset="1" stopColor="#0a1a44" stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* Smooth under-glow so the clouds sit in colour, not on black. */}
      <ellipse cx="1180" cy="200" rx="620" ry="420" fill="url(#cosmos-deep)" />
      <ellipse cx="180" cy="880" rx="560" ry="360" fill="url(#cosmos-deep)" />

      {/* A galactic band falling from top right to bottom left, plus a brighter core near the hero. */}
      <g mask="url(#cosmos-clouds)">
        <ellipse cx="820" cy="470" rx="1050" ry="210" transform="rotate(-24 820 470)" fill="url(#cosmos-band)" />
        <circle cx="1230" cy="190" r="430" fill="url(#cosmos-core)" />
        <circle cx="210" cy="860" r="340" fill="url(#cosmos-band)" />
      </g>
      <g mask="url(#cosmos-fine)" opacity="0.55">
        <ellipse cx="820" cy="470" rx="900" ry="150" transform="rotate(-24 820 470)" fill="url(#cosmos-core)" />
      </g>
    </svg>
  );
}

export function Cosmos() {
  const reduce = !!useReducedMotion();
  const { scrollY, scrollYProgress } = useScroll();
  const nebulaY = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [0, -140]);

  return (
    <div aria-hidden className="cosmos pointer-events-none fixed inset-0 -z-10 overflow-hidden">
      {/* will-change keeps the noise-filtered nebula rasterised once, then only moved by the compositor. */}
      <motion.div className={`absolute inset-x-0 top-0 h-[calc(100%+140px)] ${reduce ? "" : "will-change-transform"}`} style={{ y: nebulaY }}>
        <Nebula />
      </motion.div>
      {LAYERS.map((spec) => (
        <StarLayer key={spec.id} spec={spec} scrollY={scrollY} still={reduce} />
      ))}
      <span className="cosmos-meteor top-[9%] right-[12%]" />
      <span className="cosmos-meteor cosmos-meteor-late top-[34%] right-[46%]" />
      {/* Vignette keeps the page edges quiet and the centre readable. Its own layer too, or it repaints
          every frame as the star layers move underneath it. */}
      <div className="absolute inset-0 will-change-transform bg-[radial-gradient(ellipse_120%_90%_at_50%_40%,transparent_55%,rgb(2_4_9/0.7))]" />
    </div>
  );
}

/**
 * Concentric orbit rings with one small moon riding the second ring. Used where a panel needs
 * texture: centred on the Download logo, off the corner of the local-model bento cell.
 * Position and size come from the caller (className); rings are fractions of that box.
 */
export function Orbits({ className = "", rings = [0.3, 0.52, 0.76, 1] }: { className?: string; rings?: number[] }) {
  return (
    <div aria-hidden className={`pointer-events-none absolute aspect-square ${className}`}>
      {rings.map((f, i) => (
        <span
          key={f}
          className={`absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full border ${i === 1 ? "border-[#38a9ff]/20" : "border-white/[0.07]"}`}
          style={{ width: `${f * 100}%`, height: `${f * 100}%` }}
        />
      ))}
      {rings.length > 1 && (
        <span className="animate-spin-slow absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2" style={{ width: `${rings[1] * 100}%`, height: `${rings[1] * 100}%` }}>
          <span className="absolute top-0 left-1/2 size-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[#9fd4ff] shadow-[0_0_12px_2px_rgb(56_169_255/0.7)]" />
        </span>
      )}
    </div>
  );
}
