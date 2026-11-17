# Asset credits

## Moon

`assets/moon.webp` uses a full Moon image from NASA’s **Moon Phase and Libration, 2021** (SVS 4874).

- NASA’s Scientific Visualization Studio credits Ernie Wright for the visualization, David Ladd for production, and Noah Petro for scientific consulting.
- [Project page](https://svs.gsfc.nasa.gov/4874/) · [Original image](https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004874/phase_full.3492.tif)
- We cropped the transparent margin, resized the image from 3240 × 3240 to 1400 × 1400 pixels, and saved it as WebP with transparency.
- SVS content is in the public domain unless otherwise noted. [SVS FAQ](https://svs.gsfc.nasa.gov/help/#frequently-asked-questions) · [NASA media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)

LunaV uses this image of a past Moon phase as decoration. Its use implies no NASA endorsement.

## Social preview

`assets/social.jpg` is a 1200 × 630 screenshot of the website’s English homepage. It uses the credited Moon image, fonts, and original site design.

## LunaV screenshots

All images below come from iOS Simulator. We resized them to 720 × 1565 pixels and saved them as WebP. The conversation and text-grouping screens show results from a test image. For performance on real devices, see the [test results](https://lunavision.koomean.com/project-status.html?lang=en).

### Version 3.0.0 (build 3)

Captured on **29 October 2026**. This release added the app language setting and About page.

| Website asset | Original preview |
| --- | --- |
| `assets/app-v3-camera-en.webp` | `App/Preview/V3-Camera-English.png` |
| `assets/app-v3-answer-en.webp` | `App/Preview/V3-Conversation-English.png` |
| `assets/app-v3-settings-en.webp` | `App/Preview/V3-Settings-English.png` |
| `assets/app-v3-about-th.webp` | `App/Preview/V3-About-Thai.png` |
| `assets/app-v3-about-en.webp` | `App/Preview/V3-About-English.png` |

The conversation screenshot uses the English interface and keeps the original Thai question and text read from the photo.

### Earlier interface

Also captured on **29 October 2026**, before the 3.0.0 language and About update. The text-grouping image shows the tool in that earlier interface.

| Website asset | Original preview |
| --- | --- |
| `assets/app-camera-20261029.webp` | `App/Preview/Website-Camera.png` |
| `assets/app-answer-20261029.webp` | `App/Preview/Website-Inline-Answer.png` |
| `assets/app-settings-20261029.webp` | `App/Preview/Website-Settings.png` |
| `assets/app-text-sources-20261029.webp` | `App/Preview/Website-Text-Sources.png` |

The older `assets/app-*.webp` files without a version or date come from 20–21 October 2026.

## Fonts

The website serves both fonts locally. Each keeps its SIL Open Font License 1.1.

- [Manrope](https://github.com/google/fonts/tree/main/ofl/manrope) was converted from `Manrope[wght].ttf` to `assets/fonts/manrope.woff2`. Its license is in `assets/fonts/Manrope-OFL.txt`.
- [Noto Sans Thai](https://github.com/google/fonts/tree/main/ofl/notosansthai) was converted from `NotoSansThai[wdth,wght].ttf` to `assets/fonts/noto-sans-thai.woff2`. Its license is in `assets/fonts/NotoSansThai-OFL.txt`.

The NASA imagery and fonts follow their own terms, separate from the site’s AGPL license.

## GitHub logo

The logo marks links to the project on GitHub. The name and logo are trademarks of GitHub, Inc. [GitHub brand guidelines](https://brand.github.com/foundations/logo)

## Opening animation

The website and app share the crescent-and-star symbol. The website’s original artwork includes the LunaVision and LunaV lettering, red pen (`assets/red-pen.svg`), and animation into the header. The site uses SVG, CSS, and JavaScript. The app uses SwiftUI. You can replay the website intro, and scrolling respects reduced-motion settings.
