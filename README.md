# Sluiter

Snel apps, vensters, browsertabbladen en achtergrondprocessen sluiten met het toetsenbord. Gemaakt voor momenten waarop je Mac traag is.

> **English:** Sluiter ("closer") is a tiny native macOS app to quickly close apps, windows, browser tabs and background processes from the keyboard. Press ⌃⌥Space, scroll with ↑↓, hit Space to close. Shows memory and CPU per app, flags apps that hang, and keeps your pinned apps safe. Swift + AppKit, no dependencies. The UI is in Dutch.

## Installeren
Vereist macOS 13 of nieuwer en de Xcode Command Line Tools (`xcode-select --install`).
```bash
git clone https://github.com/amvdkallen/sluiter.git
cd sluiter
./build.sh --install
```
Sluiter staat daarna in Programma's. Hij is niet door Apple ondertekend; je bouwt hem zelf, dus macOS blokkeert hem niet.

## Privacy
Sluiter werkt volledig lokaal: geen internet, geen tracking, geen account. Toestemmingen die hij vraagt: Toegankelijkheid (vensters), Automatisering (browsertabbladen) en Meldingen.

## Openen
- **⌃⌥Spatie** overal (in te stellen via ⌘,)
- Dock, Launchpad, Spotlight of het ☒-icoon in de menubalk

## Tabbladen
| | |
|---|---|
| **Apps** | met CPU, geheugen (incl. helpers), wanneer laatst gebruikt, en "reageert niet" |
| **Vensters** | gegroepeerd per app (vereist Toegankelijkheid) |
| **Tabbladen** | Chrome, Brave, Edge, Vivaldi, Chromium, Safari (vraagt Automatisering-toestemming per browser) |
| **Processen** | achtergronddiensten van jou (Docker, sync-apps, scripts). macOS-systeemprocessen worden nooit getoond. |

Bovenin: systeembalk met geheugen, geheugendruk, CPU en swap, plus advies als je Mac geheugentekort heeft.

## Toetsen
| Toets | Actie |
|---|---|
| ↑ ↓ / PgUp PgDn / Home End | kiezen |
| typen / ⌫ / esc | filteren / letter weg / filter wissen of verbergen |
| **spatie** of **⏎** | sluiten (alle gemarkeerde, of de geselecteerde) |
| ⇧⏎ | geforceerd stoppen |
| ⇧↑ ⇧↓, ⌘-klik, ⌘A | markeren (meerdere tegelijk) |
| → of dubbelklik | naar app / venster / tabblad springen |
| ⌘⏎ | alles in de lijst sluiten (2× drukken, beschermde apps blijven) |
| ⌘P | app beschermen 📌 (nooit meesluiten) |
| ⌘⌫ | **Opruimen**: alle apps sluiten behalve beschermde (2× drukken) |
| ⌘S | sorteren: geheugen → CPU → langst ongebruikt → naam |
| ⇥ / ⌘1–4 | wisselen tussen Apps, Vensters, Tabbladen, Processen |
| ⌘R | verversen |
| ⌘, | instellingen |

## Werksets
Knop **Werksets** (of menu Werksets): sla de apps op die nu open staan, en zet ze later terug met **Openen** of **Overschakelen** (dan worden andere apps gesloten).

## Waarschuwingen
Op de achtergrond (elke 30 s) krijg je een melding met de knop **Sluiten** als een app meer dan 3 GB gebruikt (instelbaar), blijft hangen, of als je Mac geheugentekort krijgt.

## Meehelpen
Verbeteringen zijn welkom! Lees [CONTRIBUTING.md](CONTRIBUTING.md) voor hoe de code in elkaar zit, en open een issue of pull request. *Contributions welcome, see CONTRIBUTING.md.*

## Bouwen
```bash
./build.sh --install
```
Na elke nieuwe build moet je Toegankelijkheid opnieuw aanzetten (Systeeminstellingen → Privacy → Toegankelijkheid: Sluiter verwijderen met − en opnieuw toevoegen).
