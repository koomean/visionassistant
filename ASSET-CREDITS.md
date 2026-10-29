# Asset credits

## Moon

`assets/moon.webp` is adapted from the full-Moon still in **Moon Phase and
Libration, 2021**, NASA's Scientific Visualization Studio (SVS 4874).

- Credit: NASA's Scientific Visualization Studio. Visualization by Ernie Wright;
  produced by David Ladd; scientific consulting by Noah Petro.
- Project page: <https://svs.gsfc.nasa.gov/4874/>
- Original image: <https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004874/phase_full.3492.tif>
- Changes: transparent margin cropped; resized from 3240 × 3240 to
  1400 × 1400 pixels; encoded as WebP. The original alpha channel is retained.
- The SVS states that its content is public domain unless otherwise noted:
  <https://svs.gsfc.nasa.gov/help/#frequently-asked-questions>.
- NASA media guidelines: <https://www.nasa.gov/nasa-brand-center/images-and-media/>.

The image is used as decorative lunar imagery, not as an indication of NASA
endorsement or a real-time Moon phase.

## Social preview

`assets/social.jpg` is a 1200 × 630 screenshot of the website’s English lunar hero,
composed from the credited Moon image, fonts, and original website design.
It is a share preview, not a screenshot of the iPhone app.

## LunaV screenshots

These images come from the project owner's local LunaV app previews. They have
been resized to 720 × 1565 pixels and encoded as WebP. No app interface or results
have been fabricated or composited.

### Current version 3.0.0 (build 3)

The following previews were captured on **29 October 2026** from the current
version 3.0.0 (build 3) interface, including its separate app-language setting and
About page.

| Website asset | Original preview |
| --- | --- |
| `assets/app-v3-camera-en.webp` | `App/Preview/V3-Camera-English.png` |
| `assets/app-v3-answer-en.webp` | `App/Preview/V3-Conversation-English.png` |
| `assets/app-v3-settings-en.webp` | `App/Preview/V3-Settings-English.png` |
| `assets/app-v3-about-th.webp` | `App/Preview/V3-About-Thai.png` |
| `assets/app-v3-about-en.webp` | `App/Preview/V3-About-English.png` |

Switching the app interface to English does not translate existing questions or
answers. The English conversation preview therefore retains its original Thai
question and source OCR text; these have not been translated or replaced for the
website.

### Earlier lunar-interface previews

These four images were also captured on **29 October 2026**, before the version
3.0.0 language/About update. They show the earlier lunar-themed interface and are
retained as historical assets. A text-grouping preview may still illustrate that
specific tool; it is not a screenshot of the current version 3.0.0 interface.

| Website asset | Original preview |
| --- | --- |
| `assets/app-camera-20261029.webp` | `App/Preview/Website-Camera.png` |
| `assets/app-answer-20261029.webp` | `App/Preview/Website-Inline-Answer.png` |
| `assets/app-settings-20261029.webp` | `App/Preview/Website-Settings.png` |
| `assets/app-text-sources-20261029.webp` | `App/Preview/Website-Text-Sources.png` |

All these previews are from iOS Simulator. Conversation and text-grouping images
show OCR of a synthetic test fixture. They do not establish live iPhone camera,
microphone, visual-model, or LiDAR performance. Still images do not demonstrate
the hold–talk–release gesture or cancellation timing. Camera previews explicitly
show the Simulator test-image state.

The unversioned `assets/app-*.webp` previews remain in the repository as historical
assets from 20–21 October 2026.

## Fonts

Fonts are served from this repository; website visitors do not need to request
them from Google Fonts or a third-party font CDN.

- **Manrope**, variable weight font: <https://github.com/google/fonts/tree/main/ofl/manrope>.
  Original: `Manrope[wght].ttf`; converted to `assets/fonts/manrope.woff2`.
  SIL Open Font License 1.1 retained in `assets/fonts/Manrope-OFL.txt`.
- **Noto Sans Thai**, variable width/weight font:
  <https://github.com/google/fonts/tree/main/ofl/notosansthai>.
  Original: `NotoSansThai[wdth,wght].ttf`; converted to
  `assets/fonts/noto-sans-thai.woff2`.
  SIL Open Font License 1.1 retained in `assets/fonts/NotoSansThai-OFL.txt`.

The NASA imagery and font licenses are separate from the repository's AGPL
license. See the files and source links above for their respective terms.

## GitHub mark

The GitHub mark identifies buttons linking to this project on GitHub. GitHub and its logo are trademarks of GitHub, Inc.; they are separate from the project’s original artwork and AGPL licence. [GitHub brand reference](https://brand.github.com/foundations/logo).

## Intro and interface motion

The LunaVision-to-LunaV introduction uses the existing crescent-and-star website
symbol, as selected by the project owner. The wordmark, animated wavy red pen stroke,
`assets/red-pen.svg`, and transition to the header are original
SVG/CSS/JavaScript interface work.
The current iPhone app icon also uses the same crescent-and-star geometry. The
app implements its introduction natively in SwiftUI, while the website uses
SVG/CSS/JavaScript. Scroll motion respects reduced-motion settings; the introduction can be replayed, with no on-screen skip button.
