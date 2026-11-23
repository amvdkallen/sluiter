# Sluiter — voortgang uitbreidingen

Werkwijze: één functie per stap → `./build.sh --install` → git commit.
Bij onderbreking (usage limit): `git log --oneline` + deze lijst laten zien waar we zijn.

## Toetsontwerp (vast, niet meer wijzigen)
- Typen = filteren (blijft zo). Acties dus via ⌘-toetsen, knoppen en rechtermuisklik.
- ↑↓ kiezen · ⇧↑↓ markeren uitbreiden · ⌘-klik markeren · ⌘A alles markeren
- Spatie/⏎ sluit gemarkeerde items (of geselecteerde) · ⇧⏎ geforceerd
- ⌘P beschermen aan/uit · ⌘⌫ Opruimen (alles behalve beschermd, 2× bevestigen)
- ⇥ / ⌘1…4 wisselen tussen tabbladen (Apps, Vensters, Tabbladen, Processen)
- → spring naar venster/app · ⌘, Instellingen

## Status
- [x] 0. Code opgesplitst, git, voortgangsbestand
- [x] 1+2. Beschermde apps + Opruimen
- [x] 3. Meerdere selecteren
- [x] 4. CPU + "reageert niet"
- [x] 5. Instellingen: starten bij inloggen + eigen sneltoets
- [x] 6. Systeembalk (geheugen, geheugendruk, CPU)
- [ ] 7. Laatst gebruikt
- [ ] 8. Waarschuwingen (veel geheugen / hangt)
- [ ] 9. Browsertabbladen (Chrome, Safari)
- [ ] 10+11. Spring naar venster + vensters groeperen per app
- [ ] 12. Werksets opslaan/herstellen
- [ ] 13. Achtergrondprocessen

## Notities
- Na elke nieuwe build moet Toegankelijkheid opnieuw worden toegestaan (ad-hoc handtekening).
