# Analyse: Codex-advies vs. Architectuurvoorstel v2

**Datum:** 2026-03-12
**Context:** Codex heeft drie documenten opgeleverd. Dit document analyseert hoe het Codex-advies zich verhoudt tot de drie geïdentificeerde root causes en de vijf voorgestelde oplossingsrichtingen (A-E).

---

## Samenvatting Codex-advies

Codex levert drie documenten met twee sporen:

### Spoor 1: Kwaliteitsarchitectuur (direct relevant)

Codex stelt een **5-pass architectuur** voor:

| Pass | Functie | Status in huidige code |
|------|---------|----------------------|
| A: DocLayout-YOLO | Primaire detectie | Geïmplementeerd |
| B: Vision fallback | Saliency + instance mask bij lage confidence | Geïmplementeerd (maar instabiel) |
| C: Boundary refinement | Text-trim, crop, variance | Geïmplementeerd (maar parametrisch fragiel) |
| **D: Kwaliteitsvalidatie** | Text-bleed check, aspect plausibility, content variance, subject consistency | **Ontbreekt** |
| **E: Fusion en ranking** | Beste kandidaatselectie op kwaliteitsscore | **Ontbreekt** |

Codex benoemt expliciet **activatie-regels voor extra detectierondes**:
- Geen figuren gedetecteerd terwijl OCR visuele regio's aangeeft
- Lage modelconfidence
- Verdachte bounds (te smal/te hoog, onwaarschijnlijke aspect ratio, grote overlap met tekst)
- Dark/low-contrast achtergrond
- Inconsistentie tussen DocLayout en Vision output

### Spoor 2: Compliance & Licentie (parallel spoor)

Codex stelt een compliance-framework voor met licentie-inventarisatie, risicoklassen en 7 verplichte artefacten. Dit is een apart werkspoor dat de figuurdetectie-architectuur niet direct beïnvloedt maar wel relevant is voor de DocLayout-YOLO afhankelijkheid (ONNX Runtime + modelgewichten).

---

## Codex-diagnose vs. onze root causes

| Root cause | Codex benoemt dit? | Codex-oplossing |
|------------|-------------------|-----------------|
| RC1: Saliency non-determinisme | Ja — "Stability Score (zelfde input, consistente output over meerdere runs)" als verplichte metric | Geen concrete oplossing, wel als meetbaar criterium |
| RC2: Donkere achtergronden | Ja — "dark-background specifieke detectie" als P0, "Dark/low-contrast achtergrond" als trigger voor extra ronde | Extra fallback-pass met content-component analyse op OCR-gemaskerde beelden |
| RC3: Eén groot subject | Indirect — "verdachte bounds" en "grote overlap met tekst" als triggers | Kwaliteitsvalidatie (Pass D) die verdachte geometrie filtert |

**Conclusie:** Codex identificeert dezelfde probleemgebieden maar verpakt ze anders. Waar wij de root causes als architectureel classificeren (de pipeline structuur moet veranderen), ziet Codex het als **ontbrekende quality gates** (er moeten extra passes komen die slechte output filteren/corrigeren).

---

## Codex-advies per voorgestelde optie

### Optie A (Edge-detectie): Niet benoemd door Codex
Codex noemt edge-detectie niet als aanbeveling. Wel benoemt Codex "edge confidence maps om zachte overgangen beter te behouden" als brainstorm-item, maar dan als post-processing — niet als primaire detectiemethode.

**Beoordeling:** Codex ziet edge-detectie als secondary signal, niet als primair. Dit sluit aan bij onze eigen risico-inschatting (nieuwe parameterset, kan parameter-tuning verschuiven).

### Optie B (Multi-resolution saliency): Niet expliciet benoemd
Codex benoemt multi-pass inferentie (origineel + contrast/gamma variant) voor DocLayout-YOLO, maar niet specifiek voor Vision saliency. Codex stelt wel "stability score" als metric voor.

**Beoordeling:** Codex ziet stabiliteit als meetbaar resultaat, niet als iets dat je oplost door saliency meerdere keren te draaien. Dit suggereert dat Codex het probleem liever architectureel adresseert (minder afhankelijk van saliency) dan de saliency zelf te stabiliseren.

### Optie C (Contour-segmentatie): Indirect benoemd
Codex noemt "segmentatiemodellen" als geparkeerd brainstorm-item: "Pas overwegen als hybride pipeline onvoldoende kwaliteit levert." Dit is nu het geval.

**Beoordeling:** Codex zou Optie C activeren nu de hybride pipeline onvoldoende kwaliteit levert. Maar Codex waarschuwt ook voor complexiteit: "expert-router" en "learned post-processor" worden als over-engineering geparkeerd.

### Optie D (Horizontal band analysis): Sterk aligned met Codex
Codex benoemt expliciet: "Voeg een extra fallback-pass toe... Gebruik **content-component analyse op OCR-gemaskerde beelden**." Dit is in essentie hetzelfde concept als horizontale band-analyse: analyseer de afbeelding met tekst uitgesloten en classificeer wat overblijft.

Codex voegt toe: "dark-background specifieke detectie (niet alleen light-background heuristiek)." Dit is precies wat band-analyse oplost — kleurvariantie per strook werkt ongeacht achtergrondkleur.

**Beoordeling:** Optie D is de meest Codex-aligned aanpak. Het combineert drie Codex-aanbevelingen: (1) content-component analyse op OCR-gemaskerd beeld, (2) dark-background detectie, (3) deterministische output.

### Optie E (Combinatie): Deels aligned
Codex's gefaseerde aanpak (Fase 0→3) komt overeen met een incrementele combinatie. Maar Codex waarschuwt tegen complexiteit en benadrukt "evidence-based beslissingen" — alleen toevoegen wat meetbaar verbetert.

**Beoordeling:** Optie E is aligned met Codex's faseringsprincipe maar riskeert de complexiteit waar Codex voor waarschuwt.

---

## Wat Codex toevoegt dat wij missen

### 1. Kwaliteitsvalidatie als aparte pass (Pass D)

Onze pipeline mist een expliciete validatie-stap die slechte output herkent en terugkoppelt. Codex stelt voor:
- **Text-bleed check**: bevat de figuur-crop tekst die er niet in hoort?
- **Aspect plausibility**: is de aspect ratio realistisch voor een foto/figuur?
- **Content variance**: bevat de crop daadwerkelijk visuele content (niet alleen achtergrond)?
- **Subject consistency**: klopt het subject met de crop-grenzen?

Dit zou direct onze problemen adresseren:
- Smal stripje (121×1177) faalt op aspect plausibility
- Figuur met "Nieuwsvideo's" faalt op text-bleed check
- Resultaat met 3 strepen faalt op content variance

**Aanbeveling:** Voeg een validatie-pass toe ongeacht welke optie (A-E) wordt gekozen. Dit is complementair.

### 2. Activatie-regels voor extra rondes

Codex stelt niet een statische pipeline voor maar een **adaptieve**: als het resultaat verdacht is, draai een extra ronde. Dit is fundamenteel anders dan onze voorstellen die allemaal een vaste pipeline wijzigen.

Concreet: in plaats van de hele pipeline te verbouwen, kun je na PASS4 checken:
- Is er een figuur met aspect ratio < 0.15? → verdacht, heranalyse met alternatieve methode
- Is er een figuur met >5% text-overlap? → trim of heranalyse
- Zijn er 0 figuren terwijl er grote non-text regio's zijn? → fallback-detectie

### 3. Verplichte kwaliteitsmetrics per run

Codex eist rapportage van: figure recall, text-bleed rate, crop completeness, false positive rate, stability score. Wij meten dit niet systematisch. Dit zou helpen om objectief te beoordelen of een wijziging een verbetering is.

### 4. Compliance-spoor als parallel werkstroom

De DocLayout-YOLO afhankelijkheid (ONNX Runtime, modelgewichten) heeft licentie-implicaties die nog niet zijn geïnventariseerd. Codex stelt Klasse D (niet-standaard modellicentie) risicoanalyse voor. Dit is een apart werkspoor maar moet niet vergeten worden.

---

## Aanbevolen aanpak (synthese Codex + eigen analyse)

Op basis van de Codex-analyse stel ik de volgende prioritering voor:

### Stap 1: Kwaliteitsvalidatie toevoegen (Pass D) — Codex alignment, laag risico

Voeg na PASS4 een validatie-pass toe die verdachte output herkent:
- Aspect ratio check (verwerp figuren smaller dan 15% van hun hoogte)
- Text-bleed check (verwerp figuren met >5% tekst-overlap)
- Content variance check (verwerp figuren met te lage kleurvariantie)
- Minimum size check (verwerp figuren kleiner dan 3% van het beeld)

Dit vangt de ergste fouten op zonder de detectie-pipeline zelf te wijzigen.

### Stap 2: Horizontal band analysis als fallback (Optie D) — Codex aligned

Wanneer Pass D verdachte output constateert (bijv. geen valide figuren, of alleen smalle strepen), trigger een alternatieve detectie op basis van horizontale band-analyse met OCR-masking. Dit is Codex's "extra fallback-pass met content-component analyse op OCR-gemaskerd beeld."

### Stap 3: Kwaliteitsmetrics implementeren — Codex vereiste

Implementeer de 5 verplichte metrics zodat elke wijziging objectief beoordeeld kan worden.

### Stap 4: Compliance-inventarisatie — apart spoor

Start parallel de licentie-inventarisatie conform Codex Fase 1-2.

---

## Open vragen voor de gebruiker

1. Is de gefaseerde aanpak (validatie → fallback → metrics → compliance) akkoord?
2. Moet het compliance-spoor parallel lopen of wachten tot UC-5 is afgerond?
3. Wil je dat Codex de validatie-pass (Stap 1) beoordeelt voordat we implementeren?
