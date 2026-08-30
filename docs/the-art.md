# The art

Claw'd is Anthropic's mascot. He is **drawn, not imported** — a parametric rig
rasterised into a 32×32 indexed buffer each frame
([`Sources/ClaudePet/View/`](Sources/ClaudePet/View/)). Flat colour, no outline,
no shading ramp, whole-pixel motion. He is not a sprite sheet, so a new pose is a
few numbers rather than a new asset, and the app icon is rendered from the same
rig so the two can never drift apart.

<div align="center">
  <img src="docs/media/props.png" width="768" alt="All seventeen props in one strip: sparkles, terminal, check, bang, servers, mug, plan, hard hat, phone, fire, glasses, star, joystick, shades, and three skateboards">
</div>

<p align="center"><em>Every prop, from the same rig — no sprite sheet anywhere.</em></p>

This project is unofficial and not affiliated with or endorsed by Anthropic.
MIT — see [LICENSE](LICENSE); the trademark and character-design note is in
[NOTICE.md](NOTICE.md).

---

[← Back to the README](../README.md)
