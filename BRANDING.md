# Brand artwork and theme

The shop artwork supplied as Robinas.jpg is the visual authority. Its original JPEG is preserved byte for byte at priv/static/brand/robinahs-original.jpg. Logo, launch screen and icon exports use the same artwork, without redrawing or cropping it.

Palette: royal blue #0737B8, navy #061C64, orange #FF9B00, gold #FFC126, cyan #00CDEE, warm ivory #FAF8F3. Use blue for navigation, orange with navy text for primary actions, cyan for selected-state details, and ivory for readable product and stock surfaces.

Assets include 32px and 48px browser icons in favicon.ico, PNG icons at 32, 48, 180, 192 and 512px, and a 512px maskable icon with padding to protect the artwork. The 180px icon is used for Apple touch shortcuts. site.webmanifest defines app icons, standalone display and launch colours.

The launch screen appears on the first full page load in each tab. It dismisses when the page loads, with a 2.5 second fallback; it does not wait for a LiveView socket connection. It is hidden when JavaScript is disabled and when printing. OS-managed launch appearance depends on the browser and operating system. No offline cache or payment integration is introduced by branding.

The stock document is a review source: its quantities and amounts do not establish verified available stock or selling unit prices. Do not post them as actual inventory before confirmation.
