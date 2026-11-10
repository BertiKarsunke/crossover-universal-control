# Crossover design system

The system for Crossover's menu bar popover, tray icon and crossing-zone bars, built by reconciling the Nothing design system and Hallmark.
Where the two disagree, this document is the final word. Any UI change must follow it.

## Principles

- **One screen, one job.** Read the state and where the pointer crosses at a glance. The only action is reconnect.
- **Three layers.** Primary: the state word. Secondary: the map and positions. Tertiary: the substate, metadata and settings.
- **Subtraction.** If spacing can separate things, use no lines or boxes. No card inside a card.
- **One expressive moment.** The Doto dot-matrix state word. Nothing else on the screen is decorated.

## Typography

| Role | Typeface | Size | Notes |
| --- | --- | --- | --- |
| State word (one per screen) | Doto | large | Sentence case (`Connected`). The only outlier face. |
| Body, labels, buttons | Space Grotesk | medium / small | Sentence case, no letter-spacing. Labels are one step smaller than body. |
| Data (times, percentages, versions) | Space Mono | small | Only on the values themselves, as data material. Never on labels. |

- Three sizes and two weights per screen at most (Regular + Medium).
- No ALL CAPS, no letter-spacing, no small caps, no eyebrow labels above headings.

## Colour

- Monochrome base. Light mode is warm off-white; dark mode is OLED black. Both are first-class.
- Grey levels: display 100%, primary 90%, secondary 60%, disabled 40%. Four levels at most.
- **Colour goes on values only:** the state word and the crossing-zone line. Buttons, labels and backgrounds are never coloured.
- Red (#D71921) is an interrupt, used only for disconnected: the state word, the zone line and the tray icon dot.
- Every colour and font goes through `Tokens`. No `Color(...)` or `Font.custom(...)` literals inside views.

## Spacing and containers

- 4pt within a group (state word ↔ substate), 16pt between groups, 32pt between major contexts.
- Container priority: spacing, then one divider (only above the footer), then an outline. No surface cards.
- Radius: pill buttons are capsules; everything else is 4–8pt. One radius per nesting level. Content keeps clear of a capsule's rounded end (horizontal padding ≥ height/2).

## Text and status

- No middle-dot joined strings. Write plain sentences: `Below DELL U2414H, 0–35%`.
- No decorative brackets (`[ ON ]`, `[READY]`). No toasts either: show status inline, and only while it exists (`Reconnecting…`, `Couldn’t reconnect`).
- Dots only when they encode state (the tray icon's disconnected dot). No decorative dots.
- About 80 words on the default screen.

## Controls

- One primary button style, and only when it is needed. Reconnect is primary only while disconnected; otherwise it is neutral.
- Toggles look like physical switches (track and knob); their state is shown by shape and fill, not text.
- Every control has default, hover, pressed, focus, disabled and active states.
- Focus: a 1pt text-display outline with a 2pt offset, shown immediately during keyboard navigation. Focus never lands automatically when the popover opens.

## Motion

- Percussive: short ease-out, no springs or bounce. Animate only opacity and transforms.
- With Reduce Motion on, nothing animates. The reconnecting tray icon becomes a static icon.

## Tray icon

- Template image that follows the menu bar's light/dark appearance automatically. States are told apart by shape: filled (connected), outline (standby), outline plus red dot (disconnected), dimmed slashed (off), `…` (unknown).
- Each state has an accessibility label (`Crossover: connected`).

## Crossing-zone bars

- One 6pt bar per segment, in the state colour. Clicks pass through.
- Colours can be changed in Settings, but red is reserved for disconnected.
