# CortexVision — Project Regels

## HARDE GATE: Use Case Akkoord

**DEZE REGEL IS NIET OPTIONEEL EN MAG NIET WORDEN OVERGESLAGEN.**

Voordat er code wordt geschreven voor een use case uit `BACKLOG.md`:

1. **PRESENTEER** de use case aan de gebruiker (beschrijving, flow, acceptatiecriteria, testcases)
2. **WACHT** op expliciet akkoord van de gebruiker
3. **PAS** de status in BACKLOG.md aan naar `APPROVED` na akkoord
4. **PAS** de status aan naar `IN PROGRESS` wanneer implementatie begint
5. **PAS** de status aan naar `DONE` wanneer alle acceptatiecriteria en tests groen zijn

Bij feedback van de gebruiker: werk de use case bij en presenteer opnieuw ter goedkeuring.

**Er mag GEEN implementatiecode worden geschreven zolang de status niet `APPROVED` is.**

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
