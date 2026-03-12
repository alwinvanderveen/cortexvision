# Instructie Voor Claude: Compliance En Kwaliteitsaanpak (Interne Gebruiksscope)

## Doel Van Deze Instructie
Deze instructie beschrijft hoe je CortexVision structureel verder ontwikkelt met:
- maximale detectiekwaliteit als primair doel,
- controleerbare licentie- en modelcompliance voor initiële interne inzet,
- duidelijke gates voordat de applicatie ooit extern gedeeld wordt.

## Opdracht
Voer de aanpak hieronder uit als leidend protocol.  
Geen shortcuts. Geen impliciete aannames. Alle beslissingen moeten aantoonbaar zijn met feiten uit code, tests, documentatie en licentiebronnen.

## Harde Eisen (Niet Onderhandelbaar)

1. Detectiekwaliteit gaat boven performance en resourceverbruik.
2. Tests mogen niet worden verzwakt om failures te maskeren.
3. Elke wijziging in detectielogica moet regressieproof zijn met tests.
4. Licentiebeoordeling gebeurt op code, modelgewichten en datasets afzonderlijk.
5. “Alleen intern gebruik” is geen vrijbrief: verplichtingen blijven relevant.
6. Voor onduidelijke licenties: niet gebruiken tot geverifieerd.

## Definities Voor Interne Inzet

Gebruik onderstaande werkdefinitie totdat legal anders bepaalt:

1. Interne inzet = alleen gebruikers binnen dezelfde rechtspersoon.
2. Geen toegang voor klanten, partners, leveranciers, freelancers buiten de rechtspersoon.
3. Geen distributie van binaries, SDK’s of hosted endpoints buiten intern netwerk.
4. Geen public demo-omgevingen, publieke API’s of gedeelde test-URLs.

Als één van deze punten niet meer waar is, geldt direct de “externe inzet”-fase en moet een nieuwe compliance review plaatsvinden.

## Licentie-Risicoklassen (Operationeel)

### Klasse A: Permissive
Voorbeelden: MIT, Apache-2.0, BSD.
Actie:
- toestaan met NOTICE/licentietekst in third-party register.
- attribuering en copyrightregels correct opnemen.

### Klasse B: Attributie/gebruiksvoorwaarden
Voorbeelden: CC-BY, modelspecifieke voorwaarden.
Actie:
- expliciete attributie opnemen.
- check op aanvullende voorwaarden (naamvermelding, documentatieplicht, gebruiksrestricties).

### Klasse C: Sterke copyleft of network copyleft
Voorbeelden: GPL-3.0, AGPL-3.0.
Actie:
- alleen gebruiken na expliciete architectuurbeslissing en impactanalyse.
- verplicht intern dossier met risico’s, trigger-events en broncodeverplichtingen.
- bij twijfel blokkeren voor productiegebruik.

### Klasse D: Niet-standaard modellicenties
Voorbeelden: OpenRAIL-varianten, custom model terms.
Actie:
- apart beoordelen van code- en modellicentie.
- specifieke beperkingen vastleggen (commercieel gebruik, redistributie, safety clauses).
- blokkeren als voorwaarden niet verifieerbaar zijn.

## Verplichte Opleverartefacten (In Repo)

Maak en onderhoud minimaal:

1. `codex/license-inventory.md`
2. `codex/model-license-inventory.md`
3. `codex/third-party-notices.md`
4. `codex/compliance-decision-log.md`
5. `codex/compliance-open-questions.md`
6. `codex/quality-metrics-baseline.md`
7. `codex/quality-regression-report.md`

## Uitvoeringsaanpak Per Fase

## Fase 0: Baseline Vastleggen
Doel: huidige status objectief vastleggen.

Taken:
1. Draai volledige testsuite via `make test`.
2. Noteer pass/fail, coverage en lijst met falende scenario’s.
3. Leg baseline metrics vast:
- figure recall,
- false positives op text-only/empty,
- text-bleed rate,
- crop completeness,
- stabiliteit over meerdere runs op dezelfde input.

Output:
- update `codex/quality-metrics-baseline.md`

## Fase 1: Volledige Dependency- En Modelinventarisatie
Doel: weten wat er juridisch en technisch precies in de stack zit.

Taken:
1. Inventariseer alle libraries/packages in build/runtime/test.
2. Inventariseer alle modellen en modelweights.
3. Inventariseer gebruikte datasets/testassets met herkomst.
4. Per item: naam, versie, bron-URL, licentie, rol in pipeline.

Output:
- `codex/license-inventory.md`
- `codex/model-license-inventory.md`

## Fase 2: Compliance-Risicoanalyse
Doel: per component risico + toepasbaarheid voor interne inzet bepalen.

Taken:
1. Classificeer elk item in A/B/C/D (zie risicoklassen).
2. Documenteer trigger-events:
- wat verandert bij externe toegang,
- wat verandert bij distributie,
- wat verandert bij model-finetuning of gewijzigde code.
3. Leg per risicovol item een actiepad vast:
- toestaan,
- tijdelijk blokkeren,
- vervangen.

Output:
- `codex/compliance-decision-log.md`
- `codex/compliance-open-questions.md`

## Fase 3: Kwaliteitsgerichte Architectuurversterking
Doel: reliability structureel verhogen, niet parametrisch “tunen”.

Verplichte richting:
1. Hybride detectie blijft backbone.
2. Extra detectierondes triggeren bij onzekerheid:
- lage confidence,
- verdachte geometrie,
- model-disagreement,
- moeilijke backgrounds.
3. Refinement en validatie verplicht vóór definitieve output.
4. Geen single-signal beslissingen bij conflictgevallen.

Output:
- architectuurbeslissingen en rationale in `codex/compliance-decision-log.md` (technisch + juridisch impact).

## Fase 4: Kwaliteitsgates In CI/Workflow
Doel: regressie blokkeren met harde criteria.

Gatevoorwaarden:
1. Alle tests groen via `make test`.
2. Geen verslechtering op kernmetrics.
3. Geen open compliance blocker in klasse C of D.
4. Voor elke nieuw toegevoegde dependency/model:
- inventaris update,
- besluit update,
- notice update.

Output:
- `codex/quality-regression-report.md`

## Fase 5: Interne Productie-Readiness
Doel: veilig intern draaien met beheersbare risico’s.

Taken:
1. Beperk toegang tot interne gebruikers.
2. Borg dat captures/logs met gevoelige data afgeschermd zijn.
3. Definieer bewaartermijn voor screenshots/resultaten.
4. Leg operationele procedures vast voor incidenten en rollback.

Output:
- update decision log met “go/no-go intern”.

## Fase 6: Voorbereiding Op Externe Inzet (Nog Niet Activeren)
Doel: klaarstaan zonder nu al extern te gaan.

Taken:
1. Maak een expliciete checklist “wat verandert bij extern gebruik”.
2. Benoem welke componenten herzien/vervangen moeten worden.
3. Plan legal reviewmoment vóór externe release.

Output:
- sectie “external readiness” in `codex/compliance-open-questions.md`.

## Kwaliteitsmetrics (Verplicht)

Per run rapporteren:

1. Figure recall per scenario-type.
2. Text-bleed rate.
3. Crop completeness.
4. False positive rate.
5. Stabiliteit (zelfde input, meerdere runs).
6. Aantal open regressies.

Regel:
- Een wijziging is alleen “verbetering” als bovenstaande metrics niet verslechteren.

## Beslisregels Voor Nieuwe Modellen Of Tools

Voordat je een model/tool toevoegt:

1. Licentieklasse bepaald (A/B/C/D).
2. Code- én modellicentie afzonderlijk geverifieerd.
3. Impact op interne-use scope beschreven.
4. Impact op externe-use scope beschreven.
5. Quality impact verwacht en meetplan gedefinieerd.

Als één punt ontbreekt: niet integreren.

## Verboden Handelingen

1. Geen testverwachtingen aanpassen om codeproblemen te maskeren.
2. Geen dependencies of models “stil” toevoegen zonder inventarisupdate.
3. Geen claims over compliance zonder bronverwijzing.
4. Geen “tijdelijke” shortcuts die niet in decision log staan.

## Standaard Rapportage Na Elke Iteratie

Lever na iedere substantiële wijziging:

1. Korte changelog.
2. Voor/na testresultaat.
3. Voor/na kwaliteitsmetrics.
4. Eventuele nieuwe licentie-impact.
5. Open risico’s en voorgestelde vervolgstap.

## Escalatieregels

Escaleren naar gebruiker wanneer:

1. Licentievoorwaarden tegenstrijdig of onduidelijk zijn.
2. Een kwaliteitverbetering één of meer kritieke metrics verslechtert.
3. Externe inzet in beeld komt.
4. Er geen duidelijk compliant pad bestaat met huidige componentkeuze.

## Slot
Werk volgens dit protocol totdat een expliciete nieuwe instructie het vervangt.  
Doel blijft: maximaal betrouwbare detectie, aantoonbaar compliant, zonder verborgen risico’s.
