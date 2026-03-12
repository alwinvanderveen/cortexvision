# Review Op Claude Voorstel v3 (OCR-gap first)

## Doel Van Deze Review
Deze review geeft een onderbouwd oordeel op:
- [eerlijk-voorstel-figuurdetectie-v3.md](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md)
- en de relatie met eerdere Claude-analyse:
  - [analyse-codex-advies-vs-architectuurvoorstel.md](/Users/alwinvanderveen/projects/cortexvison/Claude/analyse-codex-advies-vs-architectuurvoorstel.md)

Doel: een technisch verdedigbare conclusie waar Claude direct op kan doorbouwen.

## Samenvatting Oordeel

Het OCR-gap voorstel is inhoudelijk sterk als **extra primair signaal** voor pagina’s met duidelijke verticale structuur, maar te risicovol als **enige architecturale basis** voor maximale betrouwbaarheid.

Kernconclusie:
1. OCR-gap first is een waardevolle verbetering.
2. OCR-gap only is niet voldoende robuust.
3. Kwaliteitsvalidatie en metrics blijven noodzakelijk als structurele kwaliteitsgates.

## Hoe Ik Tot Deze Conclusie Kwam

## Stap 1: Controle van probleemdiagnose
Claude stelt dat saliency-first fundamenteel instabiel is:
- non-deterministisch,
- resolutie-afhankelijk,
- niet semantisch.

Dat is coherent met de geschetste observaties in v3:
- [v3:41](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:41)
- [v3:43](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:43)
- [v3:44](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:44)

Beoordeling: diagnose is plausibel en technisch geloofwaardig.

## Stap 2: Analyse van het voorgestelde alternatief
Claude positioneert OCR-gap detectie als primair signaal:
- [v3:93](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:93)
- [v3:97](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:97)

Sterke punten:
1. Deterministischer gedrag dan saliency-only.
2. Leunt op bestaande OCR-data in plaats van extra modelafhankelijkheid.
3. Eenvoudiger en testbaarder implementatiepad.

Beoordeling: sterk als kandidaat-generator voor duidelijke tekst-figuur-segmentatie.

## Stap 3: Validatie van generaliseerbaarheid
Claude noemt zelf beperkingen:
- geen tekst = geen gaps,
- side-by-side layouts,
- tekstoverlay op figuren,
- kleine figuren tussen tekstregels.

Zie:
- [v3:116](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:116)
- [v3:117](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:117)
- [v3:118](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:118)
- [v3:119](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:119)

Beoordeling: als deze beperkingen gelden, kan OCR-gap niet de enige pijler zijn voor “maximaal betrouwbare detectie”.

## Stap 4: Toets op methodologische claims
Claude stelt dat validatie-pass en metrics geen noodzakelijke verbetering zijn:
- [v3:23](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:23)
- [v3:25](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:25)

Mijn tegenargument:
1. Validatie-pass verhoogt niet direct recall, maar voorkomt dat slechte output doorstroomt.
2. Metrics verbeteren geen detectie direct, maar zijn essentieel om regressie objectief te blokkeren.
3. Zonder gates ontstaat opnieuw parametrische drift zonder kwaliteitscontrole.

Beoordeling: deze onderdelen zijn architectonisch ondersteunend en blijven noodzakelijk.

## Stap 5: Interne consistentiecheck met eerdere Claude-analyse
Eerder adviseerde Claude juist validatie-pass als laag-risico stap:
- [analyse-codex-advies-vs-architectuurvoorstel.md:120](/Users/alwinvanderveen/projects/cortexvison/Claude/analyse-codex-advies-vs-architectuurvoorstel.md:120)

Beoordeling: v3 is scherper op signaalkeuze, maar de volledige afwijzing van Pass D/metrics is te absoluut.

## Concrete Conclusie

### Wat ik overneem uit v3
1. Saliency-first moet gedegradeerd worden; niet langer fundament.
2. OCR-gap analyse is een sterke, deterministische primaire kandidaatbron in tekst-gedreven pagina’s.
3. Complexe heuristische tuning op instabiele input moet worden verminderd.

### Wat ik niet overneem uit v3
1. “Lost alle root causes op” als algemene claim:
   - [v3:183](/Users/alwinvanderveen/projects/cortexvison/Claude/eerlijk-voorstel-figuurdetectie-v3.md:183)
2. Impliciete suggestie dat validatie en metrics niet noodzakelijk zijn.
3. Positionering alsof OCR-gap als enige primaire aanpak voldoende is voor alle scenario’s.

## Aanbevolen Richting Voor Claude

## Richting A (aanbevolen)
1. Voeg OCR-gap toe als **extra primaire kandidaatgenerator**.
2. Behoud DocLayout en Vision als parallelle signalen (niet leading, wel beschikbaar).
3. Introduceer verplichte kwaliteitvalidatie (text-bleed, aspect plausibility, crop-completeness).
4. Beslis met fusion/ranking op kwaliteitsscore.
5. Borg met metrics en regressiegates.

## Richting B (afgeraden)
1. Vervang alles door OCR-gap-only.
2. Verwijder/neutraliseer validatie en metrics.
3. Vertrouw op beperkte scenario-sterkte zonder brede benchmark.

Waarom afgeraden:
- te kwetsbaar buiten tekst-gedreven verticale layouts,
- hogere kans op stille regressies in edge-cases.

## Besliscriterium Voor Volgende Iteratie
Claude kan dit voorstel als “nodige verbetering” beschouwen als het onderstaande waar is:

1. OCR-gap integratie verhoogt recall op huidige failset.
2. Geen verslechtering op text-only/empty en side-by-side gevallen.
3. Text-bleed rate neemt af of blijft stabiel.
4. Stabiliteit over meerdere runs op dezelfde capture verbetert aantoonbaar.
5. Alle resultaten zijn reproduceerbaar via `make test`.

## Eindoordeel In Eén Zin
OCR-gap first is een goede bouwsteen, maar alleen in combinatie met kwaliteitsvalidatie, multi-signaal fallback en metriekgedreven gates haal je structureel de betrouwbaarheid die CortexVision nodig heeft.
