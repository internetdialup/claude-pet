# The release pages

Every release page on GitHub is laid out the same way, like a store page: the
banner, a row of links, a few picture tiles, then the full patch notes. This
file is the template and the rules, so the next release looks like the last
five without anyone reverse-engineering them.

## The one invariant

**Everything below the `---` divider is the release's `CHANGELOG.md` section,
byte for byte.** The changelog and the release pages are the same text in two
places, and they move together — edit both or neither. The decoration above
the divider is the only thing this file owns. If the patch notes on a page
ever differ from the changelog section, one of them is stale, and that signal
is worth more than any layout.

## The template

```markdown
<img src="https://raw.githubusercontent.com/internetdialup/claude-pet/main/docs/media/release-banner.png" width="100%" alt="Claw'd mid-ollie on a warm white ground, beside the words Claude Pet">

<p align="center"><a href="⟨CTA-URL⟩"><strong>⬇️ ⟨CTA-LABEL⟩</strong></a> &nbsp;·&nbsp; <a href="https://github.com/internetdialup/claude-pet#readme"><strong>📖 Meet him in the README</strong></a> &nbsp;·&nbsp; <a href="https://github.com/internetdialup/claude-pet/blob/main/CHANGELOG.md"><strong>🧾 Full changelog</strong></a></p>

### Highlights

<table><tr>
<td width="200" align="center"><img src="https://raw.githubusercontent.com/internetdialup/claude-pet/main/docs/media/⟨TILE⟩" width="160"><br><strong>⟨CAPTION⟩</strong><br><sub>⟨one line⟩</sub></td>
</tr></table>

---

⟨the release's CHANGELOG section, byte for byte⟩
```

## Rules that keep it from breaking

- **Release bodies render every newline as a line break**, like comments do.
  A wrapped sentence in the decoration becomes a broken line on the page. So
  every HTML block above the divider is written on ONE line, however long,
  and blank lines separate the blocks. The patch notes below the divider are
  exempt by construction: their 80-column wrapping comes from the changelog
  and renders fine as markdown.
- **Image URLs are absolute `raw.githubusercontent.com/...`/`main` links**,
  because a release page has no repo context of its own. Which means the
  asset must be merged to `main` before any page references it. Check with
  `curl -sI <url>` for a 200 first.
- **The CTA is honest.** A release that carries its own `.dmg` links it
  directly (`…/releases/download/vX.Y.Z/ClaudePet-X.Y.Z.dmg`). A release
  with no asset links `…/releases/latest` and calls it "Download the latest
  build" — never that version's build, because that build does not exist.
- **Two to four tiles**, from committed `docs/media/` only, each showing
  something *that release* shipped. The banner already carries the ollie, so
  no ollie tile. It is fine for a GIF to appear on two pages when both
  releases genuinely touched it.
- **`gh release edit` overwrites.** Back up first:
  `gh release view vX.Y.Z --json body -q .body > backup.md`, then
  `gh release edit vX.Y.Z --notes-file page.md`. Titles stay as they are.

## Which tiles went where

| Release | Tiles |
| :--- | :--- |
| v1.3.0 | flourish-jump.gif · flourish-wave.gif · roster.png · party.gif |
| v1.4.0 | costumes.gif (wide row) · cooking.gif · done.gif |
| v1.5.0 | thinking.gif · party.gif · working.gif |
| v1.5.1 | nudging.gif · needsAttention.gif |
| v1.6.0 | flourish-kickflip.gif · flourish-cruise.gif · sleeping.gif · facts.png |

## The banner itself

`docs/media/release-banner.png`, 1280×320, rendered by `--render-reel` with
everything else and held to the same byte-for-byte determinism test. The
frame is the ollie at the top of its float, derived from the animator's own
timing (`ReelRenderer.ollieApex`) so a retimed trick moves the banner with
it, and a test pins that the sampled instant is actually airborne.

---

[← Back to the README](../README.md)
