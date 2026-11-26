/// Version dieser Scrivi-Ausgabe, z. B. „v0.1.42“ – dieselbe Nummer wie beim
/// Download auf GitHub. Wird beim Bauen gesetzt (`--dart-define=SCRIVI_VERSION`).
const scriviVersion = String.fromEnvironment('SCRIVI_VERSION', defaultValue: 'Testversion');
