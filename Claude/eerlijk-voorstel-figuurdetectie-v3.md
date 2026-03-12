# Eerlijk Voorstel: Figuurdetectie v3

**Datum:** 2026-03-12
**Auteur:** Claude Opus
**Status:** VOORSTEL — vervangt architectuurvoorstel v2 en analyse-codex-advies

---

## Waarom ik mijn eerdere voorstellen verwerp

### Voorstel v2 (5 opties A-E): verkeerde framing

Mijn eerdere voorstel presenteerde vijf architectuuropties (edge-detectie, multi-resolution saliency, contour-segmentatie, horizontal band analysis, combinatie) als alternatieven voor de huidige pipeline. Het probleem: al deze opties bouwen voort op of compenseren voor Vision saliency — een signaal dat fundamenteel onbetrouwbaar is gebleken.

De opties proberen een instabiel fundament te repareren in plaats van een stabiel alternatief te kiezen.

### Codex-aligned voorstel (validatie + fallback): lagen op een wrak

De analyse van het Codex-advies leidde tot een voorstel met drie stappen: validatie-pass, band-analyse als fallback, en kwaliteitsmetrics. Bij eerlijke evaluatie:

| Voorstel | Wat het doet | Wat het niet doet |
|----------|-------------|-------------------|
| Validatie-pass (Pass D) | Herkent slechte output en verwerpt het | Produceert geen betere output. Gebruiker ziet 0 figuren i.p.v. 1 foute figuur. |
| Band-analyse als fallback | Tweede kans bij slechte output | Onbewezen, eigen tuning nodig, extra codepath die ook kan falen |
| Kwaliteitsmetrics | Meten hoe slecht het gaat | Nul effect op detectiekwaliteit |

Netto effect op wat de gebruiker ziet: **minimaal tot negatief**. Meer code, meer complexiteit, maar de foto's op de nieuwspagina worden niet betrouwbaarder gedetecteerd.

### Waarom parameter-tuning faalde (3 iteraties)

| Iteratie | Aanpassing | Resultaat |
|----------|-----------|-----------|
| 1 | subjectAnchored penalty >1.5x | Geen effect op kandidaat met 1.46x expansie |
| 2 | Threshold naar 1.2x + contentFit clipping | Walvis beter maar met tekst, hero afgesneden |
| 3 | Agressievere trim + padding limit | Complete regressie: 3 smalle strepen |

Het patroon: elke parameterwijziging verschuift het probleem. De ene capture wordt beter, de andere slechter. Dit is geen tuning-probleem — het is een architectuurprobleem.

### De fundamentele fout in de huidige pipeline

De pipeline begint bij **Vision saliency** als eerste signaal en bouwt daar alles omheen (content map, hypotheses, scoring). Maar Vision saliency is:

1. **Non-deterministisch**: dezelfde content geeft bij elke capture andere regio's (van 0.617×0.276 conf=0.80 tot 0.181×0.227 conf=0.50)
2. **Resolutie-afhankelijk**: test-PNG (625×1259) → 2 saliency regio's; app-capture (1200×2500) → 1 regio
3. **Niet-semantisch**: saliency vindt "visueel opvallend", niet "dit is een foto"

Alles bouwen op een onbetrouwbaar signaal maakt de hele pipeline onbetrouwbaar. Geen hoeveelheid hypothese-scoring, content-mapping of text-trimming kan dat compenseren.

---

## Wat wel werkt: OCR als structureringssignaal

Er is één signaal dat in **elke capture stabiel, deterministisch en betrouwbaar** is: de OCR-output.

Bewijs uit 5 opeenvolgende captures van dezelfde nieuwspagina:

| Capture | Afmetingen | OCR blokken | Tekstposities | Saliency regio |
|---------|-----------|-------------|---------------|----------------|
| #1 | 1200×2522 | 18 | Stabiel (±0.003) | (0.000, 0.400, 0.610, 0.283) |
| #2 | 1210×2508 | 20 | Stabiel (±0.003) | (0.000, 0.356, 0.626, 0.327) |
| #3 | 1206×2502 | 18 | Stabiel (±0.003) | (0.000, 0.407, 0.617, 0.276) |
| #4 | 1204×2506 | 19 | Stabiel (±0.003) | (0.000, 0.396, 0.617, 0.287) |
| #5 | 1198×2502 | 19 | Stabiel (±0.003) | (0.406, 0.415, 0.181, 0.227) |

OCR vindt consistent 18-20 tekstblokken op nagenoeg identieke posities (variatie <0.3%). Vision saliency varieert met factor 3× in grootte en positie.

### De pagina-structuur zit in de tekst

Webpagina's (en documenten) zijn opgebouwd uit afwisselende horizontale banden van tekst en visuele content. De OCR-bounds definiëren deze structuur impliciet:

```
y=1.000 ┌─────────────────────────┐
        │                         │  ← geen tekst = HERO-FOTO
y=0.895 ├─────────────────────────┤
        │ Live | Italiaanse...    │
        │ doden bij aanval...     │  ← tekst = KOPPEN
        │ • Verstappen vreest...  │
        │ • Spoorverkeer...       │
        │ ...                     │
y=0.667 │ Meer Algemeen >         │
y=0.644 │ Nieuwsvideo's           │  ← tekst = SECTION HEADER
y=0.532 ├─────────────────────────┤
        │                         │  ← geen tekst = WALVISFOTO
y=0.510 ├─────────────────────────┤
        │ Indonesiërs begeleiden..│  ← tekst = BIJSCHRIFT
y=0.500 └─────────────────────────┘
```

De foto-regio's zijn simpelweg de **gaten tussen tekstblokken** die groot genoeg zijn om een foto te bevatten. Dit vereist geen saliency, geen content map, geen hypothese-scoring. Het vereist alleen OCR-bounds (die we al hebben) en een minimum hoogte-drempel.

---

## Concreet voorstel: OCR-gap detectie als primair signaal

### Concept

1. Sorteer alle OCR-bounds op Y-positie
2. Bereken de gaten (gaps) tussen opeenvolgende tekstblokken
3. Gaten boven een minimum hoogte (bijv. 5% van de afbeeldingshoogte) zijn kandidaat-figuren
4. De bovenkant van het beeld (boven de eerste tekst) en onderkant (onder de laatste tekst) zijn ook kandidaten
5. Valideer kandidaten met een lichte pixel-check: bevat het gap daadwerkelijk visuele content (niet alleen achtergrond)?
6. Gebruik Vision subject/saliency en DocLayout-YOLO als **bevestiging en verfijning**, niet als primaire bron

### Waarom dit werkt

| Eigenschap | OCR-gap detectie | Huidige pipeline (saliency-first) |
|-----------|-----------------|-----------------------------------|
| Deterministisch | Ja — OCR is stabiel over captures | Nee — saliency varieert per capture |
| Achtergrondkleur-onafhankelijk | Ja — tekst wordt gevonden ongeacht achtergrond | Nee — content map faalt op donkere achtergronden |
| Multi-figuur | Ja — elke gap is een aparte kandidaat | Nee — één groot subject absorbeert meerdere figuren |
| Conceptueel eenvoudig | Ja — gaten tussen tekst = figuren | Nee — 5 passes, 4 hypothese-types, content maps |
| Bouwt op bewezen signaal | Ja — OCR is de meest geteste component | Nee — saliency is de minst betrouwbare component |

### Wat het niet kan

- **Pagina's zonder tekst**: als er geen OCR-bounds zijn, zijn er geen gaten. Fallback naar saliency nodig.
- **Figuren naast tekst** (horizontale layout): gaps zijn verticaal; side-by-side foto-tekst layouts worden gemist.
- **Figuren met tekst-overlay**: tekst OP een foto maakt de gap kleiner of laat hem verdwijnen.
- **Hele kleine figuren**: een icoon tussen twee tekstregels produceert een gap die te klein is.

Voor al deze edge cases blijft de bestaande pipeline (DocLayout-YOLO + Vision) als fallback beschikbaar.

### Implementatie-impact

| Aspect | Impact |
|--------|--------|
| Nieuwe code | ~100-150 regels: `OCRGapAnalyzer` klasse |
| Wijziging bestaande code | `FigureDetector.detectFigures()` gebruikt gaps als primaire kandidaten |
| Bestaande tests | Ongewijzigd — gap-analyse produceert dezelfde of betere bounds |
| Nieuwe tests | Gap-berekening is een pure functie → eenvoudig en deterministisch testbaar |
| Performance | Sneller — geen content map, geen hypothese-scoring voor de primaire path |
| Dependencies | Geen — gebruikt alleen bestaande OCR-output |

### Relatie tot DocLayout-YOLO

DocLayout-YOLO blijft waardevol als **bevestiging**:
- Als YOLO een figuur vindt die overlapt met een OCR-gap → hoge confidence
- Als YOLO een figuur vindt buiten de gaps → extra kandidaat (bijv. figuur naast tekst)
- Als YOLO niets vindt maar er is een gap met visuele content → gap wint

### Relatie tot Vision saliency/subject

Vision wordt gedegradeerd van primair signaal naar optionele verfijning:
- Subject bounds kunnen helpen de gap-bounds te verfijnen (preciezere onder/bovengrens)
- Saliency kan helpen bij de validatie-stap (bevat de gap opvallende content?)
- Maar als Vision niets vindt of onzin geeft, is dat geen probleem meer — de gaps staan al vast

### Risico's

| Risico | Mitigatie |
|--------|----------|
| OCR mist tekst → gap te groot | OCR is bewezen betrouwbaar (18-20 blokken consistent); te grote gaps worden gevalideerd met pixel-check |
| OCR vindt "tekst" in foto → gap te klein | Komt voor bij tekst-overlay op foto's; fallback naar YOLO/Vision voor die regio |
| Niet alle pagina's zijn verticaal gestructureerd | Horizontale gap-analyse als uitbreiding; YOLO/Vision als fallback |
| Minimale gap-hoogte is een parameter | Eén parameter (5%) vs. huidige ~15 parameters; eenvoudig te testen |

---

## Verwacht resultaat voor de nieuwspagina

Met OCR-gap detectie op de huidige debug-data:

```
Gap 1: y=0.895 tot y=1.000 (boven eerste tekst)
        → hoogte 0.105 (10.5%) > 5% drempel
        → pixel-check: visuele content aanwezig
        → RESULTAAT: hero-foto gedetecteerd ✓

Gap 2: y=0.532 tot y=0.644 (tussen bijschrift en "Nieuwsvideo's")
        → hoogte 0.112 (11.2%) > 5% drempel
        → pixel-check: visuele content aanwezig
        → RESULTAAT: walvisfoto gedetecteerd ✓
```

Geen saliency nodig. Geen content map. Geen hypothese-scoring. Deterministisch. Elke capture hetzelfde resultaat.

---

## Samenvatting

| Aspect | Voorstel v2 (5 opties) | Codex-aligned (validatie + fallback) | Dit voorstel (OCR-gap first) |
|--------|----------------------|-------------------------------------|------------------------------|
| Lost root causes op | 1-2 van 3 per optie | 0 van 3 (filtert alleen slechte output) | Alle 3 (omzeilt saliency als primair signaal) |
| Complexiteit | Hoog (nieuwe subsystemen) | Gemiddeld (extra passes) | Laag (pure functie op bestaande data) |
| Testbaarheid | Gemiddeld (nieuwe parameters) | Gemiddeld (validatie-thresholds) | Hoog (deterministische gap-berekening) |
| Risico op parameter-tuning | Hoog | Gemiddeld | Laag (1 parameter: minimum gap-hoogte) |
| Implementatie-inspanning | Gemiddeld-hoog | Gemiddeld | Laag (~150 regels) |
| Verwacht effect op output | Onbekend | Minimaal tot negatief | Direct positief en deterministisch |
