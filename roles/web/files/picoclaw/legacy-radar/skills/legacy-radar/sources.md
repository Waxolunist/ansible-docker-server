# Legacy Radar sources

Edit this file to change what the radar looks for. The scripts in `scripts/`
carry their own keyword lists for the tender APIs.

## News queries (`sh scripts/gnews.sh '<query>'`)

- `Legacy Migration KI`
- `Mainframe Modernisierung`
- `COBOL Migration`
- `Altsystem Ablösung`
- `Application Modernization KI`
- `Host Ablösung Bank OR Versicherung OR Verwaltung`

## Job and freelance queries (`web_search`, range `m`)

Plain words, no `OR`: the search engine returns nothing for long `OR` chains.

Germany:
- `freelancermap Legacy Migration Projekt`
- `gulp COBOL Projekt`
- `Mainframe Migration Freelance Projekt`
- `stepstone Legacy Modernisierung`

Austria:
- `karriere.at Mainframe`
- `Legacy Migration Job Wien`

Switzerland:
- `jobs.ch Mainframe`
- `Legacy Migration Job Zürich`

All DACH:
- `COBOL Entwickler Migration`
- `KI-gestützte Migration Mainframe`
- `Natural Adabas Ablösung`
- `Host Ablösung Projekt`

## Below-threshold tender queries (`web_search`, range `m`)

- `service.bund.de Ausschreibung Ablösung Fachverfahren`
- `Ausschreibung Migration Altsystem Kommune`
- `auftrag.at Ausschreibung Software Ablösung`
- `Ausschreibung Mainframe Migration`

## Keywords for judging relevance

Legacy-Migration, Altsystemablösung, Ablösung Fachverfahren, Host-Ablösung,
Großrechner, Mainframe, z/OS, COBOL, PL/I, Natural, Adabas, RPG, AS/400, IBM i,
Oracle Forms, Delphi, VB6, PowerBuilder, Code-Transformation,
Reengineering, Rehosting, Replatforming, Refactoring, KI-gestützte Migration,
Application Modernization, Software AG.
