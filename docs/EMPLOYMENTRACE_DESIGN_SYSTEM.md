# Breads Up! design system

This is the source of truth for all future UI work in this repository. It applies Duolingo's playful, tactile consumer-product principles to Breads Up!'s own purple-and-pink identity. The app is light-first: white space and restraint provide the hierarchy, while purple and pink provide the personality.

## Principles

- Make the next action obvious, friendly, and satisfying.
- Use compact, mobile-first single-column layouts; content caps at 560px.
- Reward progress with wording, visible state, and colour—but never colour alone.
- Prefer simple, snappy 300ms transitions over decorative motion.

## Tokens

| Token | Value | Use |
| --- | --- | --- |
| Background | `#FFFFFF` | Default screen canvas |
| Secondary background | `#F8F6FF` | Desktop page backdrop |
| Surface | `#FFFFFF` | Cards, forms, sheets |
| Ink | `#24163D` | Primary text |
| Muted | `#8A7D9D` | Secondary text only |
| Primary purple | `#6C3DE8` | Primary actions and selection |
| Pink accent | `#FF4B9B` | Brand moments and hires |
| Soft lavender | `#F0EAFF` | Featured/selected surfaces |
| Border | `#E5DDF1` | Default containment |
| Success | `#36C98A` | Positive status |
| Warning | `#FFCE45` | Countdown and warning |
| Radius | `12px` | Buttons, inputs, small cards |
| Spacing unit | `10px` | All layout rhythm |
| Motion | `300ms ease` | State changes only |

The runtime token implementation is [app/employmentrace-design-system.css](../app/employmentrace-design-system.css).

## Components

- **Primary button:** purple surface with a darker purple 5px bottom edge; press moves into that edge.
- **Secondary button:** white surface, quiet lilac outline, no primary visual weight.
- **Danger / irreversible button:** pink surface and darker pink bottom edge.
- **Card:** white surface, 1px lavender border, no default shadow. Use lavender fill for featured states.
- **Inputs:** white, 2px lilac border, purple focus halo; never rely on placeholder text as a label.
- **Avatars:** circular, coloured, white rim, light neutral outline.
- **Status:** always combines text with colour (for example, `READY!`, not only a green dot).

## Typography and accessibility

Use the rounded system sans stack at 15px/700 for body copy. Use 900-weight headings with tight tracking. Interactive targets must be at least 44px tall, with a cyan 3px keyboard focus ring. Honour reduced-motion preferences.

## Future implementation rule

New screens and components must import and use the shared CSS tokens above. Do not introduce unrelated radii, shadows, timing curves, or off-palette colours without updating this document and `redesign.css` together. Avoid dark containers, heavy shadowed cards, and all-caps labels except for genuinely compact labels.
