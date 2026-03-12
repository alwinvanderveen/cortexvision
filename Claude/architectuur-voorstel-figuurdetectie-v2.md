# Architectuurvoorstel: Figuurdetectie Pipeline v2

**Datum:** 2026-03-12
**Auteur:** Claude Opus (iteratie-analyse na Gate 6 stop)
**Status:** VOORSTEL — wacht op beoordeling door peer (Codex) en akkoord gebruiker
**Context:** UC-5 figuurdetectie afronden

---

## Probleemstelling

De huidige hybride pipeline (DocLayout-YOLO + Vision saliency/subject fallback) werkt goed op deterministische test-PNG's maar produceert inconsistente resultaten op live screen captures. Na 3 iteraties van parameter-tuning (Gate 6 limiet bereikt) is vastgesteld dat het probleem **architectureel** is, niet parametrisch.

### Concreet waargenomen gedrag

Test-afbeelding: nieuwspagina (nu.nl) met twee foto's (hero-foto bovenaan, walvisfoto onderaan) gescheiden door tekstkoppen.

| Run | Saliency regio | Conf | Subject bounds | Resultaat |
|-----|---------------|------|----------------|-----------|
| Test PNG (625×1259) | 2 aparte regio's | — | Geen subjects | 2 figuren, correct |
| App capture #1 (1200×2522) | (0.000, 0.400, 0.610, 0.283) | 0.80 | 1 groot: (0.000, 0.493, 0.509, 0.507) | 1 smal stripje (121×1177) |
| App capture #2 (1210×2508) | (0.000, 0.356, 0.626, 0.327) | 0.80 | 1 groot: (0.000, 0.493, 0.509, 0.507) | 2 figuren, walvis met tekst erin |
| App capture #3 (1206×2502) | (0.000, 0.407, 0.617, 0.276) | 0.80 | 1 groot: (0.000, 0.493, 0.507, 0.507) | 2 figuren, walvis met "Nieuwsvideo's" |
| App capture #4 (1198×2502) | (0.406, 0.415, 0.181, 0.227) | 0.50 | 1 groot: (0.000, 0.491, 0.509, 0.509) | 3 smalle strepen |

### Drie onafhankelijke root causes

**1. Vision saliency is non-deterministisch**
Elke capture van dezelfde content (licht andere pixeldimensies door window resizing) geeft fundamenteel andere saliency-regio's. Van een groot betrouwbaar gebied (0.617×0.276, conf 0.80) tot een klein onbruikbaar stukje (0.181×0.227, conf 0.50). De pipeline kan niet bouwen op stabiele saliency input.

**2. Donkere achtergronden breken de content map**
De content map classificeert pixels als "content" (#), "text" (T) of "background" (.). Op een donkere webpagina zijn foto's EN tekst beide non-background. De content map kan ze niet onderscheiden, waardoor `contentFit` en `subjectAnchored` hypotheses altijd oversized regio's teruggeven die vervolgens door text-trimming tot smalle strepen worden gereduceerd.

**3. Eén groot subject absorbeert meerdere figuren**
Vision's instance segmentation vindt één subject dat de hele onderkant van de pagina beslaat (beide foto's + alle tekst). De `subjectAnchored` hypothese convergeert daardoor altijd naar dezelfde bounds, ongeacht welke kandidaat wordt verfijnd.

### Waarom parameter-tuning niet werkt

| Iteratie | Aanpassing | Effect case A | Effect case B |
|----------|-----------|---------------|---------------|
| 1 | subjectAnchored penalty >1.5x | Geen effect (1.46x < threshold) | Goed (5x penalized) |
| 2 | Threshold verlaagd naar 1.2x + contentFit clipping | Walvis beter, hero afgesneden | Goed |
| 3 | Agressievere trim (0.5%) + padding limit 3x | — | Compleet broken (3 strepen) |

Elke threshold-aanpassing die één case verbetert, verslechtert een andere. Het systeem heeft te veel interacterende parameters (padding, trim drempel, expansie ratio, edge proximity, min cut fraction) die samen een fragiel evenwicht vormen.

---

## Voorgestelde oplossingsrichtingen

### Optie A: Edge-detection pass (Canny/Sobel)

**Concept:** Voeg een edge-detectie pass toe die foto-grenzen vindt op basis van scherpe kleur-/helderheidovergangen. Foto's hebben typisch harde randen (frame, achtergrondovergang) die tekst niet heeft. Gebruik dit als aanvullend signaal naast saliency om figuur-bounds te bepalen.

**Implementatie:**
- `CGImage` → grijswaarden → Sobel/Canny edge filter (via Accelerate/vImage of CIFilter)
- Horizontale en verticale edge-profielen berekenen
- Foto-grenzen identificeren als pieken in het edge-profiel
- Integreren als extra hypothese in PASS3 (`edgeBounded`)

**Voordelen:**
- Deterministisch: zelfde input → zelfde output (geen neural network variatie)
- Werkt onafhankelijk van achtergrondkleur (donker/licht maakt niet uit, de OVERGANG telt)
- Complementair aan saliency: saliency vindt WAT interessant is, edges vinden WAAR het ophoudt
- Lage computational cost (Accelerate framework, <50ms)
- Geen externe dependencies

**Nadelen:**
- Foto's met zachte randen (gradient, blur, vignette) hebben zwakke edges → onbetrouwbaar
- Webpagina's met veel visuele scheidslijnen (borders, dividers, schaduwen) produceren valse edges
- Complexe implementatie: edge-profielen naar bounds converteren vereist heuristieken (drempel voor "sterke" edge, minimum lengte, oriëntatie filtering)
- Voegt een nieuwe parameterset toe (edge threshold, min edge length, profiel smoothing) die ook getuned moet worden
- Lost root cause #1 (saliency variatie) niet op — het is een extra signaal dat gewogen moet worden

**Gevolgen voor bestaande code:**
- Nieuwe klasse `EdgeBoundaryDetector`
- Extra hypothese-type in `BoundaryHypothesis`
- Scoring moet worden uitgebreid om edge-evidence mee te wegen
- Bestaande tests ongewijzigd, nieuwe tests voor edge-detectie nodig
- Accelerate/vImage dependency toevoegen (al beschikbaar in macOS SDK)

**Risico-inschatting:** Gemiddeld. Deterministisch maar introduceert nieuwe heuristieken. Kan hetzelfde parameter-tuning probleem verschuiven naar edge thresholds.

---

### Optie B: Multi-resolution saliency consensus

**Concept:** Draai Vision's saliency-analyse op meerdere resoluties van dezelfde afbeelding (1x, 0.75x, 0.5x, eventueel 0.25x) en neem de consensus (intersectie of gewogen unie) van de resultaten. Dit compenseert de non-deterministische saliency door te middelen over meerdere runs.

**Implementatie:**
- Schaal het bronbeeld naar 3-4 resoluties
- Draai `VNGenerateSaliencyImageBasedRequest` op elke resolutie
- Converteer resultaten terug naar originele coördinaten
- Neem intersectie (conservatief) of gewogen unie (agressief) als stabiele saliency

**Voordelen:**
- Pakt root cause #1 (non-determinisme) direct aan
- Geen nieuwe heuristieken of parameters — gebruikt bestaande Vision API
- Als alle resoluties hetzelfde gebied vinden, is het vertrouwen hoog
- Kan bestaande pipeline-structuur behouden (PASS1 levert stabielere input)
- Eenvoudig te implementeren (~50 regels code)

**Nadelen:**
- 3-4× langere saliency-analyse (momenteel ~100ms per run, wordt ~300-400ms)
- Vision's saliency kan op ALLE resoluties hetzelfde verkeerde gebied vinden — consensus van verkeerde data is nog steeds verkeerd
- Lost root cause #2 (donkere achtergrond content map) en #3 (groot subject) NIET op
- Saliency op lagere resoluties verliest detail — kleine figuren kunnen verdwijnen
- Consensus-logica (intersectie vs. unie, wegingen) is weer een set parameters

**Gevolgen voor bestaande code:**
- Wijziging in `pass1_gatherEvidence` — saliency-analyse loopt meerdere keren
- Nieuwe helper `multiResolutionSaliency()`
- Performance impact: +200-300ms per analyse
- Bestaande tests ongewijzigd
- Test voor consensus-stabiliteit toevoegen

**Risico-inschatting:** Laag-gemiddeld. Eenvoudige implementatie maar lost slechts 1 van 3 root causes op. Performance impact acceptabel (Gate 8: kwaliteit boven snelheid).

---

### Optie C: Contour-gebaseerde segmentatie

**Concept:** Gebruik Vision's `VNDetectContoursRequest` om contouren in het beeld te detecteren. Foto's produceren complexe, gesloten contouren (veel detail), terwijl tekst en achtergrond eenvoudige of geen contouren hebben. Groepeer contour-dichte regio's als kandidaat-figuren.

**Implementatie:**
- `VNDetectContoursRequest` op het bronbeeld
- Contour-dichtheidskaart berekenen (hoeveel contourpunten per grid-cel)
- Regio's met hoge contourdichtheid markeren als figuur-kandidaten
- Integreren als alternatief voor saliency in PASS1, of als validatie in PASS3

**Voordelen:**
- Deterministisch (contourdetectie is stabiel, geen neural network variatie)
- Onderscheidt foto's (veel contouren) van tekst (regelmatige, eenvoudige contouren) en achtergrond (geen contouren) — lost root cause #2 deels op
- Werkt op donkere achtergronden (contouren zijn onafhankelijk van absolute helderheid)
- MacOS 11+ API, geen externe dependencies
- Kan de content map vervangen of aanvullen met betrouwbaarder signaal

**Nadelen:**
- Tekst produceert OOK contouren (lettervormen) — onderscheid foto vs. tekst vereist contour-complexiteitsanalyse (kromming, lengte, dichtheid)
- Eenvoudige foto's (bijv. egale achtergrond met weinig detail) produceren weinig contouren → worden gemist
- `VNDetectContoursRequest` kan traag zijn op grote afbeeldingen (>1s)
- Complexe post-processing: van contourpunten naar bounding boxes is niet triviaal
- Niet bewezen in onze codebase — nieuw terrein met onbekende edge cases
- Lost root cause #1 (saliency variatie) niet direct op (tenzij het saliency volledig vervangt)

**Gevolgen voor bestaande code:**
- Nieuwe klasse `ContourFigureDetector`
- Significante wijziging in PASS1 of nieuw PASS0
- Content map logica moet worden herzien (contour-density i.p.v. pixel-brightness)
- Alle 18 figuurdetectie tests opnieuw valideren
- Performance profiling nodig

**Risico-inschatting:** Hoog. Veel onbekenden, complexe implementatie, en het is niet bewezen dat contour-dichtheid foto's betrouwbaar van tekst onderscheidt in webpagina-context.

---

### Optie D: Horizontal band analysis (aanbevolen)

**Concept:** In plaats van saliency als startpunt te nemen, analyseer de pagina als horizontale banden. Webpagina's zijn inherent verticaal gestructureerd: foto's, tekst en witruimte wisselen af als horizontale banden. Door de afbeelding in horizontale stroken te verdelen en per strook het type te classificeren (foto/tekst/achtergrond), worden figuur-regio's direct geïdentificeerd zonder afhankelijk te zijn van saliency.

**Implementatie:**
- Verdeel de afbeelding in horizontale stroken (bijv. 2% hoogte per strook)
- Per strook: bereken kleurvariantie (foto's: hoog), tekstdichtheid (OCR bounds overlap), en helderheidsuniformiteit (achtergrond: uniform)
- Classificeer stroken: PHOTO (hoge variantie, geen tekst), TEXT (lage variantie, tekst overlap), BACKGROUND (uniform)
- Groepeer aaneengesloten PHOTO-stroken tot figuur-kandidaten
- Gebruik OCR-bounds als harde grenzen (tekst = niet-figuur)

**Voordelen:**
- **Volledig deterministisch** — geen Vision saliency, geen neural network variatie
- **Lost alle drie root causes op:**
  - RC1: geen saliency → geen variatie
  - RC2: kleurvariantie per strook onderscheidt foto van tekst ongeacht achtergrondkleur
  - RC3: geen subject-analyse nodig
- **Conceptueel eenvoudig** — pagina-layout is inherent horizontaal gestructureerd
- **Bouwt voort op bestaande OCR** — tekst-bounds zijn al beschikbaar en betrouwbaar
- **Snel** — pixel-statistieken per strook via Accelerate framework (<50ms)
- **Geen externe dependencies**
- **Goed testbaar** — deterministisch, meetbare output per strook

**Nadelen:**
- Werkt alleen voor verticaal gestructureerde pagina's — side-by-side foto's worden als één brede band gezien (horizontale splitsing moet apart)
- Foto's die dezelfde kleurvariantie hebben als de achtergrond (bijv. egaal gekleurde infographics) worden gemist
- Vereist calibratie van variantie-drempels per strook (wat is "hoog genoeg" voor een foto?)
- Vervangt een groot deel van de bestaande PASS1-3 logica — significant refactoring
- Nieuw terrein — onbekend hoe goed dit werkt op diverse pagina-types (documenten, presentaties, apps)

**Gevolgen voor bestaande code:**
- Nieuwe klasse `HorizontalBandAnalyzer`
- PASS1 logica deels vervangen (band-analyse als primaire bron, saliency als secundair signaal)
- Content map kan worden vereenvoudigd (strook-classificatie vervangt pixel-level analyse)
- OCR-integratie wordt strakker (tekst-bounds als harde grenzen)
- Bestaande figuurdetectie tests moeten opnieuw gevalideerd worden
- Nieuwe tests voor band-classificatie

**Risico-inschatting:** Gemiddeld. Conceptueel helder en deterministisch, maar onbewezen aanpak die significante refactoring vereist. Risico zit in de generalisatie naar diverse pagina-types.

---

### Optie E: Combinatie-aanpak (pragmatisch)

**Concept:** Combineer de sterke punten van meerdere opties zonder de volledige implementatie van elk:

1. **Multi-resolution saliency (Optie B)** voor stabielere PASS1 input
2. **Horizontal band analysis (Optie D)** als validatie/correctie in PASS3
3. **Bestaande pipeline behouden** als backbone

Dit is een evolutionaire aanpak: verbeter de input (B) en de validatie (D) terwijl de bestaande hypothese-scoring en extractie intact blijven.

**Voordelen:**
- Incrementeel implementeerbaar (B eerst, D daarna)
- Beperkt risico per stap
- Bestaande tests blijven werken
- Adresseert alle drie root causes gefaseerd

**Nadelen:**
- Meer code-complexiteit (extra lagen)
- Twee nieuwe subsystemen te onderhouden
- Kan alsnog niet voldoende zijn als de individuele verbeteringen te zwak zijn
- Performance impact van beide stappen opgeteld

**Risico-inschatting:** Laag-gemiddeld. Evolutionair maar kan tot een complex systeem leiden.

---

## Vergelijkingsmatrix

| Criterium | A: Edge | B: Multi-res | C: Contour | D: Band | E: Combinatie |
|-----------|---------|-------------|-----------|---------|---------------|
| Lost RC1 (saliency variatie) | Nee | **Ja** | Deels | **Ja** | **Ja** |
| Lost RC2 (donkere achtergrond) | **Ja** | Nee | Deels | **Ja** | Deels |
| Lost RC3 (groot subject) | Nee | Nee | Nee | **Ja** | Deels |
| Deterministisch | **Ja** | Nee | **Ja** | **Ja** | Deels |
| Implementatie-inspanning | Gemiddeld | Laag | Hoog | Gemiddeld-hoog | Gemiddeld |
| Risico op nieuwe parameter-tuning | Hoog | Laag | Gemiddeld | Gemiddeld | Gemiddeld |
| Impact op bestaande code | Laag | Laag | Hoog | Gemiddeld-hoog | Gemiddeld |
| Performance impact | Laag | Gemiddeld | Gemiddeld-hoog | Laag | Gemiddeld |
| Bewezen in ons domein | Nee | Nee | Nee | Nee | Nee |

---

## Huidige staat van de code

De volgende wijzigingen zijn in de huidige working copy (nog niet gecommit):

1. **`FigureDetector.swift`**:
   - `subjectAnchored` penalty bij expansion ratio >1.2x (actief, getest, 190/190 pass)
   - `contentFit` clipping bij <50% overlap met kandidaat (actief, getest, 190/190 pass)
   - Trim en padding wijzigingen zijn **teruggedraaid** (veroorzaakten regressie)

2. **`AppViewModel.swift`**: Tijdelijke debug logging naar `/tmp/cortexvision-analysis-debug.log`

3. **`DocLayoutDetectorTests.swift`**: YOLO-limitatie tests (expect 0 figures) + newsPageMultiplePhotos test

4. **`CaptureVerificationTests.swift`**: Alle figuurdetectie tests omgezet naar in-memory rendering

5. **`Makefile`**: Debug default ON, rapport generatie per run

### Testresultaten huidige code
- 190/190 tests pass
- Coverage: 86%
- newsPageMultiplePhotos test (PNG): 2 figuren correct gedetecteerd
- Live app capture: inconsistent (2 figuren met tekst-artefacten tot 3 smalle strepen)

---

## Vraag aan peer reviewer

1. Welke optie (A-E) heeft je voorkeur en waarom?
2. Zijn er oplossingsrichtingen die hier niet zijn overwogen?
3. Is de diagnose van de drie root causes correct en volledig?
4. Moeten we de huidige wijzigingen (penalty + clipping) committen als tussenstap, of wachten tot de architectuurkeuze is gemaakt?
