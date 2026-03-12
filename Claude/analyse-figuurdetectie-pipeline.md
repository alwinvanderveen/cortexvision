# Analyse Figuurdetectie Pipeline — Conclusies & Aanbevelingen

**Datum:** 2026-03-12
**Context:** DocLayout-YOLO (ONNX Runtime) is geïntegreerd als primaire figuurdetector. Model laadt en draait succesvol. Analyse op basis van testresultaten en Codex-aanbevelingen.

---

## Huidige Situatie

### Wat werkt
- DocLayout-YOLO laadt via ONNX Runtime in Swift (72MB, CPU, ~2.8s init, <1s inference)
- Propinion circulaire foto: gedetecteerd met 96.7% confidence, correcte bounds
- Tekstregio's worden betrouwbaar geclassificeerd (title, plain_text, captions)
- Bounds zijn correct genormaliseerd (0..1), XYXY output correct geparsed
- 183 van 189 tests slagen, coverage 83%

### Wat niet werkt
| Test | Probleem | Root Cause |
|------|----------|------------|
| DenHaagDoet hero banner | 0 figuren gedetecteerd | Model classificeert hero banner als achtergrond met tekst — geen "figure" label |
| BlackBackground figuur | 0 figuren gedetecteerd | Foto met tekst-overlay is geen standaard documentfiguur voor het model |

### Kern-inzicht
DocLayout-YOLO is getraind op **documenten** (papers, artikelen, rapporten). Het excelleert in het herkennen van figuren, tabellen en tekst in documentcontext. Maar **webpagina-captures** bevatten hero banners, foto-achtergronden en mixed media die buiten het trainingsdomein vallen. Dit is geen bug in het model — het is een domeinmismatch.

---

## Analyse Codex-aanbevelingen

### Aanbeveling 1: Fallback-keten (P0) — DIRECT RELEVANT

**Conclusie:** Dit is de kernoplossing. De bestaande Vision-pipeline (saliency + instance mask) detecteert precies wat DocLayout-YOLO mist:
- Instance mask vindt de persoon in DenHaagDoet
- Saliency vindt de visueel opvallende regio in BlackBackground

**Aanbeveling:** Implementeer een hybride pipeline waar Vision als fallback dient wanneer DocLayout-YOLO geen figuren vindt. Dit is geen concessie — het is de juiste architectuur voor maximale recall (Gate 8).

### Aanbeveling 2: Boundary refinement (P1) — BEHOUDEN

**Conclusie:** De bestaande boundary-code (`autoCropWhitespace`, `tightenByVariance`, `TextFigureRelation` classifier) is solide en bewezen. DocLayout-YOLO levert al nauwkeurige bounds, dus boundary refinement wordt eenvoudiger voor model-detecties. Voor Vision-fallback detecties blijft de volledige refinement-keten nodig.

**Aanbeveling:** Behouden als-is. Geen wijzigingen nodig in deze fase.

### Aanbeveling 3: Expand-logica integreren (P1) — HERBEOORDELEN

**Conclusie:** `snapToEdges`, `directionalExpand`, `expandToIncludeSubjects` waren nodig omdat saliency onnauwkeurige bounds gaf. DocLayout-YOLO geeft nauwkeurige bounds, waardoor deze functies voor model-detecties overbodig worden. Ze blijven relevant voor Vision-fallback detecties.

**Aanbeveling:** Niet actief integreren in de DocLayout-YOLO tak van de pipeline. Wel behouden voor de Vision-fallback tak. Opruimen in Fase 3 (legacy code verwijdering).

### Aanbeveling 4: DocLayout multi-pass (P1) — LATER

**Conclusie:** Multi-pass inferentie (origineel + contrast-variant) en tiled inferentie zijn interessante optimalisaties, maar voegen complexiteit toe voordat de basispipeline staat. Class-specifieke confidence thresholds zijn wel direct toepasbaar.

**Aanbeveling:** Eerst de hybride pipeline implementeren en valideren. Multi-pass alleen als de hybride aanpak onvoldoende recall levert op het volledige testbeeld-corpus. Class-specifieke thresholds kunnen direct mee.

### Aanbeveling 5: OCR word-box robuustheid (P2) — PARKEREN

**Conclusie:** Huidige OCR werkt voldoende voor tekst-exclusie. Geen falende tests gerelateerd aan OCR-kwaliteit.

**Aanbeveling:** Pas oppakken als er concrete problemen optreden.

---

## Aanbevolen Architectuur: Hybride Pipeline

```
Capture Image
     │
     ▼
┌─────────────────────────────┐
│  Pass 1: DocLayout-YOLO     │  ← Primaire detectie (documenten, rapporten)
│  ONNX Runtime, ~1s          │
│  Output: figures, tables,   │
│          text regions        │
└──────────┬──────────────────┘
           │
     ┌─────┴─────┐
     │ Figuren    │ Geen figuren
     │ gevonden?  │ gevonden
     ▼            ▼
  Direct      ┌─────────────────────────────┐
  naar        │  Pass 2: Vision Fallback     │  ← Vangnet (hero banners, foto's)
  Pass 3      │  Saliency + Instance Mask    │
              │  Bestaande dual-pipeline     │
              └──────────┬──────────────────┘
                         │
                         ▼
              ┌─────────────────────────────┐
              │  Pass 3: Refinement          │  ← Boundary + extractie
              │  - TextFigureRelation        │
              │  - autoCropWhitespace        │
              │  - tightenByVariance         │
              │  - trimTextFromRegion        │
              └──────────┬──────────────────┘
                         │
                         ▼
                  DetectedFigure[]
```

### Waarom deze architectuur

1. **Kwaliteit eerst (Gate 8):** Twee detectiemethoden dekken elkaars blinde vlekken
2. **Performance acceptabel:** Extra Vision-pass alleen als DocLayout-YOLO niets vindt (~20% van captures)
3. **Bestaande code hergebruik:** Vision-pipeline en refinement-code zijn bewezen en getest
4. **Testbaar:** Elke pass is onafhankelijk testbaar
5. **Uitbreidbaar:** Multi-pass inferentie (aanbeveling 4) kan later als Pass 1b worden ingevoegd

### Verwachte impact op falende tests

| Test | Verwachting |
|------|------------|
| DenHaagDoet hero banner | PASS — Instance mask vindt persoon, saliency vindt hero regio |
| BlackBackground figuur | PASS — Saliency vindt visueel opvallende content |
| Bestaande figuurdetectie tests | Geen regressie — DocLayout-YOLO vangt standaard cases |

---

## Brainstorm-items — Geparkeerd

De volgende suggesties uit de Codex zijn waardevol maar prematuur:

| Item | Reden om te parkeren |
|------|---------------------|
| Expert-router per scene-type | Over-engineering; hybride pipeline dekt voldoende scenario's |
| Learned post-processor | Vereist trainingsdata en labeling die we niet hebben |
| Weighted box fusion | Relevant bij model-ensemble; nu hebben we sequential fallback, geen parallel ensemble |
| Gebruikersfeedback terugvoeden | Productfeature voor na UC-7 |
| Segmentatiemodellen | Pas overwegen als hybride pipeline onvoldoende kwaliteit levert |
| Benchmarkset met golden standard | Waardevol maar vereist handmatig gelabelde ground truth |

---

## Concrete Vervolgstappen

1. **Hybride pipeline implementeren** — DocLayout-YOLO als primair, Vision als fallback
2. **Valideren** — `make test` moet DenHaagDoet + BlackBackground PASS maken
3. **Bestaande tests behouden** — geen testaanpassingen (Gate 7)
4. **Class-specifieke thresholds** — lagere confidence voor `figure`/`table` (0.15) dan tekst (0.25)
5. **Fase 3: Legacy opruiming** — verwijder ongebruikte saliency-functies na validatie
