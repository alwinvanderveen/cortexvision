# CortexVision — Project Regels

## HARDE GATE 1: Use Case Akkoord

**DEZE REGEL IS NIET OPTIONEEL EN MAG NIET WORDEN OVERGESLAGEN.**

Voordat er code wordt geschreven voor een use case uit `BACKLOG.md`:

1. **PRESENTEER** de use case aan de gebruiker (beschrijving, flow, acceptatiecriteria, testcases)
2. **WACHT** op expliciet akkoord van de gebruiker
3. **PAS** de status in BACKLOG.md aan naar `APPROVED` na akkoord
4. **PAS** de status aan naar `IN PROGRESS` wanneer implementatie begint
5. **PAS** de status aan naar `DONE` wanneer alle acceptatiecriteria en tests groen zijn

Bij feedback van de gebruiker: werk de use case bij en presenteer opnieuw ter goedkeuring.

**Er mag GEEN implementatiecode worden geschreven zolang de status niet `APPROVED` is.**

## HARDE GATE 2: Production-Ready Classificatie

**DEZE REGEL IS NIET OPTIONEEL EN MAG NIET WORDEN OVERGESLAGEN.**

Bij het presenteren van een use case, aandachtspunt, architectuurkeuze of oplossingsrichting MOET elk onderdeel expliciet worden geclassificeerd als:

| Label | Betekenis | Regel |
|-------|-----------|-------|
| `PRODUCTIE` | Structurele, productie-rijpe oplossing | Mag worden geïmplementeerd |
| `SCAFFOLD` | Tijdelijke constructie die later wordt vervangen | **Moet expliciet worden benoemd met reden en vervangplan** |

### Regels
- **Standaard is `PRODUCTIE`.** Elke keuze moet productie-rijp zijn tenzij er een dwingende reden is om tijdelijk te scaffolden.
- **Geen mock-oplossingen.** Geen placeholder-implementaties, geen "dit vullen we later in", geen UI stubs die niets doen.
- **Scaffold mag alleen als:**
  1. De productie-oplossing afhangt van een use case die nog niet is geïmplementeerd
  2. Er een concreet vervangplan is met verwijzing naar de betreffende UC
  3. De gebruiker expliciet akkoord geeft op de scaffold
- **Bij elke review (use case, aandachtspunt, vraag, onduidelijkheid):** toon de classificatie `PRODUCTIE` of `SCAFFOLD` per onderdeel

## Werkwijze per use case

```
DRAFT ──[review]──► APPROVED ──[start dev]──► IN PROGRESS ──[tests groen]──► DONE
  ▲                                                │
  └────────────────[rejected/feedback]─────────────┘
```

## Overige regels

- Code in het Engels, UI labels in het Engels, comments in het Engels
- TDD: schrijf tests vóór implementatie
- Update memory bestanden bij elke milestone
- Update BACKLOG.md status bij elke statuswijziging
- Commit messages in het Engels
- Geen over-engineering, maar ook geen shortcuts — het juiste abstractieniveau voor productie
