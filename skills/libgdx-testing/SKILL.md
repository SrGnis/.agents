---
name: libgdx-testing
description: >
  Headless Scene2D / libGDX UI testing without GL: font construction, actor-tree
  bounds tests, layout budgets, and the gdx traps that waste hours (Cell.defaults
  recursion, protected FileHandle, renamed font resources). Use when testing
  libGDX widgets off-screen, asserting UI layout bounds, building Scene2D
  screens in unit tests, or debugging StackOverflowError in Table/Cell.
  Trigger on phrases like "scene2d test", "headless gdx", "widget bounds",
  "libgdx test without GL", "gdx stack overflow cell".
license: MIT
compatibility: opencode
metadata:
  type: testing
---

# libGDX headless UI testing

Scene2D **layout runs without GL** — widgets are plain objects after construction,
so the UI-testing policy's highest-ROI gate (bounds assertions on the actor tree)
is fully unit-testable. The obstacles are all in *construction*; here is the recipe
that works (verified on gdx 1.13.1 / JDK 25).

## The traps (each costs an hour if unknown)

1. **`Cell.defaults()` infinitely recurses when `Gdx.files == null`.**
   `Cell()` calls the static `Cell.defaults()`, which rebuilds its cached default
   cell whenever `Gdx.files` *changes identity* — and with `Gdx.files` null the
   guard `files == null || files != Gdx.files` never clears. `StackOverflowError`
   alternating `Cell.<init>` / `Cell.defaults`. **Fix: set `Gdx.files` to any
   non-null `Files` before touching Table/Label** — only its identity is compared
   in that path. A tiny stub returning null handles is enough.

2. **`FileHandle`'s constructor is protected.** Only `Gdx.files` factories create
   them, so a test cannot `new FileHandle(path, FileType.Classpath)`. Either
   implement `Files` in the stub (classpath() via a reflective constructor call)
   or build the handle reflectively once. Classpath `read()` itself is pure
   (`getResourceAsStream`) and needs no `Gdx.files`.

3. **`Texture` needs GL — except the protected no-arg `Texture()`.** Fonts need a
   `TextureRegion`; the region is only used for UV math, never drawing. A trivial
   `class EmptyTexture extends Texture { EmptyTexture() { super(); } }` with
   `getWidth()/getHeight()` overridden to 1 works headless.

4. **The bundled font was renamed.** gdx 1.13 ships `lsans-15.fnt`, not
   `arial15.fnt` (license change). `BitmapFontData` is a *nested* class:
   `BitmapFont.BitmapFontData`.

```java
// the whole recipe
Gdx.files = filesStubWithClasspath();            // non-null: kills the Cell recursion
FileHandle fnt = reflectiveFileHandle("com/badlogic/gdx/utils/lsans-15.fnt",
        Files.FileType.Classpath);
BitmapFont font = new BitmapFont(new BitmapFont.BitmapFontData(fnt, false),
        new TextureRegion(new EmptyTexture()), true);
```

## The bounds gate

Test the **widget**, not the screen: build the widget, `setSize(w, h)`,
`update(model…)`, `validate()`, then walk the actor tree with **accumulated
offsets** (children coordinates are parent-relative) asserting every actor is
inside `[0,w] × [0,h]`. Run at **several viewport sizes** (e.g. 320/800/1920 ×
200/600/1080) plus a deliberate **overflow boundary case** (more rows than fit:
clipped rows must collapse into a "N more…" indicator, never draw off-screen).

Layout rules that make bounds hold **by construction** (found by this gate):

- **anchor content `top-left`** (`table.align(Align.topLeft)`) — the Table default
  centers, so over-wide content escapes on *both* sides (x becomes negative).
- **budget rows exactly** from the real line height (`new Label("X", style)
  .getPrefHeight()`), and count *every* line — category headers and overflow
  indicators too. One un-budgeted line shoves the footer off-screen by exactly
  one line — the classic off-by-one this gate catches.
- **truncate text by measurement** (`GlyphLayout` width) with an ellipsis; cell
  `maxWidth` does *not* shrink a label's preferred width.

## Mutation-check the gate itself

A bounds test can be vacuous (e.g. asserting on a stale copy of a row). Before
trusting it, flip the rule it guards (e.g. remove the anchoring or the budget)
and watch it go red — the standard "prove a test can fail" discipline, applied
to visual code.

## What still needs GL

`Texture`, `Pixmap` (natives), and therefore `SpriteBatch`/`Stage.draw()`. Keep
draw-time paths behind the host (app/scenario) and inject an optional
`Drawable` background (null in tests). Golden screenshots remain the separate
rendering gate — layout gates do not see pixels.
