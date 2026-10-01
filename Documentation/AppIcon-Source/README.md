# Angrove app icon

The editable Icon Composer document is `Angrove-iOS/AngroveAppIcon.icon`.
The Xcode target selects `AngroveAppIcon` in both Debug and Release.

The painted leaf is a separate foreground group with a subtle shadow. The
background group switches between opaque light and dark dotted SVGs using
appearance-specific layer opacity. Translucency and specular effects are disabled
to preserve the painted artwork.

Source assets came from the owner's Desktop:

- `leaf.png`: `angrove-logo.png`, with transparency preserved.
- `dark-background.svg`: `darkmode-background.svg`, including cream dots at 55% opacity.
- `light-background-original.png`: the provided light export, retained for reference.
- `light-background.svg`: the same dot geometry as the dark export, recolored to
  cream (#F3EEE2) with brown (#614C40) dots at 80% opacity to match Figma.

The leaf remains at its native 814 × 864 size, centered within the 1024 × 1024 icon.
The old `AppIcon.appiconset` remains available but is no longer selected.
