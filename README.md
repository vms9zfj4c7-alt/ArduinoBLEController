# Arduino BLE Adaptive Controller (iOS SwiftUI + Arduino)

Application iPhone complète (**iOS 16+**, **SwiftUI**, **CoreBluetooth**, architecture **MVVM**) accompagnée d'un sketch Arduino universel qui s'adapte automatiquement à votre carte (**ESP32**, **Arduino Uno R4 WiFi**, **Nano 33 BLE / IoT**, **Uno / Nano / Mega + module HM-10**).

L'application inclut un **scanner BLE** (nom + RSSI), une **manette de jeu réactive** (croix directionnelle, boutons A/B/X/Y, gâchettes L1/R1, curseurs analogiques L2/R2, console de logs pliable) et une **page dédiée d'assignation des boutons style manette**.

---

## Contenu de l'archive

- `iOS_App/`
  - `App/ArduinoBLEControllerApp.swift` : point d'entrée `@main`
  - `Models/` : constantes UUID/protocole, profils de cartes Arduino, modèles manette & logs
  - `Services/` : `BLEManager.swift` (CoreBluetooth), `PS4ControllerManager.swift` (GameController / DualShock 4) et `ControllerStorageService.swift` (persistance `UserDefaults`)
  - `ViewModels/` : `ScanViewModel.swift`, `ControllerViewModel.swift`, `MappingViewModel.swift`
  - `Views/` : `MainTabView.swift`, `ScanView.swift`, `ControllerView.swift`, `DPadClusterView.swift`, `ActionButtonsClusterView.swift`, `LogConsoleView.swift`, `MappingView.swift`, `ButtonAssignmentEditorView.swift`
- `Arduino/ArduinoBLE_Adaptive_Controller/ArduinoBLE_Adaptive_Controller.ino` : sketch Arduino multi-cartes commenté en français
- `project.yml` : configuration XcodeGen pour générer le `.xcodeproj` et `Info.plist` sans Mac
- `.github/workflows/build-ipa.yml` : workflow GitHub Actions (`macos-latest`) compilant automatiquement l'`.ipa` non signé

---

## Partie 1 — Préparer et téléverser le sketch Arduino (.ino)

### 1. Ouvrir le sketch dans Arduino IDE
1. Ouvrez **Arduino IDE** (version 2.x recommandée).
2. Ouvrez le fichier `Arduino/ArduinoBLE_Adaptive_Controller/ArduinoBLE_Adaptive_Controller.ino` (il se trouve déjà dans un dossier du même nom, requis par Arduino IDE).

### 2. Bibliothèques requises selon votre carte
Le sketch détecte automatiquement votre carte à la compilation :

| Carte utilisée | Bibliothèque à installer dans Arduino IDE | Brochage BLE |
| :--- | :--- | :--- |
| **ESP32 / Nano ESP32** | Aucune bibliothèque externe (incluse dans le cœur ESP32) | BLE intégré |
| **Arduino Uno R4 WiFi / Nano 33 BLE / IoT** | `ArduinoBLE` + `Servo` (via Gestionnaire de bibliothèques) | BLE intégré |
| **Arduino Uno / Nano + module HM-10** | `Servo` + `SoftwareSerial` (incluses de base) | `D2` -> TXD du HM-10, `D3` -> RXD du HM-10 *(pont diviseur 5V → 3.3V recommandé)* |
| **Arduino Mega + module HM-10** | `Servo` (incluse de base) | `Serial1` : `19 (RX1)` -> TXD du HM-10, `18 (TX1)` -> RXD du HM-10 |

> **Astuce capteur de température :** Par défaut (`#define TEMP_SENSOR_TYPE 0`), l'Arduino envoie une température de démonstration vers l'iPhone. Pour utiliser un vrai capteur analogique sur `A0`, modifiez `TEMP_SENSOR_TYPE` à `1` (LM35), `2` (TMP36) ou `3` (Thermistance NTC 10k).

3. Sélectionnez votre carte et votre port série dans **Outils > Carte / Port**, puis cliquez sur **Téléverser**.
4. Ouvrez le **Moniteur série** à `115200 bauds` pour vérifier que la carte a bien été identifiée.

---

## Partie 2 — Créer le projet iOS dans Xcode et importer les fichiers

> **Important :** CoreBluetooth ne permet pas de scanner ni de se connecter à des périphériques BLE réels depuis le simulateur iOS. Vous devez compiler sur un **iPhone réel**.

### Étape 1 : Créer le projet Xcode
1. Ouvrez **Xcode** (Xcode 14.3, 15 ou 16 sur macOS).
2. Cliquez sur **Create New Project...** (ou `File > New > Project...`).
3. Choisissez l'onglet **iOS**, sélectionnez **App**, puis cliquez sur **Next**.
4. Renseignez les champs :
   - **Product Name** : `ArduinoBLEController`
   - **Interface** : `SwiftUI`
   - **Language** : `Swift`
   - **Storage** : `None` (ne cochez pas SwiftData / CoreData)
5. Enregistrez le projet à l'emplacement souhaité.

### Étape 2 : Définir la version minimale iOS 16+
1. Dans le navigateur de gauche (Project Navigator), cliquez sur la racine du projet (icône bleue `ArduinoBLEController`).
2. Sélectionnez votre **Target** (`ArduinoBLEController`) puis l'onglet **General**.
3. Dans **Minimum Deployments**, choisissez **iOS 16.0** (ou supérieur).

### Étape 3 : Importer les fichiers `.swift`
1. Dans le Project Navigator de Xcode, **supprimez** les deux fichiers créés par défaut par Xcode :
   - `ContentView.swift`
   - `ArduinoBLEControllerApp.swift` (choisissez **Move to Trash** afin d'éviter un doublon `@main`).
2. Ouvrez le Finder, entrez dans le dossier `iOS_App/` décompressé.
3. Glissez-déposez les 5 dossiers (`App`, `Models`, `Services`, `ViewModels`, `Views`) directement dans le dossier de votre Target dans Xcode.
4. Dans la boîte de dialogue d'importation :
   - Cochez **Copy items if needed** (ou *Copy files to destination* sur Xcode 16).
   - Sélectionnez **Create groups**.
   - Vérifiez que votre Target `ArduinoBLEController` est bien cochée dans **Add to targets**.
5. Cliquez sur **Finish**.

### Étape 4 : Configurer la permission Bluetooth (`Info.plist`)
Sans cette clé obligatoire, iOS ferme immédiatement l'application au lancement du scan Bluetooth :

1. Cliquez sur la racine du projet dans Xcode > sélectionnez la Target **ArduinoBLEController**.
2. Ouvrez l'onglet **Info** (section **Custom iOS Target Properties**).
3. Survolez une ligne existante et cliquez sur le bouton **`+`** pour ajouter une nouvelle clé.
4. Tapez ou sélectionnez dans la liste :
   - Clé : **`Privacy - Bluetooth Always Usage Description`**
     *(si vous éditez `Info.plist` en XML brut, le nom exact de la clé est **`NSBluetoothAlwaysUsageDescription`**)*.
   - Type : `String`
   - Valeur : `Cette application utilise le Bluetooth Low Energy pour détecter et piloter votre carte Arduino.`

### Étape 5 : Signature, GameController et compilation sur un iPhone réel
1. Toujours dans les réglages de la Target, ouvrez l'onglet **Signing & Capabilities**.
2. *(Optionnel recommandé pour la manette PS4)* : cliquez sur **`+ Capability`**, ajoutez **Game Controllers**, puis cochez **Extended Gamepad**.
3. Cochez **Automatically manage signing** et sélectionnez votre compte Apple dans **Team**.
4. Si le **Bundle Identifier** pose un conflit, personnalisez-le (ex. `com.votrenom.arduinoblecontroller`).
5. Sur votre iPhone :
   - Branchez l'iPhone au Mac par câble USB (puis touchez **Faire confiance à cet ordinateur**).
   - Activez le **Mode développeur** sur iOS 16+ : **Réglages > Confidentialité et sécurité > Mode développeur** (redémarrage requis la première fois).
   - Vérifiez que le **Bluetooth** est activé sur l'iPhone.
6. Dans la barre supérieure de Xcode, sélectionnez votre **iPhone physique** comme destination d'exécution, puis appuyez sur **Cmd + R** (bouton Run).

---

## Partie 3 — Fonctionnement de l'adaptation automatique & de la Manette

### 1. Adaptation automatique à la carte Arduino
- À la connexion, l'application iOS envoie automatiquement la requête `I?` à la carte.
- L'Arduino répond avec son profil exact (`INFO:BOARD=...;PINS=...;PWM=...;TEMP=1`).
- L'application reconnaît aussi les services BLE **ArduinoBLE/ESP32**, **HM-10 (`FFE0`/`FFE1`)** et **Nordic UART**, puis ajuste automatiquement la liste des broches disponibles et des broches PWM dans l'éditeur de boutons.
- Vous pouvez aussi forcer manuellement un profil de carte depuis l'onglet **Assigner > Profil Arduino**.

### 2. Page d'assignation style manette (onglet « Assigner »)
- Touchez directement n'importe quel bouton sur le schéma de manette interactif (`↑`, `↓`, `←`, `→`, `A`, `B`, `X`, `Y`, `L1`, `R1`, `L2`, `R2`, `Select`, `Start`) ou dans la liste.
- Pour chaque bouton, vous pouvez choisir :
  - **Nom, couleur et icône**
  - **Type d'action** : Sortie Digitale (ON/OFF), Sortie PWM (0–255), Servomoteur (0–180°), Multi-broches (ex. piloter 4 broches d'un pont en H L298N d'un seul appui), Commande texte libre, ou Arrêt d'urgence (`X`)
  - **Comportement** : Maintenu (*Momentary* — envoie à l'appui et coupe au relâchement), Interrupteur (*Toggle*), ou Impulsion (*Push*)
- Trois modèles prêts à l'emploi (**Découverte**, **Robot 4 Directions**, **Bras / Multi-Servos**) adaptent instantanément leurs numéros de broches à la carte connectée.

### 3. Utiliser une manette PS4 (DualShock 4) en Bluetooth
L'iPhone sert de passerelle temps réel entre votre manette PS4 et l'Arduino en BLE :

1. Sur la manette PS4, maintenez **SHARE + PS** pendant 3 secondes jusqu'au clignotement rapide de la barre LED.
2. Sur l'iPhone, ouvrez **Réglages > Bluetooth** et connectez **DUALSHOCK 4 Wireless Controller**.
3. Ouvrez l'application : la barre LED de la manette PS4 devient **verte** lorsque l'Arduino BLE est connecté (rouge si déconnecté, orange pendant la connexion).
4. Les touches de la manette PS4 pilotent directement les assignations configurées dans l'onglet **Assigner** :
   - **Croix / Rond / Carré / Triangle** → Boutons `A / B / X / Y`
   - **Croix directionnelle** ou **Stick gauche** → Croix `↑ / ↓ / ← / →`
   - **L1 / R1** → Gâchettes `L1 / R1`
   - **L2 / R2** (ou **Stick droit X/Y** si activé) → Curseurs analogiques `L2 / R2`
   - **Share / Options** → `Select / Start`

---

## Partie 2B — Compiler l'IPA automatiquement avec GitHub Actions (sans Mac)

Si vous n'avez pas de Mac avec Xcode, utilisez le workflow déjà inclus :

1. Créez un nouveau dépôt sur GitHub (public pour des minutes macOS illimitées, ou privé dans la limite du quota mensuel).
2. Décompressez l'archive et poussez **tout son contenu** (y compris le dossier caché `.github/workflows/build-ipa.yml` et `project.yml`) sur la branche `main` ou `master`.
3. Sur GitHub, ouvrez l'onglet **Actions** : le workflow **Build iOS IPA (Unsigned)** démarre automatiquement (vous pouvez aussi le lancer manuellement via **Run workflow**).
4. Une fois terminé, téléchargez l'artefact **`ArduinoBLEController-unsigned-ipa`** contenant `ArduinoBLEController-unsigned.ipa`.
5. Installez ce `.ipa` sur votre iPhone depuis Windows, Linux ou macOS avec **Sideloadly** ou **AltStore** (compte Apple gratuit, à renouveler tous les 7 jours).

---

## Protocole BLE (référence rapide)

- **UUID Service personnalisé** : `4fafca01-1fb5-459e-8fcc-c5c9c331914b`
- **UUID RX (iOS → Arduino)** : `beb5483e-36e1-4688-b7f5-ea07361b26a8`
- **UUID TX (Arduino → iOS)** : `beb5483f-36e1-4688-b7f5-ea07361b26a8`
- **HM-10 compatible** : Service `FFE0`, Caractéristique `FFE1`

| Commande envoyée | Action sur l'Arduino |
| :--- | :--- |
| `I?` | Renvoie les capacités de la carte (`INFO:...`) |
| `T?` | Renvoie la télémétrie compacte (`DATA:T=...;S=...`) |
| `D:13:1` / `D:13:0` | Met la broche 13 à `HIGH` ou `LOW` |
| `P:5:200` | Applique une sortie PWM `200` (0–255) sur la broche 5 |
| `V:9:90` | Positionne le servomoteur sur la broche 9 à `90°` (0–180) |
| `M:5D1,6D0,10D1,11D0` | Lot atomique multi-broches en 1 seul paquet BLE (Digital/PWM/Servo) |
| `R:7` | Lit l'état logique de la broche 7 |
| `X` | Arrêt d'urgence : coupe toutes les sorties actives |
