# Problem: Inpainting Mask Strategy for UI Elements on Photos

## Context

CortexVision is a macOS screen capture app that detects text and figures (photos, charts) in captured images. When the user excludes overlay-text (text that sits on top of a photo), the app uses LaMa inpainting (ONNX, 512×512) to remove the text from the figure and replace it with surrounding content.

**Reference image:** `Image/testMultipleImageNews2.png` (1214×2504, news page with two photos)

## What works

- LaMa model loads and runs correctly (198MB ONNX, ~1s inference on Apple Silicon)
- Text-only inpainting works well: black/white text on photos is cleanly removed
- Orientation is correct (Y-flip between Vision bottom-left and CGImage top-left coords resolved)
- Figure 1 (military personnel, top of page): text removal quality is excellent (avgDiff 1-29 from surroundings)
- Original figure restore on re-include works

## The problem

**Figure 2** (dog on airport runway, bottom of page) has a **red oval "Video" button** overlaid on the photo. The button contains white "Video" text. When the user excludes the overlay-text:

1. The **text glyphs** ("Video") are correctly removed by the text mask + LaMa
2. The **red button background** remains visible because it's not covered by the text mask
3. The text mask only covers the OCR bounding box (70×25px) + padding, not the entire button (~146×125px)

### Visual layout of the button area

```
                    ┌── airplane body (white/gray, RGB ~200,200,210) ──┐
                    │                                                   │
                    │    ┌── red oval button (RGB ~196,0,1) ──┐        │
                    │    │                                     │        │
                    │    │         "Video" (white text)        │        │
                    │    │                                     │        │
                    │    └─────────────────────────────────────┘        │
                    │                                                   │
                    ├── runway/tarmac (gray, RGB ~90,90,95) ───────────┤
```

Key observations from pixel analysis:
- The text "Video" is positioned in the **upper half** of the button, not centered
- Button size: ~146×125px. Text size: ~70×25px
- The text mask border touches red pixels only at the **bottom edge**
- Top edge of mask: airplane body (white/gray) — NOT red
- Left/right edges of mask: airplane body (white/gray) — NOT red
- The button is asymmetric relative to the text

### Attempted solutions and why they failed

| Approach | Result | Problem |
|----------|--------|---------|
| **Fixed padding** (8px) | Text removed, button stays | Padding too small for 125px button |
| **Proportional padding** (0.6× text height = 15px) | Text removed, button stays | Same — button extends ~100px beyond text |
| **Large proportional padding** (5× text height = 125px) | Button partially removed, **but dog/airplane/tail damaged** | Rectangular mask covers too much photo content |
| **UI element expansion** (grow rect while color differs from figure edge bg) | Over-expanded, 40% of figure masked | Figure edge background ≠ local background; airplane body is different from runway |
| **Saturation-based pixel detection** (mark high-saturation pixels) | Too many false positives in photo content | Military uniforms, colored objects in photos also have high saturation |
| **Magic wand flood-fill** from mask border | Only 190 red pixels reached | Button's red color only touches mask at bottom edge; top/sides are airplane white |

### Root cause

The fundamental issue is a **mismatch between what needs to be masked and what the OCR bounding box provides**:

- OCR gives tight bounds around **text glyphs** only
- UI elements (buttons, badges, labels) have **backgrounds that extend beyond the text** in an arbitrary shape
- The text position within the UI element is **not centered** — it can be offset to any corner
- A rectangular padding expansion around the text inevitably covers **photo content** that should be preserved
- Pixel-based detection (saturation, color) produces **false positives** in complex photo content

## What we need

A mask generation strategy that:

1. **Removes the text** (OCR bounds — this works)
2. **Removes the UI element background** (red button — this doesn't work)
3. **Preserves the photo content** (airplane, dog, runway — this gets damaged)
4. Can be **objectively verified** via pixel-level before/after comparison in tests

## Constraints

- 100% on-device, no cloud APIs
- LaMa model: fixed 512×512 input, single-pass (multi-pass possible but slow)
- ONNX Runtime already in project (DocLayout-YOLO + LaMa)
- Gate 8: detection quality over performance
- Must work for various UI elements: red buttons, blue badges, green labels, etc.
- Must NOT damage surrounding photo content

## Test infrastructure

The test `realImageInpaintNews2` in `InpaintingDebugTests.swift` provides objective pixel-level verification:
- Compares original vs inpainted figure pixel by pixel
- Measures: % pixels changed, % preserved, avg preserve diff, red pixel reduction
- Current passing thresholds: >70% preserved, <30% changed, avg preserve diff <5

## Files involved

- `Sources/CortexVision/Analysis/FigureInpaintingPipeline.swift` — orchestrates mask → crop → inpaint → composite
- `Sources/CortexVision/Analysis/TextMaskGenerator.swift` — generates binary mask from OCR bounds
- `Sources/CortexVision/Analysis/LaMaInpainter.swift` — ONNX Runtime wrapper for LaMa model
- `Tests/CortexVisionTests/InpaintingDebugTests.swift` — visual verification tests
- `Image/testMultipleImageNews2.png` — reference test image
