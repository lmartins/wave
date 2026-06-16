export const site = {
  name: "Wave",
  repoOwner: "mxvsh",
  repoName: "wave",
  siteUrl: "https://wave.mxv.sh",
  ogImage: "/opengraph.png",
  title: "Wave - The right option for your every word",
  description:
    "A native macOS dictation app that turns your voice into text instantly. Local Whisper for complete privacy, or Groq for ultra-fast transcription.",
  githubUrl: "https://github.com/mxvsh/wave",
  downloadUrl: "#download",
  releaseUrl: "#download",
  // Direct release channel (Cloudflare R2 + Sparkle) — modeled on the Ayron setup.
  // XML (appcast) and DMGs live on updates.wave.mxv.sh (R2-backed custom domain).
  // The stable latest DMG is overwritten on each release with short cache TTL.
  directDmgUrl: "https://updates.wave.mxv.sh/downloads/Wave-latest.dmg",
  directAppcastUrl: "https://updates.wave.mxv.sh/appcast.xml",
  navLinks: [
    { href: "#features", label: "Features" },
    { href: "#how-it-works", label: "How it works" },
  ],
  ctaPrimary: {
    href: "#download",
    label: "Download for macOS",
  },
  ctaSecondary: {
    href: "https://github.com/mxvsh/wave",
    label: "View on GitHub",
  },
} as const;
