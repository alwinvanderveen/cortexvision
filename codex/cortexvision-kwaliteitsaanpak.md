# CortexVision Kwaliteitsaanpak (Maximale Detectiekwaliteit)

## Doel
CortexVision moet tekstblokken en figuren detecteren met **maximale nauwkeurigheid**.  
Snelheid, kosten en resourcegebruik zijn secundair en mogen kwaliteit niet verlagen.

## Harde Eisen (Niet Onderhandelbaar)

### Kwaliteit boven performance
- Detectiekwaliteit heeft altijd prioriteit boven latency, CPU/GPU-gebruik en geheugen.
- Bij twijfel tussen een snelle en een nauwkeurigere methode wordt de nauwkeurigere methode gekozen.
- Multi-pass, ensemble en extra validatierondes zijn verplicht zodra ze aantoonbaar kwaliteit verhogen.

### Geen kwaliteitsverlies accepteren
- Geen wijziging mag merged worden als recall, text/figure-separatie of crop-completeness verslechtert.
- Failing tests mogen niet “weggetuned” worden via zwakkere verwachtingen zonder expliciete productbeslissing.
- Elke bugfix in detectie moet regressietests toevoegen op exact het faalpatroon.

### Evidence-based beslissingen
- Elke pipeline-aanpassing moet meetbaar onderbouwd zijn met voor/na-resultaten.
- Geen “aannames op gevoel”: alleen metrics en testuitkomsten zijn leidend.

## Doelarchitectuur (Kwaliteit-First)

1. Pass A: DocLayout-YOLO detectie (figuren, tabellen, tekstregio’s).
2. Pass B: Vision detectie (saliency + instance mask) als fallback én als quality-recheck bij lage confidence of verdachte geometrie.
3. Pass C: Boundary refinement (text-relation, trim, crop, variance-tightening).
4. Pass D: Kwaliteitsvalidatie per detectie (text-bleed check, aspect plausibility, content variance, subject consistency).
5. Pass E: Fusion en ranking (beste kandidaatselectie op kwaliteitsscore, niet op snelheid).

## Activatie-Regels Voor Extra Detectierondes

Een extra detectieronde is verplicht als een van onderstaande signalen optreedt:
- Geen figuren gedetecteerd, terwijl OCR + layout sterke visuele regio’s aangeven.
- Lage modelconfidence voor figuurklassen.
- Verdachte bounds (te smal/te hoog, onwaarschijnlijke aspect ratio, grote overlap met tekst).
- Dark/low-contrast achtergrond met bekende detectierisico’s.
- Inconsistentie tussen DocLayout en Vision output.

## Harde Quality Gates

### Gate 1: Functionele testgate
- `make test` moet groen op de volledige suite.
- Geen nieuwe flaky failures toegestaan.

### Gate 2: Figuurdetectiegate
- Alle bekende regressiecases moeten passeren:
  - hero banners (top + cutout),
  - dark background met light text,
  - bottom-positioned figures,
  - middle figures met tekst boven/onder,
  - kleine figuren boven dense text,
  - real-image fixtures (Propinion/DenHaag/BlackBackground).

### Gate 3: Scheiding tekst/figuur
- Text-bleed in figuren mag niet toenemen.
- Figuren moeten semantisch compleet zijn (geen agressieve afsnijding van relevante content).

### Gate 4: Meetbare kwaliteitsverbetering
- Wijzigingen moeten aantoonbaar verbetering geven op minstens één kernmetric zonder regressie op andere kernmetrics.

## Kernmetrics (Verplicht Te Rapporteren)
- Figure Recall per scenario-type.
- Text-Bleed Rate (hoeveel tekst binnen figuurcrop blijft).
- Crop Completeness (hoeveel van relevante figuurinhoud behouden blijft).
- False Positive Rate op text-only/empty windows.
- Stability Score (zelfde input, consistente output over meerdere runs).

## Gefaseerde Uitvoering

### Fase 0 (Nu): Stabiliseren op actuele failures
- Los de huidige faalset gericht op (9 bekende failures).
- Voeg per faaltype minimaal 1 regressietest toe of versterk bestaande testdekking.

### Fase 1: Hybride pipeline hard maken
- DocLayout primair, Vision fallback + quality-recheck.
- Class-specifieke thresholds voor figuurklassen.
- Extra rondes triggeren op kwaliteitssignalen (niet alleen bij “0 detecties”).

### Fase 2: Refinement en fusion
- Verbeter hypothesis scoring met strengere text-bleed penalties.
- Voeg candidate fusion/ranking toe op kwaliteitsscore.

### Fase 3: Advanced quality mode
- Multi-pass inferentie (contrast/gamma varianten).
- Tiled inferentie voor brede/lage figuren.
- Optioneel ensemble-uitbreiding indien metrics nog tekortschieten.

## Beslisregels Voor Geparkeerde Items

Items mogen alleen geparkeerd blijven als:
- huidige metrics al op doelniveau zitten, en
- er geen open regressies in relevante scenario’s zijn.

Anders worden ze automatisch geactiveerd in de eerstvolgende fase.

## Definitie Van Klaar (Quality-First DoD)
- Volledige `make test` groen.
- Geen open regressies op bekende moeilijke scenario’s.
- Meetrapport met voor/na-metrics aanwezig.
- Geen kwaliteitsconcessies gemaakt voor performance zonder expliciete goedkeuring.
