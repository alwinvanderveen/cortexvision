# Solutions: Inpainting Mask Strategy for UI Elements on Photos

Companion to `PROBLEM-inpainting-mask-strategy.md`.

## Root Cause (Deeper)

The current approach starts from the text mask border and tries to grow outward into color-matching pixels. This fundamentally requires that the UI element **surrounds** the text mask border on all sides. When the text is offset within the button (top-aligned in the "Video" case), the approach breaks down structurally. No amount of threshold tuning will fix this, because the spatial assumption is wrong.

---

## Approach A: Two-Pass Inpainting

**How it works:**
1. Pass 1: Inpaint using tight text-only mask. "Video" text disappears; red button background remains as a now-solid red blob.
2. Pass 2: Analyze the inpainted result for non-photo anomalies (solid-color blobs). Generate a second mask. Inpaint again.

**Strengths:**
- Decouples two distinct problems: text removal and UI-element removal
- After pass 1, the button becomes a solid red oval — trivially detectable via connected-component analysis
- Text inpainting is already proven to work

**Weaknesses:**
- Two LaMa inference passes (~2s total). Per Gate 8 (quality > performance) this is acceptable
- Relies on pass 1 producing a sufficiently clean solid-color blob
- LaMa might introduce texture/gradient that makes blob detection harder

**Assessment: Strong candidate.** Key insight is correct — removing text first makes the button trivially detectable.

---

## Approach B: Semantic Segmentation for Mask Generation

**How it works:**
- Use a pre-trained model to segment UI overlays from photo content
- Options: custom ONNX model, or Apple's VNGenerateForegroundInstanceMaskRequest

**Strengths:**
- Model-based detection is the most robust long-term solution

**Weaknesses:**
- `VNGenerateForegroundInstanceMaskRequest` detects photographic subjects (people, animals), NOT UI elements
- No readily available ONNX model for "UI overlay element segmentation"
- Training a custom model requires a substantial dataset that doesn't exist
- Another ONNX model adds to app size (already 198MB LaMa + 72MB DocLayout-YOLO)

**Assessment: Over-engineered.** No suitable off-the-shelf model exists.

---

## Approach C: Color-Space Analysis with Connected Components (on original)

**How it works:**
- Convert figure crop to HSV, threshold on saturation, connected-component analysis
- Filter by proximity to text, compactness, size

**Strengths:**
- No additional model needed, works in existing pipeline

**Weaknesses:**
- This is a refined version of the already-failed saturation-based detection
- Text cuts through the button, making it a non-solid shape with white text mixed in
- Colorful photo content near text (flowers, neon signs) would produce false positives

**Assessment: Fragile.** Same fundamental weakness as iterations 2-6 in the problem doc.

---

## Approach D: Difference-Based Detection After Initial Inpaint

**How it works:**
- Inpaint with text mask, compare original vs result, detect remaining anomalies

**Strengths:**
- Uses LaMa output as verification signal

**Weaknesses:**
- Button pixels are OUTSIDE the mask → identical in original and inpainted → comparison gives zero information
- Only adds value if you inpaint a larger region first, which is the "large mask damages photo" problem

**Assessment: Does not help.** Comparison gives no new information about unmasked regions.

---

## Approach E: Accept Limitation

**How it works:**
- Remove text only, leave button background
- Users manually adjust overlay bounds via UC-5a interactive editing

**Strengths:**
- Simple, UC-5a already provides interactive editing

**Weaknesses:**
- Does not meet quality expectation (Gate 8)
- Poor UX for every button/badge encountered

**Assessment: Fallback only**, not primary strategy.

---

## Approach F: Two-Pass with HSV Blob Detection on Inpainted Result ⭐ RECOMMENDED

**Hybrid of A and C.** The key insight: Approach C fails on the original image because the text cuts through the button. After Pass 1 (text removed), the button becomes a **solid, compact, high-saturation blob** — the ideal target for connected-component analysis.

### How it works

1. **Pass 1:** Run LaMa with text-only mask (existing, proven). Text is removed. Red button is now a solid red oval (LaMa fills text area with surrounding red).

2. **Blob detection on Pass 1 result:**
   - Convert inpainted figure crop to HSV
   - Binary mask: saturation > 0.5 AND value > 0.3
   - Connected-component analysis (BFS flood-fill)
   - Filter components by:
     - **Proximity:** Must overlap or be adjacent to a text bound (within 2× text height)
     - **Compactness:** area / bounding-box area > 0.5 (solid shapes, not texture)
     - **Size:** 100–50000 pixels (a button, not full-screen)
     - **Not already masked:** Mostly outside original text mask

3. **Pass 2:** Merge blob masks with original text mask. Run LaMa on the **original** figure crop (not pass 1 result) with expanded mask. This avoids compounding artifacts.

4. **Fast path:** If no blobs detected → return pass 1 result (no second pass, saves ~1s).

### Why this works

- After text removal, the button is a solid blob — no white text breaks it up
- Connected-component analysis on a solid blob produces a clean, tight component
- Proximity-to-text filter eliminates virtually all false positives
- Compactness filter excludes textured photo regions (trees, grass, skin)
- Using original image for pass 2 prevents artifact compounding

### Why previous approaches failed and this won't

| Previous approach | Why it failed | Why F avoids this |
|---|---|---|
| Rectangular padding | Damages photo in all directions | Only masks the blob shape, not a rectangle |
| Saturation on original | Text breaks the blob → non-contiguous | Text removed first → solid blob |
| Magic wand from mask border | Only bottom edge touches red | Not dependent on mask-border connectivity |
| UI element expansion | Grows into photo content | Connected-component with size/compactness filters |

### Performance

- Two LaMa passes: ~2s total on M5 Max (acceptable per Gate 8)
- HSV conversion + connected components: ~10ms for 512×512 (negligible)
- Fast path (no blobs): same speed as current single-pass

### Architecture fit

- `FigureInpaintingPipeline.removeText` already handles crop/resize/inpaint/composite
- Two-pass logic fits inside this method
- `TextMaskGenerator` extended with blob mask merging
- No new models, no new dependencies
- Replaces the current `enhanceMaskWithUIElements` method

### Test strategy

**Unit tests (blob detection):**
- Synthetic: gray background + red oval (text removed) → detected
- Synthetic: colorful photo, no text → zero blobs near text bounds
- Synthetic: red blob far from text → filtered by proximity

**Integration (existing):**
- `realImageInpaintNews2`: `redReduction > 80%`, `preservedPct > 70%`, `avgPreserveDiff < 5`

**Regression:**
- Figure 1 (military, no button): continues to pass with excellent quality
- No second pass triggered → fast path

---

## Approach G: Multi-Scale Mask with Local Background Sampling

**Not explored in depth but worth mentioning:**
- For each text bound, sample a ring of pixels at 2×, 3×, 4× text height distance
- If any ring has a uniform color that differs from the photo content at 5×+ distance, that ring is a UI element boundary
- Generate mask up to the detected boundary

**Strengths:** Single-pass, no model overhead

**Weaknesses:** Complex ring-sampling logic, edge cases with gradients, requires robust "photo vs UI" discrimination at each ring distance

**Assessment:** Viable but less elegant than F. More threshold-dependent.
