# Analyse En Implementatieplan — BUG-1 Overlay Text Trimming

## Doel
Dit document geeft een technisch oordeel op:
- [analysis-bug1-overlay-text-trimming.md](/Users/alwinvanderveen/.claude/projects/-Users-alwinvanderveen-Projects-cortexvision/memory/analysis-bug1-overlay-text-trimming.md)
- de huidige overlay-trimming code in [FigureDetector.swift](/Users/alwinvanderveen/Projects/cortexvision/Sources/CortexVision/Analysis/FigureDetector.swift)

Het doel is niet een lokale threshold-fix, maar een structurele oplossing die maximale figuurdetectiekwaliteit levert. Performance, backward compatibility en implementatiegemak zijn ondergeschikt.

## Samenvatting
De Claude-analyse is grotendeels correct over het directe foutmechanisme, maar nog niet volledig over de structurele oorzaak. Het probleem is niet alleen dat de content map te grof is. Het echte probleem is dat de overlay-beslissing op dit moment semantisch fout gemodelleerd is:

1. Tekst op een foto wordt alleen als overlay gezien als er content boven EN onder de tekst zit.
2. Dat criterium faalt precies voor headline-tekst die op de rand van een foto staat.
3. De gebruikte content map is te grof en de analysegio te vervuild om dit lokaal betrouwbaar te corrigeren.
4. Daardoor wordt tekst-trimming uitgevoerd op basis van een fout overlay-oordeel, en dan is de rest van de pipeline alleen nog schadebeperking.

Mijn conclusie: dit moet niet met extra drempel-tuning worden opgelost, maar met een lokale, hoge-resolutie, mask-first overlay-analyse per tekstblok.

## Beoordeling Van De Bestaande Root Cause Analyse

### Wat klopt
Claude identificeert terecht:
1. De bovenfoto wordt verkeerd getrimd in de 3D trim-stap.
2. `filterOverlayTextViaContentMap()` werkt wel voor de onderfoto, maar niet voor de headline op de bovenfoto.
3. De huidige `minContentCells` drempel veroorzaakt een dilemma tussen twee testcases.
4. Een lokale oplossing in `autoCropWhitespace` pakt het kernprobleem niet aan.

Deze punten zijn technisch coherent met de huidige code, vooral rond:
- [FigureDetector.swift](/Users/alwinvanderveen/Projects/cortexvision/Sources/CortexVision/Analysis/FigureDetector.swift:529)
- [FigureDetector.swift](/Users/alwinvanderveen/Projects/cortexvision/Sources/CortexVision/Analysis/FigureDetector.swift:795)

### Wat ontbreekt in de analyse
De Claude-analyse benoemt niet expliciet twee extra structurele oorzaken:

1. **De overlay-definitie is semantisch te strikt**
   Tekst op de rand van een foto hoeft niet "sandwiched" te zijn om overlay te zijn. Bij hero-headlines staat de tekst vaak op de onderste strook van de foto, met content erboven en weinig of geen content eronder. De huidige logica behandelt dat als niet-overlay, terwijl het in feite wel overlay is.

2. **De feature-extractie is lokaal onvoldoende zuiver**
   De content map wordt niet op een echt lokaal tekstpatch-niveau beoordeeld, maar op een grotere kandidaatregio waarin ook andere tekst, whitespace en soms een tweede afbeelding zitten. Daardoor wordt de overlay-klassificatie beïnvloed door pagina-layout in plaats van alleen door de relatie tussen tekst en de onderliggende beeldcontent.

## Werkelijke Root Cause
De huidige pipeline gebruikt een coarse content map als proxy voor een semantische vraag:

`Is dit tekst op pagina-achtergrond, of tekst die op figuurcontent ligt?`

Die vraag wordt nu beantwoord met een grid-signaal dat daar niet sterk genoeg voor is.

Het echte probleem bestaat uit drie lagen:

1. **Verkeerde beslisregel**
   Overlay wordt gemodelleerd als "content boven en onder tekst". Dat is niet gelijk aan "tekst ligt op beeldcontent".

2. **Te grove ruimtelijke representatie**
   Een 50x50 grid is te grof voor randgevallen met gradients, zachte randen en smalle overgangszones.

3. **Te vroege destructieve actie**
   Zodra een tekstblok niet als overlay wordt gezien, mag `trimTextFromRegion()` het figuur afsnijden. Dat is een harde beslissing op basis van zwakke evidentie.

## Waarom Drempel-Tuning Niet De Juiste Richting Is
De analyse laat zelf al zien dat `minContentCells` een instabiele trade-off oplevert. Dat is een signaal dat de feature ongeschikt is voor de taak. Als de enige manier om beide beelden goed te krijgen het zoeken naar een "net goed genoeg" drempel is, dan is de representatie verkeerd gekozen.

Voor een quality-first product is dat niet acceptabel.

## Voorgestelde Oplossing

## Hoofdrichting
Vervang de huidige coarse overlay-detectie door een **lokale mask-first overlay analyzer** per OCR-tekstblok dat een figuurkandidaat overlapt.

De trim-beslissing wordt dan niet meer genomen op basis van een grid-heuristiek, maar op basis van een lokale analyse van de echte beeldcontinuiteit achter en rondom het tekstblok.

## Kernprincipe
Voor ieder tekstblok dat het figuur snijdt:

1. Maak een lokale patch rond het tekstblok met ruime context.
2. Segmenteer of classificeer welke pixels tot de figuur horen.
3. Meet of de figuurmasker/beeldstructuur doorloopt achter de tekst en richting de aangrenzende rand.
4. Als die continuiteit aanwezig is, markeer het tekstblok als overlay en sluit het uit van trimming.
5. Trim alleen op tekstblokken die met hoge zekerheid geen overlay zijn.

## Aanbevolen Implementatie

### Fase 1: Overlay Analyzer abstraheren
Voeg een aparte component toe:

`OverlayTextAnalyzer`

Verantwoordelijkheden:
1. Analyse van tekstblokken die een figuurkandidaat overlappen.
2. Uitkomst per tekstblok:
   - `overlay`
   - `edgeOverlay`
   - `pageText`
   - `uncertain`

Belangrijk:
- `edgeOverlay` moet expliciet bestaan.
- `uncertain` moet bestaan zodat de pipeline conservatief kan handelen.

### Fase 2: Lokale hoge-resolutie patch-analyse
Voor elk relevant tekstblok:
1. Snij een patch uit rond het tekstblok, bijvoorbeeld 3x de teksthoogte erboven/eronder en 1.5x links/rechts.
2. Gebruik de figuurkandidaat als ruimtelijke prior.
3. Analyseer niet alleen boven/onder, maar ook:
   - laterale continuiteit,
   - kleur/texture-verschil t.o.v. pagina-achtergrond,
   - connected component continuity,
   - continuity richting de rand van het figuur.

### Fase 3: Moderne modelgebaseerde variant
Als kwaliteit de hoogste prioriteit heeft, is dit de voorkeursvariant:

1. Gebruik een moderne promptable segmenter op de patch.
2. Gebruik de bestaande figuurkandidaat als prompt of prior.
3. Laat de segmenter bepalen of de regio achter de tekst onderdeel is van hetzelfde visuele object/beeldvlak.

Geschikte moderne richting:
1. `SAM 2` of vergelijkbare high-quality segmentatie voor lokale patches.
2. Optioneel gecombineerd met een open-vocabulary detector/grounder voor "photo/banner/video thumbnail" confirmatie.

Dit is zwaarder, maar kwalitatief duidelijk sterker dan een 50x50 content map.

### Fase 4: Conservatieve trim-regel
Pas trimming aan:

1. `overlay` of `edgeOverlay`:
   - nooit gebruiken voor trim.
2. `uncertain`:
   - standaard niet gebruiken voor destructieve trim.
   - alleen trimmen als extra signalen sterk bevestigen dat het pagina-tekst is.
3. `pageText`:
   - wel gebruiken voor trim.

Dat is bewust conservatief: liever tijdelijk iets te veel figuur behouden dan relevante figuurinhoud wegsnijden.

## Waarom Dit Voorstel Beter Is

### Beter dan de huidige content-map oplossing
1. Het modelleert de juiste vraag:
   - niet "zitten er grid-cellen boven en onder?"
   - maar "loopt figuurcontent lokaal door achter/naast deze tekst?"
2. Het werkt ook bij edge-overlays.
3. Het is minder gevoelig voor coarse quantization.
4. Het is minder afhankelijk van vervuilde full-candidate context.

### Beter dan alleen hogere content-map resolutie
1. Hogere resolutie maakt een zwakke feature alleen fijner, niet semantisch juister.
2. Het lost de verkeerde overlay-definitie niet op.
3. Het blijft gevoelig voor ROI-vervuiling.

### Beter dan pixel-sampling heuristiek alleen
1. Losse samplepunten boven/onder zijn te fragiel bij gradients en fototransities.
2. Patch-analyse met continuiteitslogica gebruikt ruimtelijk rijkere informatie.
3. Een mask-first aanpak kan objectcontinuiteit zien waar een paar samplepunten dat niet kunnen.

### Beter dan OCR-gap-first als volledige oplossing
1. OCR-gap is goed voor kandidaatgeneratie, maar niet voor overlay-op-foto gevallen.
2. OCR-gap faalt juist als tekst op de foto staat, omdat het "gat" kleiner of onzichtbaar wordt.
3. Het huidige bugtype is precies zo'n geval.

### Beter dan een pure validatie-pass
1. Een validatie-pass kan slechte output afkeuren.
2. Deze aanpak voorkomt dat de slechte output uberhaupt ontstaat.
3. Validatie blijft nuttig, maar is geen vervanging voor een betere primaire beslissing.

## Concreet Implementatieplan

## Stap 1: Huidige overlay-logica isoleren
Doel:
- huidige `filterOverlayTextViaContentMap()` niet verder uitbreiden met extra tuning.

Actie:
1. Introduceer `OverlayTextAnalyzer` als nieuwe laag.
2. Laat bestaande trim-code niet rechtstreeks meer beslissen op basis van content map.

Resultaat:
- overlay-beslissing wordt vervangbaar en testbaar.

## Stap 2: Voeg lokale patch-analyse toe
Doel:
- overlay-klassificatie op tekstblokniveau.

Actie:
1. Bouw patch extractor per overlappend tekstblok.
2. Voeg een high-resolution local feature analyzer toe:
   - pagina-achtergrond verschil,
   - local variance,
   - connected component continuity,
   - continuity richting de rand van het figuur.

Resultaat:
- eerste deterministische versie zonder externe modeldependency.

## Stap 3: Voeg model-assisted segmentatie toe
Doel:
- kwaliteit maximaliseren op moeilijke gevallen.

Actie:
1. Integreer een lokale patch-segmenter.
2. Gebruik segmentatie alleen op moeilijke overlapgevallen, niet noodzakelijk op elke figuur.
3. Laat `overlay` / `edgeOverlay` classificatie mede afhangen van maskercontinuiteit.

Resultaat:
- veel robuustere overlay-beslissing bij gradients, vignettes, video thumbnails en hero-images.

## Stap 4: Pas trim-policy aan
Doel:
- destructieve trim alleen uitvoeren bij hoge zekerheid.

Actie:
1. `uncertain` behandelen als "do not trim".
2. `pageText` alleen toekennen bij sterke negatieve overlay-evidence.

Resultaat:
- minder false negative figure crops.

## Stap 5: Regressiesuite uitbreiden
Doel:
- dit bugtype permanent afdekken.

Voeg tests toe voor:
1. headline op onderrand van foto,
2. tekst midden op foto,
3. tekst net onder foto,
4. donkere foto met witte tekst-overlay,
5. gradientrand met headline,
6. foto met badge/label linksboven,
7. video thumbnail met meerdere overlay-tekstregels.

## Verplichte kwaliteitsgates
Een oplossing is alleen acceptabel als:

1. De bovenfoto-case slaagt zonder regressie op de onderfoto.
2. Geen regressie op text-only of empty-window cases.
3. Geen extra false positives op body text.
4. Crop completeness stijgt of blijft gelijk.
5. Text-bleed rate stijgt niet.

## Alternatieven En Afweging

### Alternatief A: Content map 100x100 of 200x200
Voordelen:
1. Laagste implementatiedrempel.
2. Kleine codewijziging.

Nadelen:
1. Nog steeds verkeerde overlay-semantiek.
2. Nog steeds afhankelijk van coarse cell classification.
3. Nog steeds fragiel bij edge-overlays.

Oordeel:
- Niet structureel genoeg.

### Alternatief B: Alleen autoCropWhitespace robuuster maken
Voordelen:
1. Pakt cascade-regressies aan.
2. Lage implementatiekosten.

Nadelen:
1. Lost verkeerde trim-beslissing niet op.
2. Symptoombestrijding.

Oordeel:
- Wel doen als ondersteunende verbetering, maar niet als hoofdoplossing.

### Alternatief C: OCR-gap als primaire overlay-oplossing
Voordelen:
1. Deterministisch.
2. Eenvoudig.

Nadelen:
1. Faalmodus precies op tekst-overlay op foto.
2. Niet geschikt als bug-1 hoofdoplossing.

Oordeel:
- Goed voor candidate generation, niet voor overlay-trimming.

### Alternatief D: Model-assisted local segmentation
Voordelen:
1. Hoogste kwaliteitskans.
2. Sterk bij zachte randen, gradients, complexe foto's.
3. Semantisch rijker dan heuristieken.

Nadelen:
1. Meer integratiecomplexiteit.
2. Meer compute.

Oordeel:
- Beste richting als kwaliteit het hoogste doel is.

## Eindconclusie
De huidige Claude-analyse is sterk in symptoombeschrijving, maar nog te veel gericht op het verbeteren van een zwakke overlay-feature. Mijn voorstel is beter omdat het:

1. de overlay-vraag semantisch correcter modelleert,
2. lokale en hoge-resolutie informatie gebruikt in plaats van een coarse global map,
3. edge-overlay expliciet ondersteunt,
4. destructieve trim conservatiever maakt,
5. en uitbreidbaar is naar moderne segmentatiemodellen zonder opnieuw de architectuur te moeten omgooien.

Voor CortexVision, waar goede figuurdetectie een must-have is, is dit de juiste richting: niet meer tunen aan een grid-heuristiek, maar overstappen op lokale mask-first overlay-analyse.
