---
name: EnergyLens Glacier Energy Mobile
description: The approved light mobile system from the fourteen supplied EnergyLens HTML pages.
colors:
  primary: "#006686"
  navigation-active: "#0284c7"
  primary-container: "#7dd3fc"
  on-primary-container: "#005b78"
  secondary: "#376479"
  secondary-container: "#bae6ff"
  tertiary: "#724e97"
  tertiary-container: "#ddbaff"
  surface: "#f9f9ff"
  surface-container-lowest: "#ffffff"
  surface-container-low: "#f1f3ff"
  surface-container-high: "#e0e8ff"
  surface-container-highest: "#d8e2fd"
  on-surface: "#111b2f"
  on-surface-variant: "#3f484e"
  outline-variant: "#bec8ce"
  error: "#ba1a1a"
  useful: "#059669"
typography:
  headline-lg:
    fontFamily: "Oswald, sans-serif"
    fontSize: "32px"
    fontWeight: 600
    lineHeight: "40px"
  body-md:
    fontFamily: "Inter, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: "24px"
  label-md:
    fontFamily: "Rubik, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: "20px"
rounded:
  sm: "2px"
  lg: "4px"
  xl: "8px"
  pill: "9999px"
spacing:
  space-xs: "4px"
  space-sm: "8px"
  space-md: "16px"
  space-lg: "24px"
  space-xl: "32px"
  gutter: "16px"
components:
  surface-card:
    backgroundColor: "{colors.surface-container-lowest}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.xl}"
    padding: "{spacing.space-md}"
  inset-metric:
    backgroundColor: "{colors.surface-container-low}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.xl}"
    padding: "{spacing.space-sm}"
  button-primary:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.on-primary-container}"
    rounded: "{rounded.xl}"
    padding: "8px 12px"
  input:
    backgroundColor: "{colors.surface-container-low}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.xl}"
    padding: "8px 12px"
  bottom-navigation:
    backgroundColor: "{colors.surface-container-lowest}"
    textColor: "{colors.on-surface-variant}"
    height: "64px"
---

# Design System: EnergyLens Glacier Energy Mobile

## Overview

**Creative North Star: "Clear Energy at Home"**

The approved fourteen HTML pages form a light, compact mobile system. Cool white and pale blue surfaces give energy and cost information room to scan. Deep teal identifies actions and interface icons, while sky blue marks the selected bottom destination; green and warm warning colors distinguish useful use and waste in the data. The visual tone is clear, calm, and approachable.

The source pages are the authority for future mobile work. Build new work in this system, then check it against the supplied pages and actual device captures. The older emerald Flutter system, four-section navigation, and the supplied Glacier dark-glass prose describe earlier or conflicting directions. They are not the visual reference for new customer pages.

**Key Characteristics:** light ice-blue surfaces; Oswald headings with Inter content and Rubik labels; compact cards and metric tiles; five-part bottom navigation; soft borders and restrained shadows.

## Colors

Primary deep teal drives actions and interface icons. The active bottom destination uses a brighter sky blue; its ice-blue container fills buttons, highlights, and useful portions of charts. Secondary slate blue supports quieter controls. Tertiary violet appears sparingly in secondary accents. Cool white is the page canvas, with white cards and pale blue inset surfaces. Dark navy text and blue-gray support text carry the hierarchy; a light outline separates stacked surfaces. Error red and useful green are data colors, not a second brand palette.

**The Source Palette Rule.** Reuse the values in the frontmatter and the approved page HTML. Do not substitute the earlier emerald navigation palette or the dark-glass colors from the conflicting source prose.

## Typography

Oswald provides the compressed, architectural headings and large metric emphasis. Inter carries paragraphs, values, and readable detail. Rubik supplies compact labels, tabs, and controls. The approved pages bundle these fonts locally, with sans-serif fallbacks.

The declared source roles are headline (32px/40px, weight 600), body (16px/24px, weight 400), and label (14px/20px, weight 500). Individual pages use smaller and stronger utility variants for dense mobile information. Match those variants from the source page that owns the component.

**The Three-Font Rule.** Preserve each family's role; do not replace the pages with platform system text or use Oswald for body paragraphs.

## Layout

The reference is mobile portrait, with a 16px page gutter and a 4/8/16/24/32px spacing scale. A fixed top header and fixed five-destination bottom navigation frame scrollable page content. Page variants use compact horizontal selectors below the header. Metric cards use paired columns where the source shows them; longer explanations and device lists stack vertically. Preserve safe-area spacing and compare new screens at the supplied 390–430px phone widths and on a physical device.

**The Five-Section Rule.** Dashboard, Devices, Efficiency, Tips, and Settings remain the primary navigation. Their named variants are separate page states, not extra bottom destinations.

## Elevation & Depth

The system combines light tonal layering, fine borders, and small offset shadows. White cards sit on a near-white canvas; pale blue inset tiles separate data within a card. The header and bottom navigation use translucent white, backdrop blur, a divider, and a subtle offset shadow. Keep that hierarchy restrained and use the exact source treatment for a component that already exists.

## Shapes

Cards and controls use gentle 4–8px corners in the source theme; small status chips use pill silhouettes. Icon wells and avatars are rounded. Thin strokes and tonal fills define most boundaries. Do not introduce the former 22px Flutter card radius as the default for new pages.

## Components

Buttons, cards, and fields feel compact and approachable. Their states stay clear within the dense mobile layout.

### Buttons

Primary actions use an ice-blue fill with deep teal text, compact Rubik labels, and gently rounded corners. Stronger confirm actions on Settings use deep teal with white text. Hover softens opacity or changes the tonal fill; pressed states may compress slightly. The approved HTML owns each action's exact copy and state.

### Chips and selectors

Small status chips use tinted fills. Section selectors sit in a pale track; the selected item becomes a white, subtly raised segment with darker, bolder text. Efficiency and Tips retain their separate variant labels and active treatments.

### Cards and metrics

White bordered cards hold the main content, usually with 16px internal padding. Pale blue inset metrics use a smaller 8px padding. Data colors distinguish useful and wasted values; the chart's colored segments follow the source. Keep dense values glanceable and avoid adding explanatory blocks inside the card without approved copy.

### Inputs

Settings fields use a pale surface, fine outline, compact label, and 8px corners. Focus shifts the outline toward the primary color. Knowledge search uses the same soft surface language and a leading search icon.

### Navigation

The fixed five-part bottom bar uses Material Symbols icons and short labels. Unselected entries are muted; the selected entry is blue and bolder. The top header uses a compact icon or section label at left and contextual action at right. Preserve the safe areas and source proportions.

The fourteen packaged pages mount their outer header and five-tab bar through `assets/design_pages/shared/chrome.js`. Each page supplies its approved home name, section label, icon and action IDs, binding IDs, and active destination. The shared header and tab bar use one visual treatment on every page. Only the current destination and page-specific content change; page content and `code.html` remain separate references.

`assets/design_pages/shared/mobile_refinements.css` owns the common body and page-title typography, header and bottom-tab theme, segmented selectors, and semantic useful/waste colors. Text ink and graph fills use separate tokens to keep small labels legible while preserving the chart palette. Reuse these classes in packaged pages and runtime-rendered content.

## Do's and Don'ts

### Do:

- **Do** use the fourteen approved HTML pages and bundled assets as the visual and wording reference for new mobile work.
- **Do** use Dashboard HTML and Knowledge HTML FAQ where their PNGs disagree; the owner chose those variants.
- **Do** keep the initial page copy, sample values, font roles, and component states exact until the owner approves a change.
- **Do** compare the resulting screen on a physical iPhone in Release mode.

### Don't:

- **Don't** reuse the earlier four-section emerald Flutter design system as new-screen guidance.
- **Don't** apply the dark glassmorphism prose from the supplied Glacier DESIGN.md to these light HTML pages.
- **Don't** treat sample energy values or savings in the visual references as measured evidence.
