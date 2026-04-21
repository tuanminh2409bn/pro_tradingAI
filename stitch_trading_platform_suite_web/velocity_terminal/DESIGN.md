# Design System Specification: Kinetic Precision

## 1. Overview & Creative North Star: "The Obsidian Pulse"
Traditional financial platforms are often cluttered, rigid, and exhausting. This design system rejects the "spreadsheet-as-an-interface" aesthetic in favor of **The Obsidian Pulse**. 

The Creative North Star is defined by **Liquid Velocity and Depth**. We treat market data not as static numbers, but as a living, breathing flow. The UI must feel like a high-performance cockpit—authoritative, expansive, and ultra-responsive. We move beyond the "template" look by using intentional asymmetry in data density: high-density information clusters balanced against expansive, breathable negative space. Overlapping elements and glassmorphism create a sense of sophisticated machinery humming at 60fps.

## 2. Colors & Surface Architecture
Our palette is anchored in deep, atmospheric darks that allow our high-octane accents to "pop" without causing eye fatigue during long trading sessions.

### Surface Hierarchy & Nesting (The "No-Line" Rule)
We prohibit the use of 1px solid borders for sectioning. Structural definition is achieved exclusively through **Tonal Shifting**.
- **Base Layer:** `surface` (#111417) – The foundation.
- **Sectioning:** Use `surface-container-low` (#191c1f) to define major layout regions (e.g., the sidebar or the order book background).
- **Interactive Units:** Use `surface-container` (#1d2023) for primary cards.
- **Elevation:** Use `surface-container-high` (#272a2e) for active states or nested content.

### The Glass & Gradient Rule
To move beyond a "standard" flat UI, all floating panels (modals, dropdowns, or hover tooltips) must utilize **Glassmorphism**:
- **Fill:** `surface-container-highest` at 70% opacity.
- **Effect:** `backdrop-blur: 24px`.
- **Signature Gradient:** For primary CTAs and critical "Buy" buttons, apply a subtle linear gradient from `secondary` (#3ce42f) to `on_secondary_container` (#004b00) at 145 degrees. This adds "soul" and a tactile, premium quality to the action.

## 3. Typography: Editorial Authority
We utilize **Inter** for its mathematical precision and neutral character, allowing the data to remain the protagonist.

| Level | Token | Size | Character | Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **Display** | `display-lg` | 3.5rem | Tight Tracking (-2%) | Epic price movements, Hero stats |
| **Headline** | `headline-md` | 1.75rem | Medium Weight | Portfolio totals, Section headers |
| **Title** | `title-sm` | 1.0rem | Semi-Bold | Asset names, Card titles |
| **Body** | `body-md` | 0.875rem | Regular | Transaction logs, Descriptions |
| **Label** | `label-sm` | 0.6875rem | All-Caps (0.05em spacing) | Data headers (e.g., VOL, MCAP) |

**Editorial Note:** Use `display-sm` for large numerical values, but pair them with `label-sm` metadata to create a "Dashboard Editorial" look. Ensure numbers are always **tabular lining** to prevent horizontal jumping during price updates.

## 4. Elevation & Depth: Tonal Layering
We reject "drop shadows" in the traditional sense. Hierarchy is achieved through the **Layering Principle**.

*   **The Ambient Lift:** When an element must float (e.g., a context menu), use a shadow color derived from `on_primary_fixed_variant` (#003ea8) at 5% opacity, with a 40px blur. This mimics a subtle blue-tinted light source, characteristic of high-end dark modes.
*   **The Ghost Border Fallback:** If high-contrast environments require containment, use the `outline-variant` (#434655) at **15% opacity**. It should be felt, not seen.
*   **Depth Stacking:** Place a `surface-container-lowest` (#0b0e11) component inside a `surface-container-low` (#191c1f) background to create a "recessed" or "etched" look for input fields and data feeds.

## 5. Components: Precision Primitives

### Buttons (Kinetic Actions)
- **Primary (Buy/Up):** Background `secondary` (#3ce42f), Label `on_secondary`. 4px radius. On hover, apply a subtle outer glow using the secondary color.
- **Secondary (Sell/Down):** Background `tertiary_container` (#ff5545), Label `on_tertiary_fixed`. 
- **Action (System):** Background `primary_container` (#618bff), Label `on_primary_fixed`. Use for "Connect Wallet" or "Settings."

### Cards & Data Lists
- **Rule:** Forbid divider lines.
- **Execution:** Separate list items by alternating between `surface` and `surface-container-low`, or use a 12px vertical margin.
- **Data Visualization:** Chart lines must use `primary` (#b4c5ff) for neutral data, with a 2px stroke and a `surface-tint` area glow beneath the line to create volume.

### Input Fields (Obsidian Inputs)
- **Base State:** `surface-container-lowest` background, no border. 
- **Focus State:** 1px "Ghost Border" using `primary` at 40% opacity. The cursor (caret) should be `primary` for a signature "Electric Blue" touch.

### Additional Signature Component: The "Pulse Indicator"
A small, 4px circular glyph next to live-ticking prices. It should use `secondary` (Green) or `tertiary` (Red) with a CSS animation: `scale(1) to scale(2)` at 0% opacity to signify real-time data ingestion at 60fps.

## 6. Do’s and Don’ts

### Do
- **Do** use `0.25rem` (sm) and `0.375rem` (md) radii for a sharp, professional look. Save `full` (pill) only for status chips.
- **Do** use `on_surface_variant` (#c3c6d8) for secondary text to maintain a sophisticated contrast ratio.
- **Do** treat "White Space" as a functional tool. If the data is complex, increase the surrounding padding.

### Don't
- **Don't** use 100% white (#FFFFFF) for text. It causes "haloing" on dark backgrounds. Use `on_surface` (#e1e2e7).
- **Don't** use pure black (#000000). It kills the sense of depth. Always stay within the defined charcoal/midnight spectrum.
- **Don't** use standard "swing" animations. Use `cubic-bezier(0.2, 0.8, 0.2, 1)` for all transitions to give a "snappy" yet smooth high-end feel.