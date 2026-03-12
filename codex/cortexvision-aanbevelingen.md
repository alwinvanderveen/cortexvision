# CortexVision Aanbevelingen En Brainstormrichtingen

## Context
- Laatste testresultaat: 189 tests, 180 geslaagd, 9 gefaald, coverage 82.8%.
- Belangrijkste probleemgebied: figuurdetectie onder moeilijke condities (dark background, positie onderaan, subtiele contrasten, tekst-bleed).
- Richting: herkenningskwaliteit boven snelheid en resourcegebruik.

## Topaanbevelingen (Implementatie)

### 1. Versterk fallback-keten voor figuurdetectie
- Voeg een extra fallback-pass toe als saliency en instance-mask geen figuren vinden.
- Gebruik content-component analyse op OCR-gemaskeerde beelden.
- Voeg dark-background specifieke detectie toe (niet alleen light-background heuristiek).
- Doel: hogere recall voor moeilijk zichtbare figuren.

### 2. Maak boundary-refinement robuuster
- Verfijn scoring van hypotheses met extra straf voor tekst-bleed aan boven/onderranden.
- Voeg vormpriors toe (banner, portrait, near-square) op basis van layout-context.
- Maak edge-detectie minder agressief bij zachte randen en gradient-overgangen.
- Doel: minder oversnijden of verkeerd kaderen van figuren.

### 3. Integreer bestaande expand-logica in de hoofdpipeline
- Breng `snapToEdges`, `directionalExpand`, `expandToIncludeSubjects` in actieve detectieflow.
- Gebruik deze niet alleen als losse helper/tests, maar als standaard stap na candidate selectie.
- Doel: betere breedtehoogte-verhoudingen en minder tekst-inclusie.

### 4. Verbeter DocLayout-detectie op echte fixtures
- Gebruik class-specifieke confidence thresholds (`figure` en `table` lager dan tekst).
- Voeg multi-pass inferentie toe (origineel + contrast/gamma variant).
- Gebruik tiled inferentie voor brede hero-secties.
- Doel: meer robuuste detectie in uiteenlopende pagina-achtergronden.

### 5. Versterk OCR-output voor betere text-masking
- Vervang eenvoudige woord-range lookup door sequentiële token-range matching.
- Behoud stabiele woord-bounding-boxes bij herhaalde tokens.
- Doel: betrouwbaardere tekstuitsluiting in figuurpipeline.

## Prioriteit En Volgorde
1. P0: fallback-keten + dark-background mode + boundary scoring.
2. P1: actieve integratie van expand-logica in pipeline.
3. P1: DocLayout multi-pass + class-thresholds + tiled inferentie.
4. P2: OCR word-box robuustheid.
5. P2: model-ensemble en fusion.

## Brainstormsuggesties Voor Beste Oplossing

### Modelstrategie
- Moeten we een ensemble gebruiken: Vision saliency + instance mask + ONNX DocLayout + segmentatiemodel?
- Welke segmentatiemodellen geven de hoogste kwaliteit voor schermcontent (diagrammen, hero-images, mixed UI)?
- Willen we een expert-router die per scene-type het beste model activeert?

### Architectuur
- Willen we een 2-stage pipeline (detecteer regio -> segmenteer nauwkeurig) of 3-stage (detecteer -> refine -> validate)?
- Kunnen we een quality-gate inbouwen die automatisch een extra pass draait bij lage confidence of verdachte aspect ratio?
- Willen we modeloutputs fuseren via weighted box fusion of mask-level fusion?

### Data En Evaluatie
- Welke benchmarkset bouwen we als gouden standaard (dark, low contrast, mixed text/figure, scroll captures)?
- Welke metrics prioriteren we: recall@figure, IoU, text-bleed rate, crop-completeness?
- Kunnen we per failing test een regressieprofiel maken met root-cause label?

### Post-processing
- Hoe detecteren we betrouwbaar tekst-bleed zonder goede figuurdelen weg te snijden?
- Kunnen we edge confidence maps toevoegen om zachte overgangen (gradient heroes) beter te behouden?
- Is een learned post-processor (klein model) beter dan handmatige heuristieken?

### Productbeslissingen
- Willen we per capture meerdere varianten genereren en de beste automatisch kiezen?
- Moeten we een expliciete "quality mode max" aanbieden die altijd multi-pass en ensemble gebruikt?
- Willen we gebruikersfeedback (correctie van boxen) terugvoeden naar adaptieve thresholds?

## Voorstel Voor Volgende Iteratie
1. Implementeer P0 en draai `make test`.
2. Vergelijk voor/na per falende test met concrete delta.
3. Verwerk P1 alleen op basis van meetbare kwaliteitswinst.
4. Start daarna een korte model-ensemble spike voor maximale recall.
