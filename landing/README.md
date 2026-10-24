# Spottr landing page

This is Misha's static landing page, with availability, accessibility and copy corrections. It needs no build step or service credentials.

From the repository root:

```bash
python3 -m http.server 8149 --bind 127.0.0.1 --directory landing
```

Open `http://127.0.0.1:8149/`. Any static host can serve the contents of `landing/`; include `assets/`. No other repository folders or `.env` files need to be served.

The five PNGs in `assets/` are unchanged copies of the existing `design/` previews. They are labelled interface concepts with sample data, including the illustrated Watch readings. They are not current native screenshots or evidence of device acceptance. The images retain their aspect ratios and explicit source dimensions.

Keep both **TestFlight soon** buttons disabled until a verified public test link exists. App Store Connect record creation does not supply that link. Voice coaching is labelled planned; pose counting, local history and on-screen cues are distinguished from optional online Gemini requests and workout uploads.

Before contributing, check the hero, feature cards, How It Works and availability/footer at desktop and narrow widths. Use the keyboard to reach Skip to content and section links. Confirm image loads, visible focus, reduced-motion behavior, and the two disabled availability controls. Preserve the restrained white/black layout and existing green accent. The page loads local assets only and starts no camera, microphone, voice or provider request.
