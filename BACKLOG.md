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

**Status:** `DONE`

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

**Status:** `DONE`

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

**Status:** `DONE`

### Beschrijving
Als gebruiker wil ik een specifiek venster of een zelf getekend schermgebied kunnen selecteren en daar een screenshot van maken, zodat ik gericht inhoud kan capturen voor verdere analyse.

### Actors
- Eindgebruiker

### Precondities
- CortexVision is gestart
- Screen Recording permissie is verleend door gebruiker

### Flow — Venster selectie
1. Gebruiker klikt "Select Window"
2. Lijst van beschikbare vensters verschijnt (met app-icoon en titel)
3. Gebruiker kiest een venster
4. Screenshot wordt gemaakt van het geselecteerde venster
5. Resultaat verschijnt in het preview paneel met overlay-laag, statusbalk toont dimensies

### Flow — Gebied selectie
1. Gebruiker klikt "Select Region"
2. Scherm dimt en crosshair cursor verschijnt
3. Gebruiker tekent een rechthoek door te klikken en te slepen
4. Geselecteerd gebied wordt gemarkeerd
5. Bij loslaten wordt de capture gemaakt
6. Resultaat verschijnt in het preview paneel met overlay-laag

### Postcondities
- Capture is beschikbaar als CGImage in het geheugen
- Preview toont de capture met een overlay-laag voor analyse-annotaties
- Capture dimensies worden getoond in de statusbalk

### Classificatie per onderdeel
| Onderdeel | Classificatie | Toelichting |
|-----------|--------------|-------------|
| ScreenCaptureKitProvider | `PRODUCTIE` | Concrete impl van CaptureProvider protocol. SCShareableContent + SCScreenshotManager. |
| Vensterpicker UI | `PRODUCTIE` | SwiftUI sheet met SCShareableContent.windows, app-icoon, titel. |
| Gebiedsselectie overlay | `PRODUCTIE` | Fullscreen NSWindow, crosshair, rubber-band, ESC-annulering. AppKit via coordinator. |
| LocalPermissionManager | `PRODUCTIE` | Concrete impl van PermissionManager. CGPreflightScreenCaptureAccess / CGRequestScreenCaptureAccess. |
| Preview met overlay-laag | `PRODUCTIE` (preview) + `SCAFFOLD` (overlay data) | De overlay-component accepteert `[AnalysisOverlay]` maar toont pas annotaties als UC-4/UC-5 data leveren. Component zelf is productie-code. |

### Overlay-laag detail (SCAFFOLD onderdeel)
- **Reden:** Analyse-data (tekst bounding boxes, figuur bounding boxes) komt uit UC-4 en UC-5 die nog niet geïmplementeerd zijn
- **Huidige invulling:** Preview bevat een `AnalysisOverlayView` die een array van `AnalysisOverlay` items rendert. Array is leeg tot UC-4/UC-5 data leveren. Geen fake annotaties.
- **Vervangplan:** UC-4 vult overlay met tekst-bounding boxes (blauw), UC-5 vult overlay met figuur-bounding boxes (groen)
- **Data model (nu al gedefinieerd):**
```swift
struct AnalysisOverlay: Identifiable {
    let id: UUID
    let bounds: CGRect          // genormaliseerd 0..1
    let kind: OverlayKind       // .text of .figure
    let label: String?
}
enum OverlayKind { case text, figure }
```

### Acceptatiecriteria
- [ ] Vensterpicker toont alle zichtbare vensters met titel en icoon
- [ ] Geselecteerd venster wordt correct gecaptured (inclusief inhoud)
- [ ] Gebiedsselectie overlay bedekt het hele scherm
- [ ] Getekende rechthoek is visueel zichtbaar tijdens selectie
- [ ] Capture wordt correct weergegeven in preview
- [ ] Preview bevat overlay-laag die AnalysisOverlay items kan renderen
- [ ] Bij ontbrekende Screen Recording permissie: duidelijke foutmelding met link naar System Settings
- [ ] ESC annuleert de selectie
- [ ] Statusbalk toont dimensies na capture

### Testcases — Unit (draaien overal, ook CI)
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-3.1 | `ScreenCaptureKitProvider` conform `CaptureProvider` | Compileert en voldoet aan protocol |
| TC-3.2 | `LocalPermissionManager` conform `PermissionManager` | Compileert en voldoet aan protocol |
| TC-3.3 | ESC tijdens gebiedsselectie | State terug naar idle, geen capture |
| TC-3.4 | CaptureState update na succesvolle capture | State is `.captured` met correcte dimensies |
| TC-3.5 | Capture zonder Screen Recording permissie | Error state met duidelijke melding |
| TC-3.6 | AnalysisOverlayView met lege array | Rendert zonder crash, geen zichtbare annotaties |
| TC-3.7 | AnalysisOverlayView met test-items | Rendert bounding boxes op correcte posities |

### Testcases — Integration (alleen lokaal, vereist screen recording permissie)
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-3.10 | `availableWindows()` retourneert lijst | Niet-lege lijst met WindowInfo objecten die naam en app bevatten |
| TC-3.11 | Capture referentie-venster met bekende tekst, verifieer via OCR | CGImage met correcte afmetingen, Vision OCR herkent "CortexVision Test Content ABC123" met >80% match |
| TC-3.12 | Capture gebied van 500x300px, verifieer dimensies en inhoud | CGImage is exact 500x300, bevat herkenbare pixels (niet volledig zwart/wit) |
| TC-3.13 | Capture referentie-venster met bekende figuur, verifieer figuurdetectie | Rectangle detection vindt minimaal 1 figuur (het blauwe vierkant) |

### Teststrategie
- **CI:** Unit tests (TC-3.1 t/m TC-3.7) draaien altijd. Integration tests worden overgeslagen via `.enabled(if: isScreenRecordingAvailable)`. `PRODUCTIE`
- **Lokaal:** Alle tests draaien. Integration tests openen een **referentie-NSWindow** met vooraf bepaalde tekst ("CortexVision Test Content ABC123") en een blauw vierkant als test-figuur. De test captured dit venster en verifieert output via Vision OCR en rectangle detection. `PRODUCTIE`
- **Geen afhankelijkheid van externe apps** — referentie-venster wordt door de test zelf aangemaakt

---

## UC-4: OCR Pipeline

**Status:** `DONE`

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

**Status:** `DONE`

### Beschrijving
Als gebruiker wil ik dat figuren (grafieken, diagrammen, afbeeldingen, tabellen, foto's) automatisch worden herkend — ongeacht hun vorm — en als losse bestanden beschikbaar worden gesteld, zodat ik visuele elementen apart kan hergebruiken.

### Actors
- Eindgebruiker
- Systeem (automatisch, parallel aan OCR)

### Precondities
- Er is een capture beschikbaar
- OCR is uitgevoerd (UC-4) zodat tekstregio's bekend zijn

### Flow
1. Na capture start figuurdetectie parallel aan OCR
2. Systeem combineert twee detectiemethoden:
   a. **Saliency detectie** (VNGenerateAttentionBasedSaliencyImageRequest) vindt visueel opvallende regio's
   b. **Tekst-exclusie** via OCR bounding boxes: regio's die overlappen met tekst worden uitgefilterd
3. Overblijvende opvallende regio's worden als figuur geïdentificeerd
4. Overlappende detecties worden samengevoegd (>50% overlap → merge)
5. Per figuur wordt een bounding box bepaald en de figuur uitgesneden als CGImage
6. In het preview paneel worden figuren met een groen kader gemarkeerd
7. Gebruiker kan figuren aan/uit selecteren voor export
8. Elke figuur krijgt een genummerd label (Figure 1, Figure 2, ...)

### Detectie-aanpak
| Methode | Doel |
|---------|------|
| VNGenerateAttentionBasedSaliencyImageRequest | Vindt visueel opvallende regio's (ongeacht vorm: rechthoeken, cirkels, onregelmatig) |
| OCR bounding boxes (uit UC-4) | Filtert tekstregio's uit, zodat alleen non-tekst regio's als figuur worden geïdentificeerd |
| Overlap merging | Samengevoegde regio's die >50% overlappen tot één figuur |
| Minimum-grootte filter | Regio's kleiner dan 3% van de afbeelding worden genegeerd (ruis) |

### Postcondities
- Figuren zijn als losse CGImage objecten beschikbaar
- Elke figuur heeft een bounding box, volgnummer en selected-state
- Tekstregio's zijn uitgesloten van figuurdetectie
- Preview toont groene overlays voor gedetecteerde figuren

### Classificatie per onderdeel
| Onderdeel | Classificatie | Toelichting |
|-----------|--------------|-------------|
| FigureDetector | `PRODUCTIE` | Vision saliency + tekst-exclusie via OCR bounds |
| DetectedFigure model | `PRODUCTIE` | Bounds, label, extracted CGImage, selected state |
| Figuur uitsnijden | `PRODUCTIE` | CGImage.cropping(to:) met pixel-conversie |
| Overlap merging | `PRODUCTIE` | IoU-berekening, samenvoeging bij >50% overlap |
| Preview overlay (groen) | `PRODUCTIE` | Bestaand AnalysisOverlay met `.figure` kind |
| Figuur selectie UI | `PRODUCTIE` | Toggle per figuur in Results panel |
| Export van figuren | `SCAFFOLD` | Export-logica komt in UC-7; hier alleen extracted CGImages. Vervangplan: UC-7 implementeert PNG-export via ExportDestination protocol |

### Acceptatiecriteria
- [ ] Figuren worden gedetecteerd ongeacht vorm (rechthoek, cirkel, onregelmatig)
- [ ] Tekstregio's worden niet als figuur aangemerkt
- [ ] Gedetecteerde figuren worden visueel gemarkeerd in preview (groene overlays)
- [ ] Figuren worden uitgesneden als losse CGImage objecten
- [ ] Gebruiker kan individuele figuren deselecteren
- [ ] Figuren worden gelabeld met volgnummer (Figure 1, Figure 2, ...)
- [ ] Overlappende detecties worden samengevoegd
- [ ] Regio's kleiner dan 3% van de afbeelding worden genegeerd
- [ ] Figuurdetectie draait asynchroon (UI blokkeert niet)

### Testcases — Unit (draaien overal, ook CI)

**Detectie basis**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.1a | DetectedFigure model heeft unieke ID's | Twee figuren hebben verschillende id's |
| TC-5.1b | DetectedFigure default selected state is true | Nieuw aangemaakt figuur is geselecteerd |
| TC-5.1c | DetectedFigure label volgt volgnummer | Figuur aangemaakt met index 0 → "Figure 1", index 2 → "Figure 3" |
| TC-5.1d | DetectedFigure bounds zijn genormaliseerd (0..1) | Bounds vallen binnen 0..1 range |

**Overlap merging**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.2a | Twee niet-overlappende regio's | Beide blijven behouden als aparte figuren |
| TC-5.2b | Twee regio's met >50% overlap | Samengevoegd tot één figuur met merged bounds |
| TC-5.2c | Twee regio's met exact 50% overlap | Niet samengevoegd (drempelwaarde is >50%) |
| TC-5.2d | Drie regio's waarvan 2 overlappen | 2 merged + 1 apart = 2 figuren |
| TC-5.2e | Volledig overlappende regio's (identieke bounds) | Samengevoegd tot één figuur |
| TC-5.2f | Lege lijst regio's | Leeg resultaat, geen crash |

**Tekst-exclusie**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.3a | Saliency-regio overlapt volledig met tekst-bounds | Regio wordt uitgefilterd |
| TC-5.3b | Saliency-regio overlapt gedeeltelijk met tekst | Regio blijft behouden (niet volledig tekst) |
| TC-5.3c | Saliency-regio zonder overlap met tekst | Regio blijft behouden als figuur |
| TC-5.3d | Geen tekst-bounds aanwezig (leeg OCR) | Alle saliency-regio's worden figuren |

**Minimum-grootte filter**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.4a | Regio kleiner dan 3% van afbeelding | Wordt genegeerd |
| TC-5.4b | Regio exact 3% van afbeelding | Wordt behouden |
| TC-5.4c | Regio groter dan 3% van afbeelding | Wordt behouden |
| TC-5.4d | Zeer grote regio (>80% van afbeelding) | Wordt behouden |

**Figuur uitsnijden**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.5a | Crop van genormaliseerde bounds naar pixel rect | Correcte pixel-coördinaten (x * width, y * height) |
| TC-5.5b | Crop bij beeldrand (bounds raken edge) | Geclampt binnen afbeelding, geen crash |
| TC-5.5c | Crop levert CGImage met juiste dimensies | Breedte en hoogte komen overeen met bounds * image size |

**Selectie-state**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.6a | Figuur deselecteren | selected wordt false |
| TC-5.6b | Figuur herselecteren | selected wordt weer true |
| TC-5.6c | Alleen geselecteerde figuren opvragen | Filter retourneert subset |

### Testcases — Integration (alleen lokaal, vereist screen recording permissie)

**Detectie met referentievensters**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.7a | Venster met 1 blauw vierkant en tekst | 1 figuur gedetecteerd, tekst niet als figuur |
| TC-5.7b | Venster met 3 gekleurde blokken naast elkaar | 3 aparte figuren gedetecteerd |
| TC-5.7c | Venster met alleen tekst (geen figuren) | 0 figuren gedetecteerd |
| TC-5.7d | Venster met rood cirkel-element | Figuur gedetecteerd ondanks niet-rechthoekige vorm |
| TC-5.7e | Venster met figuur boven tekst | Figuur gedetecteerd, tekst apart herkend |
| TC-5.7f | Venster met figuur tussen twee alinea's | Figuur gedetecteerd, beide alinea's als tekst |
| TC-5.7g | Venster met meerdere figuren van verschillende grootte | Alle figuren gedetecteerd met correcte relatieve grootte |
| TC-5.7h | Leeg wit venster | 0 figuren gedetecteerd, geen crash |

**Extractie verificatie**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.8a | Uitgesneden figuur heeft verwachte kleur | Pixel sampling bevestigt kleur van de figuur |
| TC-5.8b | Uitgesneden figuur heeft juiste aspect ratio | Breedte/hoogte ratio komt overeen met originele bounds |

**Overlay integratie**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5.9a | Figuur-overlays verschijnen als .figure kind | AnalysisOverlay items hebben kind == .figure |
| TC-5.9b | Figuur-overlays en tekst-overlays bestaan naast elkaar | Beide typen aanwezig in overlay array |
| TC-5.9c | figureCount in CaptureState.analyzed is correct | Aantal komt overeen met gedetecteerde figuren |

---

## UC-5a: Interactieve Figuur & Tekst Overlay Correctie

**Status:** `IN PROGRESS`

### Beschrijving
Als gebruiker wil ik de automatisch gedetecteerde figuur- en tekstvlakken (overlays) handmatig kunnen verplaatsen, vergroten/verkleinen en verwijderen in de preview, zodat ik de detectie kan corrigeren wanneer deze niet perfect is. Daarnaast wil ik nieuwe figuurvlakken handmatig kunnen toevoegen. Tekst-overlays worden gegroepeerd tot logische blokken in plaats van per regel getoond.

### Actors
- Eindgebruiker

### Precondities
- Er is een capture met analyse-resultaten beschikbaar (UC-4 + UC-5)
- Overlays zijn zichtbaar in de preview

### Flow
1. Na figuurdetectie (UC-5) en OCR (UC-4) worden overlays getoond op de preview
2. Tekst-overlays worden gegroepeerd: nabijgelegen OCR-regels worden samengevoegd tot logische blokken
3. Gebruiker kan een overlay selecteren door erop te klikken
4. Geselecteerde overlay toont resize-handgrepen (hoeken + zijden)
5. Gebruiker kan de overlay slepen om te verplaatsen
6. Gebruiker kan handgrepen slepen om te resizen
7. Gebruiker kan een overlay verwijderen (Delete-toets of context menu)
8. Gebruiker kan individuele tekstblokken uitsluiten via toggle (niet meenemen in export)
9. Gebruiker kan een nieuw figuurvlak tekenen (klik + sleep op lege plek)
10. Wijzigingen worden direct gereflecteerd in de geëxtraheerde figuren
11. Bij re-export worden de gecorrigeerde bounds en uitsluitingen gebruikt

### GUI-aanpassingen
- Preview paneel is het primaire werkgebied en krijgt het meeste schermruimte
- Splitview met instelbare verhouding (preview vs results), default ~65/35 ten gunste van preview
- Results panel compacter: toont samenvatting, figuur-lijst, en bewerkingsopties
- Zoom/pan op de preview (scroll-zoom + drag-to-pan) voor nauwkeurige positionering van overlays
- Bij het inzoomen moeten overlays meeschalen en positioneerbaar blijven

### Classificatie per onderdeel
| Onderdeel | Classificatie | Toelichting |
|-----------|--------------|-------------|
| Tekst-overlay grouping | `PRODUCTIE` | Merge nabijgelegen OCR-blokken tot logische tekstblokken via proximity-threshold |
| Tekst-overlay interactie | `PRODUCTIE` | Zelfde selectie/drag/resize als figuur-overlays |
| Tekstblok uitsluiting | `PRODUCTIE` | Toggle per tekstblok om uit te sluiten van export. Visueel doorgestreept/gedimd |
| Draggable overlay selectie | `PRODUCTIE` | Klik-selectie met visuele feedback |
| Resize handgrepen | `PRODUCTIE` | 8-punt resize (4 hoeken + 4 zijden) |
| Verplaatsing (drag) | `PRODUCTIE` | Overlay meebeweegt met muis |
| Verwijderen overlay | `PRODUCTIE` | Delete-toets + context menu |
| Nieuw vlak tekenen | `PRODUCTIE` | Klik+sleep op lege plek, wordt nieuwe DetectedFigure |
| Live figuur re-extractie | `PRODUCTIE` | Na verplaatsen/resizen wordt CGImage opnieuw uitgesneden |
| Splitview herverdeling | `PRODUCTIE` | Preview ~65%, results ~35%. Preview is primair werkgebied |
| Preview zoom/pan | `PRODUCTIE` | Scroll-zoom + drag-to-pan, overlays schalen mee |

### Acceptatiecriteria
- [x] Tekst-overlays zijn gegroepeerd tot logische blokken (niet per regel)
- [x] Klik op overlay selecteert deze (visuele highlight)
- [x] Geselecteerde overlay toont resize-handgrepen
- [x] Overlay kan worden versleept naar andere positie
- [x] Overlay kan worden vergroot/verkleind via handgrepen
- [x] Delete-toets verwijdert geselecteerde overlay
- [x] Klik+sleep op lege plek tekent nieuw figuurvlak
- [ ] Na verplaatsen/resizen wordt de figuur opnieuw uitgesneden
- [ ] Individuele tekstblokken kunnen worden uitgesloten via toggle
- [ ] Preview paneel is primair werkgebied (~65% van de breedte)
- [ ] Splitview verhouding is aanpasbaar door gebruiker
- [ ] Preview ondersteunt zoom en pan voor nauwkeurig werk
- [ ] Bij zoom schalen overlays mee en blijven positioneerbaar

### Testcases — Unit (draaien overal, ook CI)

**Tekst-overlay grouping**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5a.8 | 10 OCR-regels met kleine gaps | Gegroepeerd tot 1-3 tekstblokken, niet 10 overlays |
| TC-5a.9 | Twee gescheiden tekstkolommen | Twee aparte tekst-overlays |
| TC-5a.10 | Tekst-overlay verplaatsen | Bounds verschuift, tekst wordt hergeassocieerd |

**Overlay interactie**
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-5a.1 | Selecteer overlay via klik | isSelected state wordt true |
| TC-5a.2 | Verplaats overlay 50px rechts | bounds.x verschuift correct in genormaliseerde coords |
| TC-5a.3 | Resize overlay via hoekhandgreep | bounds.width en height passen aan |
| TC-5a.4 | Verwijder geselecteerde overlay | overlays array verliest 1 element |
| TC-5a.5 | Teken nieuw vlak | overlays array krijgt 1 nieuw element |
| TC-5a.6 | Verplaats overlay buiten beeldrand | Bounds worden geclampt binnen 0..1 |
| TC-5a.7 | Re-extractie na resize | Nieuwe CGImage heeft aangepaste dimensies |

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

## UC-4a: OCR Formatted Output

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik kunnen kiezen tussen platte tekst en geformatteerde tekst bij OCR-resultaten, zodat de originele documentstructuur (alinea-spacing, kolom-indeling, inspringing) behouden blijft wanneer dat gewenst is.

### Actors
- Eindgebruiker

### Precondities
- OCR pipeline is actief (UC-4)
- Er is een capture met herkende tekst beschikbaar

### Flow
1. Na OCR-verwerking is tekst beschikbaar in twee formaten
2. **Plain** (standaard): tekst in leesvolgorde, gescheiden door enkele newlines
3. **Formatted**: tekst met behoud van structuur:
   - Grotere Y-gap tussen blokken → dubbele newline (alinea-scheiding)
   - Kolommen als aparte secties (niet dooreen gemengd)
   - Relatieve inspringing behouden via spaces
4. Gebruiker kan in het Results panel schakelen tussen plain en formatted
5. Copy-functie kopieert het actieve formaat

### Postcondities
- Beide formaten zijn beschikbaar op `OCRResult`
- Results panel heeft een toggle voor plain/formatted
- Copy-knop respecteert de gekozen weergave

### Acceptatiecriteria
- [ ] `OCRResult.fullText` levert platte tekst (bestaand gedrag)
- [ ] `OCRResult.formattedText` levert geformatteerde tekst met alinea-spacing
- [ ] Kolom-layout wordt als aparte secties weergegeven in formatted mode
- [ ] Toggle in Results panel schakelt tussen plain en formatted
- [ ] Copy-knop kopieert het actief weergegeven formaat
- [ ] Formatted output van een enkel-koloms document heeft correcte alinea-scheiding

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-4a.1 | Formatted output van tekst met 3 alinea's | Dubbele newlines tussen alinea's |
| TC-4a.2 | Formatted output van twee-koloms tekst | Kolommen als aparte secties, niet doorgelezen |
| TC-4a.3 | Formatted output van enkel-koloms tekst | Zelfde als plain, met alinea-spacing |
| TC-4a.4 | Toggle tussen plain en formatted in UI | Weergave wisselt correct |
| TC-4a.5 | Copy in formatted mode | Klembord bevat geformatteerde tekst |

---

## UC-4b: Tekstblok Selectie in Preview

**Status:** `DRAFT`

### Beschrijving
Als gebruiker wil ik individuele tekstblokken kunnen selecteren in het preview paneel door erop te klikken, zodat ik gericht specifieke tekst kan kopiëren of bekijken zonder het volledige OCR-resultaat te doorlopen.

### Actors
- Eindgebruiker

### Precondities
- Er is een capture met OCR-resultaten beschikbaar (UC-4)
- Overlay-blokken zijn zichtbaar op de preview

### Flow
1. Gebruiker ziet overlay-blokken op de preview na OCR
2. Gebruiker klikt op een tekstblok in de preview
3. Het geselecteerde blok wordt visueel gehighlight (bijv. blauwe rand)
4. De bijbehorende tekst wordt getoond/gehighlight in het Results panel
5. Gebruiker kan meerdere blokken selecteren (Cmd+klik)
6. "Copy Selection" knop kopieert alleen de geselecteerde tekst
7. Klikken op de achtergrond deselecteert alle blokken

### Postcondities
- Geselecteerde blokken zijn visueel onderscheiden
- Selectie is gesynchroniseerd tussen preview en Results panel
- Geselecteerde tekst kan apart worden gekopieerd

### Acceptatiecriteria
- [ ] Klik op overlay-blok selecteert het blok
- [ ] Geselecteerd blok heeft visueel onderscheidende stijl
- [ ] Corresponderende tekst in Results panel wordt gehighlight
- [ ] Cmd+klik voegt toe aan selectie
- [ ] Klik op achtergrond deselecteert alles
- [ ] "Copy Selection" kopieert alleen geselecteerde blokken
- [ ] Selectie werkt met zowel venster- als gebiedscapture

### Testcases
| ID | Beschrijving | Verwacht resultaat |
|----|-------------|-------------------|
| TC-4b.1 | Klik op tekstblok in preview | Blok wordt geselecteerd, tekst gehighlight in panel |
| TC-4b.2 | Cmd+klik op tweede blok | Beide blokken geselecteerd |
| TC-4b.3 | Klik op achtergrond | Alle selectie verwijderd |
| TC-4b.4 | Copy Selection met 2 blokken geselecteerd | Klembord bevat tekst van alleen die 2 blokken |
| TC-4b.5 | Selectie na nieuwe capture | Vorige selectie is gewist |

---

## Implementatievolgorde

```
UC-0 [DONE] ──► UC-1 [DONE] ──► UC-2 [DONE] ──► UC-3 [DONE]
                                                       │
                                                       ▼
                                                  UC-4 [DONE]
                                                       │
                                              ┌────────┼────────┐
                                              ▼        ▼        ▼
                                        UC-4a [DRAFT] UC-4b [DRAFT] UC-5 [DONE]
                                                                       │
                                                                       ▼
                                                              UC-5a [APPROVED] ◄── NEXT
                                                                       │
                                              ┌────────────────────────┘
                                              ▼
                                 UC-6 [DRAFT] ──► UC-7 [DRAFT]
                                                       │
                                                       ▼
                                              UC-8 [BACKLOG] (App Store)
```

UC-5a (interactieve overlay correctie) is de eerstvolgende prioriteit.
UC-4a en UC-4b zijn afhankelijk van UC-4, kunnen parallel met UC-5a.
UC-6 en UC-7 kunnen deels parallel worden ontwikkeld na UC-5a.

---

## UC-8: App Store Distributie (TOEKOMSTIG)

**Status:** `BACKLOG`

> **Dit is een toekomstige use case.** Wordt pas opgepakt nadat UC-1 t/m UC-7 zijn
> afgerond en de lokale versie compleet en stabiel is. Zie `technical-debt.md` in
> memory voor het volledige overzicht van benodigde aanpassingen.

### Beschrijving
Als ontwikkelaar wil ik de applicatie via de Mac App Store kunnen distribueren zodat gebruikers de app eenvoudig kunnen vinden, installeren en updaten.

### Vereiste aanpassingen
1. **App Sandbox activeren** (TD-1) — entitlements configureren
2. **Scrolling capture herontwerpen** (TD-2) — Accessibility API vervangen door ScreenCaptureKit SCStream + user-gestuurd scrollen. `AccessibilityScrollCapture` → `StreamScrollCapture` achter bestaand `ScrollCaptureProvider` protocol
3. **Export sandboxen** (TD-1) — `FileSystemExport` → `SandboxedExport` via NSSavePanel, achter bestaand `ExportDestination` protocol
4. **Minimum deployment target verhogen** naar macOS 15 (TD-3)
5. **Privacy descriptions toevoegen** aan Info.plist (TD-4)
6. **Code signing & notarization** configureren (TD-5)

### Ontkoppelingsprotocollen (ingebouwd vanaf UC-2)
| Protocol | Lokale impl | App Store impl |
|----------|------------|----------------|
| `CaptureProvider` | `ScreenCaptureKitProvider` | Zelfde |
| `ScrollCaptureProvider` | `AccessibilityScrollCapture` | `StreamScrollCapture` |
| `ExportDestination` | `FileSystemExport` | `SandboxedExport` |
| `PermissionManager` | `LocalPermissionManager` | `SandboxPermissionManager` |

---

## UC-9: Intelligente Tekst Structurering (NICE TO HAVE)

**Status:** `BACKLOG`

> **Dit is een toekomstige nice-to-have.** Wordt pas overwogen nadat de kern-pipeline
> (UC-1 t/m UC-7) volledig is en er behoefte is aan geavanceerdere tekst-analyse.

### Beschrijving
Als gebruiker wil ik dat de herkende tekst (uit UC-4) optioneel kan worden verrijkt met structuurherkenning — zoals het identificeren van koppen, tabellen, contactgegevens, datums en andere entiteiten — zodat de export (UC-7) rijkere en beter bruikbare output levert.

### Aanleiding
Google's open-source [LangExtract](https://github.com/google/langextract) library biedt LLM-powered extractie van gestructureerde data uit ongestructureerde tekst. Dit is geen OCR-vervanging maar een **post-OCR verrijkingsstap**.

### Mogelijke aanpak
1. OCR pipeline (UC-4) levert platte tekst op (bestaand, on-device)
2. Optionele verrijkingsstap stuurt tekst naar een LLM (lokaal of cloud) voor structuurherkenning
3. LLM identificeert: koppen, tabellen, lijsten, contactgegevens, datums, bedragen
4. Gestructureerde output wordt gebruikt in export (UC-7) voor rijkere Markdown

### Technologie-opties
| Optie | Voordeel | Nadeel |
|-------|----------|--------|
| Google LangExtract (Python, Gemini) | Productie-rijp, source grounding | Cloud-afhankelijk, Python (niet Swift native) |
| Lokaal LLM (MLX, llama.cpp) | 100% on-device, geen API key | Grotere app, langzamere verwerking |
| Apple Foundation Models (macOS 26+) | Native Swift, on-device | Alleen macOS 26+, beperkte capabilities |

### Randvoorwaarden
- **Optioneel** — kernfunctionaliteit (OCR + figuurdetectie) blijft 100% on-device
- **Opt-in** — gebruiker kiest expliciet voor verrijking (privacy)
- **Graceful degradation** — als verrijking niet beschikbaar is, valt terug op plain tekst
- **Geen blokkering van export** — verrijking mag export niet vertragen bij afwezigheid

### Classificatie
| Onderdeel | Classificatie |
|-----------|--------------|
| Gehele UC-9 | `NICE TO HAVE` — pas na UC-1 t/m UC-7 |

---

## Bevindingen

### BUG-1: Figuur links afgesneden in UI + overlay-tekst trimming

**Status:** `FIXED`
**Gevonden:** 2026-03-12
**Opgelost:** 2026-03-14
**Component:** FigureDetector / OverlayTextAnalyzer

**Beschrijving:**
Meerdere gerelateerde problemen bij figuurdetectie op nieuwspagina's:
1. Figuur links afgesneden in UI (DenHaagDoet hero banner)
2. Foto gesplitst in meerdere figuren door subject promotion (RC-1)
3. Foto afgeknipt bij overlay-tekst op de foto (RC-2)
4. Headline tekst op fotorand veroorzaakt onterechte trimming

**Oplossing:**
- `OverlayTextAnalyzer` — lokale patch-analyse per tekstblok met 3 signalen (continuïteit, coherentie, randproximiteit)
- `mergeHorizontallyAdjacent()` — merget figuren in dezelfde rij
- Post-crop validatie in PASS4 — voorkomt autoCrop cascade
- Classificaties: overlay, edgeOverlay, pageText, uncertain
- Conservatieve trim-policy: alleen pageText wordt getrimd

**Resultaten:**
- Bovenfoto bounds height: 0.209 → 0.263
- Onderfoto bounds height: 0.210 → 0.269
- 214 tests, 214 passed, 87.8% coverage
