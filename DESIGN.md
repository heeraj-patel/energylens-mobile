---
name: EnergyLens Light Mobile
description: Native EnergyLens screens shaped by the light Figma reference.
colors:
  ink: "#0f172a"
  muted: "#61738b"
  canvas: "#f8fafc"
  surface: "#ffffff"
  line: "#e1e8ee"
  primary: "#008f68"
  primary-soft: "#e3f5ed"
  rose: "#e11d48"
  rose-soft: "#fff1f2"
  blue: "#007fbe"
typography:
  headline:
    fontFamily: "system-ui"
    fontWeight: 700
  body:
    fontFamily: "system-ui"
    fontWeight: 400
rounded:
  inner: "16px"
  surface: "22px"
  pill: "999px"
  circle: "50%"
spacing:
  tight: "8px"
  standard: "16px"
  section: "16px"
components:
  surface-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.surface}"
    padding: "16px"
  native-navigation:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    height: "80px"
  round-icon:
    textColor: "{colors.primary}"
    rounded: "{rounded.circle}"
    size: "42px"
  empty-metric:
    textColor: "{colors.ink}"
    rounded: "{rounded.inner}"
    padding: "10px"
  setup-disclosure:
    backgroundColor: "{colors.surface}"
---


The canonical design system is [here](../energylens-common/product/mobile/DESIGN.md).
This file remains as a repository-local entry point for design tooling.
