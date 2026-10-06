# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Everyday homeowners and renters who want a quick, nontechnical view of why their electricity costs are high, what is using power, and where they might save. The supplied PRD uses the Miller family as an illustrative household.

## Product Purpose

EnergyLens translates household and device electricity use into glanceable cost and waste information. The intended outcome is to help people identify avoidable use and check the effect of actions without requiring them to interpret electrical telemetry.

## Positioning

Evidence-backed waste detection and measured outcomes remain the intended distinction. The current 14-page design reference contains illustrative household readings, savings, recommendations, and actions; these are approved design content, not evidence that detection or savings verification is live.

## Operating Context

The Flutter app targets iOS and Android. The supplied design replaces the four-section customer navigation with Dashboard, Devices, Efficiency, Tips, and Settings, and includes 14 named page variants. The PRD describes mobile web/PWA delivery, but this repository implements the same supplied customer pages in the mobile app. Cloud features depend on configured services and available data; local pilot features have separate build configuration.

## Capabilities and Constraints

- The owner approved displaying the exact sample names, values, and wording from the 14 supplied HTML/PNG designs until backend data is connected. These values are reference content, not measured household results; future backend integration must replace them with actual or unavailable data.
- The app contains local energy estimate logic and clients for hub and cloud data. A screen or client in code does not establish that its external service is live or that a household has readings.
- Production release builds require configured real authentication. Local or dummy authentication stays in local development configuration.
- Build and install a Release app on a physical iPhone for customer acceptance. A Flutter Debug build is insufficient.
- Develop and verify the mobile customer UI before resuming work on the web UI.
- Get owner approval for the exact customer-facing words and new UI content before adding or changing them. Keep primary screens concise; retain provenance and calculation detail internally or in a separately approved presentation.
- Whether iOS and Android should use distinct design language beyond standard Flutter behavior remains open.
- The PRD's product direction is read-only energy analysis; it does not authorize remote power switching. The source designs contain illustrative controls whose backend behavior remains unimplemented.

## Brand Commitments

The product name is EnergyLens. The 14 HTML/PNG pairs under `../energy_waste_monitor design files/` are the exact visual and copy reference for the new customer pages. The owner chose these pairs over differing PDF variants and approved their source wording and values. For `tips_knowledge`, its PNG conflicts with its HTML; the owner chose the HTML FAQ, which matches the PDF frame. For `dashboard`, its PNG conflicts with its HTML; the owner chose the Dashboard HTML. Their illustrative readings, savings, assistant responses, and controls are not product evidence.

## Evidence on Hand

- Current app behavior and build configuration: [README.md](README.md), [lib/main.dart](lib/main.dart), and the feature code under `lib/features/`.
- Latest supplied requirements: [Energylens_product_requirements_document_prd.md](../energy_waste_monitor%20design%20files/Energylens_product_requirements_document_prd.md); 14 approved HTML/PNG source pairs in the same folder; [copy inventory](docs/new-ui-copy-review.md).
- Earlier product record: [energylens-common/product/mobile/PRODUCT.md](../energylens-common/product/mobile/PRODUCT.md). Its implementation-status statements predate current mobile work.
- No household-specific measurements, verified savings, or testimonials are supplied by this product record.

## Product Principles

1. Put energy and cost numbers for the home and devices first, using plain language.
2. Distinguish measured data, sourced estimates, and unavailable data.
3. Support waste findings and claimed savings with evidence.
4. Keep incomplete integrations and disconnected states truthful.
5. Preserve the supplied page designs exactly during this replacement, then connect real household data as backend support arrives.
