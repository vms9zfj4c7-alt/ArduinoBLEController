# Arduino BLE & Wi-Fi Adaptive Controller (iOS SwiftUI + Arduino)

Application iPhone complète (**iOS 16+**, **SwiftUI**, **CoreBluetooth**, **Network**, architecture **MVVM**) accompagnée d'un sketch Arduino universel compatible **BLE** et **Wi-Fi TCP** qui s'adapte automatiquement à votre carte (**ESP32 / Nano ESP32**, **Arduino Uno R4 WiFi**, **Nano 33 BLE / IoT**, **MKR WiFi 1010**, **Uno / Nano / Mega + module HM-10**).

L'application inclut un **radar BLE interactif en temps réel** (distance estimée, orientation et balayage sonar), une **connexion Wi-Fi TCP directe et Bonjour mDNS** (`_arduinowifi._tcp`), une **manette de jeu portrait et paysage** (**Mode Essentiel** à 7 touches ou **Mode Complet** à 14 touches, curseurs analogiques `L2`/`R2`, console de logs pliable, arrêt d'urgence) et une **page d'assignation des boutons**.

---

## Contenu du projet

- `iOS_App/`
  - `App/ArduinoBLEControllerApp.swift` : point d'entrée `@main`
  - `Assets.xcassets/AppIcon.appiconset/` : icône native de l'application (`AppIcon-1024.png`)
  - `Models/` : `BLEProtocolConstants.swift`, `ArduinoBoardProfile.swift`, `BLEDevice.swift`, `BLELogEntry.swift`, `ControllerModels.swift`
  - `Services/` : `ArduinoConnectionHub.swift` (routeur BLE/Wi-Fi), `BLEManager.swift` (CoreBluetooth + HM-10/Nordic/FFF0/ISSC), `WiFiManager.swift` (TCP `Network.framework` + Bonjour `_arduinowifi._tcp`), `PS4ControllerManager.swift` (DualShock 4) et `ControllerStorageService.swift` (persistance `UserDefaults`)
  - `ViewModels/` : `ScanViewModel.swift`, `ControllerViewModel.swift`, `MappingViewModel.swift`
  - `Views/` : `MainTabView.swift`, `Scan/ScanView.swift`, `Scan/BLERadarView.swift`, `Controller/ControllerView.swift`, `Controller/DPadClusterView.swift`, `Controller/ActionButtonsClusterView.swift`, `Controller/LogConsoleView.swift`, `Mapping/MappingView.swift`, `Mapping/ButtonAssignmentEditorView.swift`, `Components/iPhoneUIHelpers.swift`
- `Arduino/ArduinoBLE_Adaptive_Controller/ArduinoBLE_Adaptive_Controller.ino` : sketch Arduino multi-cartes (BLE par défaut, ou Wi-Fi TCP avec `#define CONTROL_MODE_WIFI`)
- `project.yml` : configuration XcodeGen pour générer `ArduinoBLEController.xcodeproj` et `Config/Info.plist`
- `.github/workflows/build-ipa.yml` : workflow GitHub Actions (`macos-latest`) compilant automatiquement l'`.ipa` non signé et publiant la Release `latest`

---

## Partie 1 — Préparer et téléverser le sketch Arduino (.ino)

### 1. Ouvrir le sketch dans Arduino IDE
1. Ouvrez **Arduino IDE** (version 2.x recommandée).
2. Ouvrez `Arduino/ArduinoBLE_Adaptive_Controller/ArduinoBLE_Adaptive_Controller.ino`.

### 2. Mode Bluetooth Low Energy (par défaut)
Le sketch détecte automatiquement votre carte à la compilation :

| Carte utilisée | Bibliothèque à installer dans Arduino IDE | Brochage / Radio BLE |
| :--- | :--- | :--- |
| **ESP32 / Nano ESP32** | Aucune bibliothèque externe (incluse dans le cœur ESP32) | BLE intégré |
| **Arduino Uno R4 WiFi / Nano 33 BLE / IoT** | `ArduinoBLE` + `Servo` | BLE intégré |
| **Arduino Uno / Nano + HM-10 / AT-09** | `Servo` + `SoftwareSerial` (incluses de base) | `D2` -> TXD du HM-10, `D3` -> RXD du HM-10 *(pont diviseur 5V -> 3.3V conseillé)* |
| **Arduino Mega + HM-10 / AT-09** | `Servo` (incluse de base) | `Serial1` : `19 (RX1)` -> TXD, `18 (TX1)` -> RXD |

> **Compatibilité iPhone (BLE vs Bluetooth Classique 3.0) :** iOS bloque dans `CoreBluetooth` et `ExternalAccessory` (sans puce matérielle Apple MFi) les modules Bluetooth Classique uniquement tels que `Serial Bluetooth v3.01`, `HC-05`, `HC-06` ou `SPP-C`. Utilisez un module BLE (`HM-10`, `AT-09`, `HC-08`, `MLT-BT05`, `JDY-23`, `DX-BT24`) ou passez sur un **ESP32** / **Arduino Uno R4 WiFi** en BLE ou en Wi-Fi.

### 3. Activer le contrôle par Wi-Fi (`#define CONTROL_MODE_WIFI`)
Pour piloter une carte équipée Wi-Fi (**ESP32**, **Nano ESP32**, **Uno R4 WiFi**, **Nano 33 IoT**, **MKR WiFi 1010**) par Wi-Fi TCP au lieu du BLE :

1. Dans `ArduinoBLE_Adaptive_Controller.ino`, décommentez `#define CONTROL_MODE_WIFI`.
2. Choisissez votre mode :
   - **Point d'Accès (`#define WIFI_AP_MODE 1`, par défaut)** : l'Arduino crée le réseau Wi-Fi `ArduinoBLE-WiFi` (mot de passe `12345678`). Connectez l'iPhone à ce réseau, sélectionnez l'onglet **Wi-Fi (TCP)** dans l'application, puis touchez **Mode AP 192.168.4.1** et **Connecter** (`192.168.4.1`, port `8888`).
   - **Routeur Wi-Fi (`#define WIFI_AP_MODE 0`)** : renseignez `WIFI_SSID` et `WIFI_PASS` de votre box Wi-Fi. Sur ESP32, la carte est publiée automatiquement sur Bonjour (`_arduinowifi._tcp`) dans l'écran Wi-Fi de l'application (ou connectez-vous directement avec son adresse IP affichée dans le Moniteur Série à `115200 bauds`).

> **Capteur de température :** Par défaut (`#define TEMP_SENSOR_TYPE 0`), l'Arduino envoie une température de démonstration vers l'iPhone. Pour un vrai capteur analogique sur `A0`, réglez `TEMP_SENSOR_TYPE` sur `1` (LM35), `2` (TMP36) ou `3` (NTC 10k).

---

## Partie 2 — Compiler l'IPA automatiquement avec GitHub Actions (sans Mac)

Le workflow `.github/workflows/build-ipa.yml` génère le projet via `xcodegen generate` et compile l'application pour iOS 16.0+ sur `macos-latest` :

1. Chaque `push` sur `main` ou `master` (ou déclenchement manuel via **Actions > Run workflow**) produit l'artefact **`ArduinoBLEController-unsigned-ipa`** et met à jour la Release **`latest`**.
2. Téléchargez `ArduinoBLEController-unsigned.ipa` depuis la section **Releases** (`latest`) ou depuis les artefacts du workflow.
3. Installez ce `.ipa` sur votre iPhone avec **Sideloadly**, **AltStore** ou **SideStore**.

---

## Partie 3 — Compiler manuellement avec Xcode (sur Mac)

1. Exécutez `xcodegen generate` à la racine du dépôt (ou importez les dossiers `iOS_App/*` et `AppIcon` dans un projet Xcode SwiftUI iOS 16.0+).
2. Dans la Target **ArduinoBLEController > Info**, assurez-vous de la présence des clés déjà définies dans `project.yml` :
   - `NSBluetoothAlwaysUsageDescription`
   - `NSBluetoothPeripheralUsageDescription`
   - `NSLocalNetworkUsageDescription`
   - `NSBonjourServices` (`_arduinowifi._tcp`)
   - `GCSupportedGameControllers` (`ExtendedGamepad`)
3. Connectez un **iPhone réel** (CoreBluetooth et le réseau local physique nécessitent un appareil réel), activez le **Mode développeur**, puis lancez avec **Cmd + R**.

---

## Protocole BLE & Wi-Fi (référence rapide)

- **UUID Service BLE personnalisé** : `4fafca01-1fb5-459e-8fcc-c5c9c331914b`
- **UUID RX (iOS → Arduino)** : `beb5483e-36e1-4688-b7f5-ea07361b26a8`
- **UUID TX (Arduino → iOS)** : `beb5483f-36e1-4688-b7f5-ea07361b26a8`
- **Services BLE série compatibles** : `FFE0`/`FFE1` (HM-10), `6E400001-...` (Nordic UART), `FFF0`, `49535343-...` (ISSC)
- **Wi-Fi TCP / Bonjour** : port `8888` par défaut, service mDNS `_arduinowifi._tcp`

| Commande envoyée | Action sur l'Arduino |
| :--- | :--- |
| `I?` | Renvoie les capacités de la carte (`INFO:...`) |
| `T?` | Renvoie la télémétrie compacte (`DATA:T=...;S=...`) |
| `D:13:1` / `D:13:0` | Met la broche 13 à `HIGH` ou `LOW` |
| `P:5:200` | Applique une sortie PWM `200` (0–255) sur la broche 5 |
| `V:9:90` | Positionne le servomoteur sur la broche 9 à `90` degrés (0–180) |
| `M:5D1,6D0,10D1,11D0` | Lot atomique multi-broches en 1 seul paquet (Digital/PWM/Servo) |
| `R:7` | Lit l'état logique de la broche 7 |
| `X` | Arrêt d'urgence : coupe toutes les sorties actives |
