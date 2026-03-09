# CortexVision — Backlog

## Werkwijze

> **GATE: Geen implementatie zonder akkoord op de use case.**
>
> Per stap geldt:
> 1. Use case wordt gepresenteerd aan de gebruiker
> 2. Gebruiker geeft expliciet akkoord (of feedback)
> 3. Pas na akkoord wordt de implementatie gestart
> 4. Na implementatie: tests draaien, use case wordt gevalideerd
>
> Status per use case:
> - `DRAFT` — use case is uitgewerkt, wacht op review
> - `APPROVED` — akkoord, mag worden geïmplementeerd
> - `IN PROGRESS` — wordt gerealiseerd
> - `DONE` — geïmplementeerd en gevalideerd
> - `REJECTED` — afgekeurd, moet worden herzien

---

## UC-0: Project Setup & CI

**Status:** `DONE`

### Beschrijving
Als ontwikkelaar wil ik een werkend project met versiebeheer en continuous integration zodat alle wijzigingen automatisch worden gebouwd en getest.

### Actors
- Ontwikkelaar

### Precondities
- macOS development machine met Xcode
- GitHub account

### Flow
1. Git repository wordt geïnitialiseerd
2. GitHub remote wordt aangemaakt
3. CI pipeline wordt geconfigureerd (build, test, coverage gate 85%)
4. Elke push naar main en elke PR triggert de pipeline

### Postcondities
- Code staat op GitHub
- CI draait bij elke push/PR
- Coverage onder 85% blokkeert merge

### Acceptatiecriteria
- [x] Git repo actief
- [x] GitHub remote bereikbaar
- [x] CI workflow aanwezig in `.github/workflows/ci.yml`
- [x] Coverage threshold staat op 85%

---

## UC-1: Test Infrastructure & Dashboard

**Status:** `DRAFT`

### Beschrijving
Als ontwikkelaar wil ik een browser-based test dashboard dat bij elke test run automatisch ververst en per testcase de functionele beschrijving, technische beschrijving, input, verwachte output, werkelijke output en resultaat toont, zodat ik conform TDD inzicht heb in de kwaliteit van het systeem.

### Actors
- Ontwikkelaar

### Precondities
- Xcode project bestaat met ten minste één test target
- Node.js is beschikbaar voor het dashboard

### Flow
1. Ontwikkelaar voert tests uit via `make test` of Xcode
2. `.xcresult` bundle wordt gegenereerd
3. Parser script converteert xcresult naar gestructureerde JSON
4. Dashboard leest JSON en toont resultaten
5. Bij een nieuwe test run detecteert de file watcher de wijziging
6. Dashboard ververst automatisch in de browser

### Postcondities
- Dashboard draait op localhost:5173
- Alle testcases zijn zichtbaar met metadata
- Coverage percentage is zichtbaar als gauge

### Acceptatiecriteria
- [ ] `make test` voert tests uit en genereert JSON output
- [ ] Dashboard toont per testcase: functionele beschrijving, technische beschrijving, input, output, resultaat
- [ ] Coverage gauge toont percentage en kleurt rood/oranje/groen
- [ ] Auto-refresh werkt binnen 2 seconden na nieuwe test run
- [ ] Dashboard is bereikbaar op localhost:5173

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-1.1 | Run `make test` met passing tests | JSON bevat alle tests met status PASS |
| TC-1.2 | Run `make test` met een failing test | Dashboard toont FAIL met foutmelding |
| TC-1.3 | Voer nieuwe test run uit terwijl dashboard open is | Dashboard ververst automatisch |
| TC-1.4 | Coverage is 80% | Gauge toont 80% in oranje/rood |
| TC-1.5 | Coverage is 90% | Gauge toont 90% in groen |

---

## UC-2: Xcode Project & Basis UI

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik een macOS applicatie kunnen starten met een overzichtelijk hoofdvenster waarin ik kan kiezen tussen capture-modi (venster selectie of gebiedsselectie) en een preview kan zien van het resultaat, zodat ik een duidelijk startpunt heb voor het capturen van scherminhoud.

### Actors
- Eindgebruiker

### Precondities
- macOS 13+ (Ventura)
- Applicatie is geïnstalleerd

### Flow
1. Gebruiker start CortexVision
2. Hoofdvenster opent met toolbar en lege preview
3. Toolbar bevat knoppen: "Selecteer Venster", "Selecteer Gebied", "Scrolling Capture"
4. Gebruiker ziet een statusbalk met huidige modus
5. Preview paneel toont placeholder tekst wanneer er nog geen capture is

### Postcondities
- Applicatie draait als native macOS window
- UI volgt macOS design guidelines
- Alle capture-modi zijn zichtbaar maar nog niet functioneel

### Acceptatiecriteria
- [ ] App start zonder crashes op macOS 13+
- [ ] Hoofdvenster heeft toolbar met drie capture-modus knoppen
- [ ] Preview paneel is zichtbaar en toont placeholder
- [ ] Window is resizable met minimum afmetingen
- [ ] App verschijnt in de Dock en heeft een menu bar
- [ ] UI gebruikt SF Symbols voor iconen
- [ ] Dark mode en light mode worden correct ondersteund

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-2.1 | Start applicatie | Hoofdvenster opent zonder crash |
| TC-2.2 | Resize venster naar minimum | Venster respecteert minimum afmetingen |
| TC-2.3 | Wissel tussen dark/light mode | UI past zich correct aan |
| TC-2.4 | Klik op capture-modus knop | Modus wordt visueel geselecteerd in toolbar |

---

## UC-3: Venster & Gebied Capture

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik een specifiek venster of een zelf getekend schermgebied kunnen selecteren en daar een screenshot van maken, zodat ik gericht inhoud kan capturen voor verdere analyse.

### Actors
- Eindgebruiker

### Precondities
- CortexVision is gestart
- Screen Recording permissie is verleend door gebruiker

### Flow — Venster selectie
1. Gebruiker klikt "Selecteer Venster"
2. Lijst van beschikbare vensters verschijnt (met app-icoon en titel)
3. Gebruiker kiest een venster
4. Screenshot wordt gemaakt van het geselecteerde venster
5. Resultaat verschijnt in het preview paneel

### Flow — Gebied selectie
1. Gebruiker klikt "Selecteer Gebied"
2. Scherm dimt en crosshair cursor verschijnt
3. Gebruiker tekent een rechthoek door te klikken en te slepen
4. Geselecteerd gebied wordt gemarkeerd
5. Bij loslaten wordt de capture gemaakt
6. Resultaat verschijnt in het preview paneel

### Postcondities
- Capture is beschikbaar als CGImage in het geheugen
- Preview toont de capture op schaal
- Capture dimensies worden getoond in de statusbalk

### Acceptatiecriteria
- [ ] Vensterpicker toont alle zichtbare vensters met titel en icoon
- [ ] Geselecteerd venster wordt correct gecaptured (inclusief inhoud)
- [ ] Gebiedsselectie overlay bedekt het hele scherm
- [ ] Getekende rechthoek is visueel zichtbaar tijdens selectie
- [ ] Capture wordt correct weergegeven in preview
- [ ] Bij ontbrekende Screen Recording permissie: duidelijke foutmelding
- [ ] ESC annuleert de selectie

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-3.1 | Capture venster van Finder | CGImage met correcte afmetingen van Finder venster |
| TC-3.2 | Capture gebied van 500x300px | CGImage is exact 500x300 pixels |
| TC-3.3 | Annuleer selectie met ESC | Geen capture, terug naar hoofdvenster |
| TC-3.4 | Capture zonder Screen Recording permissie | Foutmelding met link naar System Settings |
| TC-3.5 | Capture venster dat gedeeltelijk buiten scherm valt | Volledige vensterinhoud wordt gecaptured |

---

## UC-4: OCR Pipeline

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik dat na een capture automatisch alle tekst wordt herkend en gestructureerd weergegeven, zodat ik de tekstinhoud kan inzien en exporteren zonder handmatig over te typen.

### Actors
- Eindgebruiker
- Systeem (automatisch na capture)

### Precondities
- Er is een capture beschikbaar (uit UC-3 of UC-6)

### Flow
1. Na een capture start de OCR pipeline automatisch
2. Voortgangsindicator toont dat analyse bezig is
3. Vision framework verwerkt de afbeelding
4. Herkende tekstblokken worden geïdentificeerd met positie en confidence
5. Tekstblokken worden gesorteerd op leesvolgoorde (top-left → bottom-right)
6. Resultaat verschijnt in een tekst-paneel naast de preview
7. Lage-confidence woorden worden gemarkeerd (bijv. oranje highlight)

### Postcondities
- Alle herkende tekst is beschikbaar als gestructureerde data
- Tekst is gesorteerd in leesvolgorde
- Confidence scores zijn beschikbaar per woord/blok

### Acceptatiecriteria
- [ ] OCR herkent Engels en Nederlands
- [ ] Tekst wordt in correcte leesvolgorde gepresenteerd
- [ ] Confidence score per blok is beschikbaar
- [ ] Woorden met confidence < 0.7 worden visueel gemarkeerd
- [ ] Voortgangsindicator is zichtbaar tijdens verwerking
- [ ] OCR draait asynchroon (UI blokkeert niet)
- [ ] Verwerking van een A4-pagina duurt < 3 seconden

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-4.1 | OCR op afbeelding met duidelijke zwarte tekst op wit | >95% correcte herkenning |
| TC-4.2 | OCR op afbeelding met Nederlandse tekst (diacrieten) | Correcte herkenning van ë, é, ü, etc. |
| TC-4.3 | OCR op afbeelding met meerdere kolommen | Kolommen worden apart herkend, juiste volgorde |
| TC-4.4 | OCR op afbeelding zonder tekst | Leeg resultaat, geen crash |
| TC-4.5 | OCR op grote afbeelding (4K) | Resultaat binnen 5 seconden |
| TC-4.6 | OCR op afbeelding met lage resolutie / vage tekst | Lage confidence scores, woorden gemarkeerd |

---

## UC-5: Figuur Detectie & Extractie

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik dat figuren (grafieken, diagrammen, afbeeldingen, tabellen) automatisch worden herkend en als losse bestanden worden opgeslagen, zodat ik visuele elementen apart kan hergebruiken.

### Actors
- Eindgebruiker
- Systeem (automatisch, parallel aan OCR)

### Precondities
- Er is een capture beschikbaar

### Flow
1. Na capture start figuurdetectie parallel aan OCR
2. Systeem detecteert rechthoekige regio's die geen tekst bevatten
3. Per gedetecteerde figuur wordt een bounding box bepaald
4. Figuren worden uitgesneden als losse afbeeldingen
5. In het preview paneel worden figuren met een kader gemarkeerd
6. Gebruiker kan figuren aan/uit selecteren voor export
7. Elke figuur krijgt een genummerd label (Figuur 1, Figuur 2, ...)

### Postcondities
- Figuren zijn als losse CGImage objecten beschikbaar
- Elke figuur heeft een bounding box, label en type-indicatie
- Tekstregio's zijn uitgesloten van figuurdetectie

### Acceptatiecriteria
- [ ] Rechthoekige figuren worden gedetecteerd met >90% nauwkeurigheid
- [ ] Tekstregio's worden niet als figuur aangemerkt
- [ ] Gedetecteerde figuren worden visueel gemarkeerd in preview
- [ ] Gebruiker kan individuele figuren deselecteren
- [ ] Figuren worden gelabeld met volgnummer
- [ ] Overlappende detecties worden samengevoegd

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.1 | Afbeelding met 1 grafiek en tekst | Grafiek gedetecteerd, tekst niet |
| TC-5.2 | Afbeelding met 3 foto's naast elkaar | 3 aparte figuren gedetecteerd |
| TC-5.3 | Afbeelding met alleen tekst | Geen figuren gedetecteerd |
| TC-5.4 | Afbeelding met tabel | Tabel als figuur gedetecteerd |
| TC-5.5 | Afbeelding met overlappende figuren | Samengevoegd tot één figuur |
| TC-5.6 | Figuur deselecteren door gebruiker | Figuur wordt uitgesloten van export |

---

## UC-6: Scrolling Capture

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik een lang document (zoals een webpagina of PDF) in zijn geheel kunnen capturen door het automatisch te laten scrollen en de frames samen te voegen, zodat ik niet beperkt ben tot wat zichtbaar is op het scherm.

### Actors
- Eindgebruiker

### Precondities
- CortexVision is gestart
- Accessibility permissie is verleend
- Screen Recording permissie is verleend
- Een scrollbaar venster is geselecteerd

### Flow
1. Gebruiker klikt "Scrolling Capture"
2. Gebruiker selecteert het venster dat gescrolld moet worden
3. Systeem detecteert of het venster scrollbaar is
4. Voortgangsbalk verschijnt met "Capturing..."
5. Systeem scrollt het document stapsgewijs naar beneden
6. Per stap wordt een frame gecaptured
7. Frames worden samengevoegd met overlap-detectie (image stitching)
8. Gebruiker kan de capture stoppen met ESC of de Stop-knop
9. Resultaat verschijnt als één lange afbeelding in het preview paneel

### Postcondities
- Volledige documentinhoud is gecaptured als één afbeelding
- Geen duplicaten of gaten in het samengestelde beeld
- Preview toont scrollbare weergave van het totaalbeeld

### Acceptatiecriteria
- [ ] Scroll capture werkt op Safari, Chrome, Preview, en Finder
- [ ] Overlap-detectie voorkomt duplicatie in het samengestelde beeld
- [ ] Voortgangsbalk toont schatting van voortgang
- [ ] ESC en Stop-knop stoppen het proces onmiddellijk
- [ ] Bij handmatige stop wordt het tot dan toe gecapturde beeld behouden
- [ ] Accessibility permissie wordt gevraagd als die ontbreekt
- [ ] Capture van een pagina van 5000px hoogte duurt < 15 seconden

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-6.1 | Scrolling capture van lange webpagina in Safari | Volledig samengesteld beeld zonder gaten |
| TC-6.2 | Stop capture halverwege met ESC | Gedeeltelijk beeld behouden |
| TC-6.3 | Capture van niet-scrollbaar venster | Duidelijke melding, valt terug op normale capture |
| TC-6.4 | Capture van document met horizontale en verticale scroll | Alleen verticale scroll wordt gecaptured |
| TC-6.5 | Twee opeenvolgende captures van hetzelfde document | Identiek resultaat (deterministic) |

---

## UC-7: Export Engine

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik de herkende tekst als geformateerd Markdown-bestand en de figuren als losse PNG-bestanden kunnen exporteren naar een zelf gekozen locatie, zodat ik het resultaat direct kan gebruiken in andere applicaties.

### Actors
- Eindgebruiker

### Precondities
- OCR en figuurdetectie zijn afgerond
- Ten minste tekst of figuren zijn gedetecteerd

### Flow
1. Gebruiker klikt "Exporteer"
2. Export dialoog opent met opties:
   - Exportlocatie (folder picker)
   - Bestandsnaam (automatisch gegenereerd, aanpasbaar)
   - Formaat: Markdown (tekst) + PNG (figuren)
   - Optie: alleen tekst / alleen figuren / beide
3. Gebruiker bevestigt
4. Markdown bestand wordt gegenereerd:
   - Tekst in leesvolgorde
   - Koppen, paragrafen en lijsten worden herkend
   - Referenties naar figuren: `![Figuur 1](./figuren/figuur-1.png)`
5. Figuren worden als genummerde PNG-bestanden opgeslagen in subfolder
6. Bevestiging met link om de folder te openen in Finder

### Postcondities
- Markdown bestand staat op de gekozen locatie
- Figuren staan in een `figuren/` subfolder
- Alle referenties in Markdown kloppen

### Acceptatiecriteria
- [ ] Markdown bevat correct geformatteerde tekst
- [ ] Koppen worden herkend (gebaseerd op lettergrootte/gewicht)
- [ ] Figuren worden opgeslagen als PNG met transparante achtergrond waar mogelijk
- [ ] Figuur referenties in Markdown zijn correcte relatieve paden
- [ ] Bestandsnamen bevatten geen spaties of speciale tekens
- [ ] Export van een document met 5 pagina's en 10 figuren duurt < 10 seconden
- [ ] Bij export van alleen tekst worden geen figuurbestanden aangemaakt

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-7.1 | Export document met tekst en 3 figuren | 1 MD-bestand + 3 PNG's in figuren/ |
| TC-7.2 | Export alleen tekst | 1 MD-bestand, geen figuren/ folder |
| TC-7.3 | Export alleen figuren | Geen MD-bestand, wel figuren/ met PNG's |
| TC-7.4 | Export met bestaand bestand op dezelfde locatie | Waarschuwing, optie om te overschrijven |
| TC-7.5 | Open export folder in Finder | Finder opent op de juiste locatie |
| TC-7.6 | Markdown openen in editor | Correcte formatting, werkende figuur links |

---

## Implementatievolgorde

```
UC-0 [DONE] ──► UC-1 [DRAFT] ──► UC-2 [DRAFT] ──► UC-3 [DRAFT]
                                                        │
                                                        ▼
                                  UC-7 [DRAFT] ◄── UC-5 [DRAFT]
                                       ▲            │
                                       │            ▼
                                  UC-6 [DRAFT]  UC-4 [DRAFT]
```

UC-4 en UC-5 kunnen deels parallel worden ontwikkeld na UC-3.
UC-6 en UC-7 kunnen deels parallel worden ontwikkeld na UC-4+UC-5.
