/*
 * ============================================================================
 *  ArduinoBLE Adaptive Controller - Sketch Universel Multi-Cartes
 * ============================================================================
 *  Ce sketch s'adapte automatiquement à la carte Arduino utilisée :
 *    1. ESP32 / Arduino Nano ESP32          -> BLE natif (BLEDevice.h)
 *    2. Arduino Uno R4 WiFi / Nano 33 BLE /
 *       Nano 33 IoT / MKR WiFi 1010 / GIGA  -> Bibliothèque ArduinoBLE
 *    3. Arduino Uno / Nano / Mega + HM-10   -> Série UART (SoftwareSerial / Serial1)
 *
 *  Protocole compact (<= 20 octets par commande, compatible MTU BLE standard) :
 *    - I?           -> Renvoie les capacités de la carte (INFO:BOARD=...;PINS=...;PWM=...;TEMP=1)
 *    - T?           -> Renvoie immédiatement la télémétrie (DATA:TEMP=...;UP=...)
 *    - D:<pin>:<v>  -> Sortie digitale (v = 0 ou 1)
 *    - P:<pin>:<v>  -> Sortie PWM (v = 0 à 255)
 *    - V:<pin>:<v>  -> Servomoteur (v = angle 0 à 180°)
 *    - R:<pin>      -> Lecture digitale d'une broche (DATA:PIN<pin>=<0|1>)
 *    - X            -> Arrêt d'urgence (remet toutes les sorties actives à 0)
 *    - PING         -> Répond PONG
 *
 *  Sécurité matérielle :
 *    - En cas de déconnexion BLE, toutes les sorties actives sont coupées.
 *    - Les broches réservées (USB Serial 0/1, RX/TX HM-10, Flash SPI ESP32) sont protégées.
 * ============================================================================
 */

#include <Arduino.h>

// ============================================================================
// 1. CONFIGURATION UTILISATEUR (OPTIONNEL)
// ============================================================================

// Décommentez UNE de ces lignes uniquement si la détection automatique échoue :
// #define FORCE_BLE_MODE_ESP32
// #define FORCE_BLE_MODE_ARDUINOBLE
// #define FORCE_BLE_MODE_HM10

// Source de température pour le retour de télémétrie vers l'iPhone :
//   0 = Valeur de démonstration (aucun capteur requis)
//   1 = Capteur analogique LM35 sur TEMP_ANALOG_PIN (10 mV / °C)
//   2 = Capteur analogique TMP36 sur TEMP_ANALOG_PIN (offset 500 mV, 10 mV / °C)
//   3 = Thermistance NTC 10k (pont diviseur 10k vers VCC/GND sur TEMP_ANALOG_PIN)
#define TEMP_SENSOR_TYPE 0
#ifdef A0
  #define TEMP_ANALOG_PIN A0
#else
  #define TEMP_ANALOG_PIN 36
#endif

// Intervalle d'envoi automatique de la télémétrie (en millisecondes)
#define TELEMETRY_INTERVAL_MS 2000UL

// Logs sur le Moniteur Série USB : 0 = désactivé, 1 = erreurs/système, 2 = toutes trames RX
#define DEBUG_SERIAL 1

// Broches utilisées pour le module HM-10 sur Arduino Uno / Nano (ignoré sur ESP32/R4/Mega)
#define HM10_RX_PIN 2  // Relier au TXD du module HM-10
#define HM10_TX_PIN 3  // Relier au RXD du module HM-10 (pont diviseur 5V -> 3.3V conseillé)
#define HM10_BAUD   9600

// ============================================================================
// 2. DÉTECTION AUTOMATIQUE DE LA CARTE ET DU MODE BLE
// ============================================================================

#if defined(FORCE_BLE_MODE_ESP32)
  #define BLE_MODE_ESP32
#elif defined(FORCE_BLE_MODE_ARDUINOBLE)
  #define BLE_MODE_ARDUINOBLE
#elif defined(FORCE_BLE_MODE_HM10)
  #define BLE_MODE_HM10
#elif defined(ESP32) || defined(ARDUINO_ARCH_ESP32)
  #define BLE_MODE_ESP32
#elif defined(ARDUINO_UNOR4_WIFI) || defined(ARDUINO_NANO33BLE) || defined(ARDUINO_ARCH_NRF52840) || defined(ARDUINO_SAMD_NANO_33_IOT) || defined(ARDUINO_SAMD_MKRWIFI1010) || defined(ARDUINO_GIGA)
  #define BLE_MODE_ARDUINOBLE
#else
  #define BLE_MODE_HM10
#endif

// Identifiant et liste des broches envoyés à l'iPhone lors du handshake "I?"
#if defined(BLE_MODE_ESP32)
  #define BOARD_ID_STR   "ESP32"
  #define DEVICE_NAME    "ArduinoBLE-ESP32"
  #define PINS_LIST_STR  "2,4,5,12,13,14,15,16,17,18,19,21,22,23,25,26,27,32,33"
  #define PWM_LIST_STR   "2,4,5,12,13,14,15,18,19,21,22,23,25,26,27,32,33"
#elif defined(ARDUINO_UNOR4_WIFI)
  #define BOARD_ID_STR   "UNO_R4_WIFI"
  #define DEVICE_NAME    "ArduinoBLE-R4"
  #define PINS_LIST_STR  "2,3,4,5,6,7,8,9,10,11,12,13"
  #define PWM_LIST_STR   "3,5,6,9,10,11"
#elif defined(ARDUINO_NANO33BLE) || defined(ARDUINO_ARCH_NRF52840) || defined(ARDUINO_SAMD_NANO_33_IOT) || defined(ARDUINO_SAMD_MKRWIFI1010)
  #define BOARD_ID_STR   "NANO_33_BLE"
  #define DEVICE_NAME    "ArduinoBLE-Nano"
  #define PINS_LIST_STR  "2,3,4,5,6,7,8,9,10,11,12,13"
  #define PWM_LIST_STR   "2,3,4,5,6,7,8,9,10,11,12,13"
#elif defined(__AVR_ATmega2560__) || defined(__AVR_ATmega1280__)
  #define BOARD_ID_STR   "MEGA_HM10"
  #define DEVICE_NAME    "ArduinoBLE-Mega"
  #define PINS_LIST_STR  "2,3,4,5,6,7,8,9,10,11,12,13,22,23,24,25,26,27,28,29,30,31,32,33,44,45,46"
  #define PWM_LIST_STR   "2,3,4,5,6,7,8,9,10,11,12,13,44,45,46"
#else
  #define BOARD_ID_STR   "UNO_HM10"
  #define DEVICE_NAME    "ArduinoBLE-Uno"
  // Les broches 2 et 3 sont réservées à SoftwareSerial pour communiquer avec le HM-10
  #define PINS_LIST_STR  "4,5,6,7,8,9,10,11,12,13"
  #define PWM_LIST_STR   "5,6,9,10,11"
#endif

// UUIDs identiques à ceux configurés dans BLEProtocolConstants.swift sur iOS
#if !defined(BLE_MODE_HM10)
static const char* SERVICE_UUID = "4fafca01-1fb5-459e-8fcc-c5c9c331914b";
static const char* RX_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
static const char* TX_CHAR_UUID = "beb5483f-36e1-4688-b7f5-ea07361b26a8";
#endif

// ============================================================================
// 3. INCLUSIONS SPÉCIFIQUES À LA PLATEFORME
// ============================================================================

#if defined(BLE_MODE_ESP32)
  #include <BLEDevice.h>
  #include <BLEServer.h>
  #include <BLEUtils.h>
  #include <BLE2902.h>
  #include <math.h>
#elif defined(BLE_MODE_ARDUINOBLE)
  #include <ArduinoBLE.h>
  #include <Servo.h>
  #include <math.h>
#else
  #include <Servo.h>
  #include <math.h>
  #if defined(__AVR_ATmega2560__) || defined(__AVR_ATmega1280__) || defined(__AVR_ATmega32U4__)
    #define HM10_USE_SERIAL1
  #else
    #include <SoftwareSerial.h>
    SoftwareSerial hm10Serial(HM10_RX_PIN, HM10_TX_PIN);
  #endif
#endif

// ============================================================================
// 4. GESTION DES BROCHES ET SERVOMOTEURS
// ============================================================================

enum PinRole : uint8_t {
  ROLE_NONE = 0,
  ROLE_DIGITAL,
  ROLE_PWM,
  ROLE_SERVO,
  ROLE_INPUT
};

#define MAX_MANAGED_PINS 16
#define MAX_PIN_INDEX    54
#define MAX_SERVOS       6

struct ManagedPin {
  int8_t  pin;
  PinRole role;
  int16_t lastValue;
  int8_t  servoSlot; // Index dans le tableau servos[] ou canal LEDC ESP32
};

ManagedPin managedPins[MAX_MANAGED_PINS];
int8_t     pinSlotMap[MAX_PIN_INDEX + 1];

#if !defined(BLE_MODE_ESP32)
Servo servoPool[MAX_SERVOS];
bool  servoSlotUsed[MAX_SERVOS];
#else
bool  espLedcSlotUsed[MAX_SERVOS];
#endif

// Tampon de réception série/BLE (protocole terminé par '\n')
#define RX_BUFFER_SIZE 96
char   rxBuffer[RX_BUFFER_SIZE];
uint8_t rxIndex = 0;

// État de connexion et télémétrie
volatile bool bleClientConnected = false;
volatile bool pendingDisconnectCleanup = false;
bool          wasConnected = false;
unsigned long lastTelemetryMs = 0;
float         demoTempBase = 22.8f;

// Prototypes
void processCommand(char* rawCmd);
void sendBleLine(const char* line);
void sendBleLineF(const __FlashStringHelper* msg);
void sendPinReservedError(int pin);
void stopAllOutputs();

// Décodeur de trame partagé entre ESP32, ArduinoBLE et HM-10 (zéro allocation)
inline void feedIncomingByte(char c) {
  if (c == '\r') return;
  if (c == '\n') {
    rxBuffer[rxIndex] = '\0';
    if (rxIndex > 0) {
      processCommand(rxBuffer);
      rxIndex = 0;
    }
  } else if (rxIndex < RX_BUFFER_SIZE - 1) {
    rxBuffer[rxIndex++] = c;
    #if defined(BLE_MODE_HM10)
      // Certains modules HM-10 (AT+NOTI1) envoient OK+CONN ou OK+LOST sans '\n'
      if (rxIndex == 7 && rxBuffer[0] == 'O' && rxBuffer[1] == 'K' && rxBuffer[2] == '+') {
        if (memcmp(rxBuffer, "OK+CONN", 7) == 0) {
          rxIndex = 0;
          bleClientConnected = true;
        } else if (memcmp(rxBuffer, "OK+LOST", 7) == 0) {
          rxIndex = 0;
          bleClientConnected = false;
          pendingDisconnectCleanup = true;
        }
      }
    #endif
  } else {
    rxIndex = 0;
  }
}

// ============================================================================
// 5. PILOTE BLE SELON L'ARCHITECTURE
// ============================================================================

#if defined(BLE_MODE_ESP32)

BLEServer*         pServer = nullptr;
BLECharacteristic* pTxChar = nullptr;
BLECharacteristic* pRxChar = nullptr;
volatile bool      espNeedStartAdvertising = false;
unsigned long      espAdvScheduleMs = 0;

// Tampon circulaire puissance de 2 avec barrière mémoire pour transfert inter-cœurs sûr
#define BLE_RING_SIZE 256
#define BLE_RING_MASK (BLE_RING_SIZE - 1)
volatile uint8_t bleRing[BLE_RING_SIZE];
volatile uint16_t bleRingHead = 0;
volatile uint16_t bleRingTail = 0;

class AdaptiveServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    (void)server;
    bleClientConnected = true;
  }
  void onDisconnect(BLEServer* server) override {
    (void)server;
    bleClientConnected = false;
    pendingDisconnectCleanup = true;
    espNeedStartAdvertising = true;
  }
};

class AdaptiveRxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    // getData() et getLength() fonctionnent sur ESP32 Core v2.x ET v3.x
    const uint8_t* data = characteristic->getData();
    size_t len = characteristic->getLength();
    uint16_t head = bleRingHead;
    for (size_t i = 0; i < len; i++) {
      uint16_t next = (uint16_t)((head + 1) & BLE_RING_MASK);
      if (next != bleRingTail) {
        bleRing[head] = data[i];
        head = next;
      }
    }
    __sync_synchronize();
    bleRingHead = head;
  }
};

void initBleTransport() {
  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new AdaptiveServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pTxChar = pService->createCharacteristic(
    TX_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxChar->addDescriptor(new BLE2902());

  pRxChar = pService->createCharacteristic(
    RX_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pRxChar->setCallbacks(new AdaptiveRxCallbacks());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
}

void pollBleTransport() {
  if (espNeedStartAdvertising) {
    if (espAdvScheduleMs == 0) {
      espAdvScheduleMs = millis();
    } else if (millis() - espAdvScheduleMs >= 100UL) {
      espNeedStartAdvertising = false;
      espAdvScheduleMs = 0;
      BLEDevice::startAdvertising();
    }
  }
  while (bleRingTail != bleRingHead) {
    __sync_synchronize();
    char c = (char)bleRing[bleRingTail];
    bleRingTail = (uint16_t)((bleRingTail + 1) & BLE_RING_MASK);
    feedIncomingByte(c);
  }
}

void writeBlePacket(const uint8_t* data, size_t len) {
  if (!bleClientConnected || pTxChar == nullptr) return;
  pTxChar->setValue(const_cast<uint8_t*>(data), len);
  pTxChar->notify();
}

#elif defined(BLE_MODE_ARDUINOBLE)

BLEService        adaptiveService(SERVICE_UUID);
BLECharacteristic rxCharacteristic(RX_CHAR_UUID, BLEWrite | BLEWriteWithoutResponse, 64);
BLECharacteristic txCharacteristic(TX_CHAR_UUID, BLERead | BLENotify, 64);

void initBleTransport() {
  if (!BLE.begin()) {
    Serial.println(F("[ERREUR] Démarrage ArduinoBLE impossible !"));
    while (1) {
      delay(1000);
    }
  }
  BLE.setLocalName(DEVICE_NAME);
  BLE.setDeviceName(DEVICE_NAME);
  BLE.setAdvertisedService(adaptiveService);
  adaptiveService.addCharacteristic(rxCharacteristic);
  adaptiveService.addCharacteristic(txCharacteristic);
  BLE.addService(adaptiveService);
  BLE.advertise();
}

void pollBleTransport() {
  BLE.poll();
  BLEDevice central = BLE.central();

  if (central && central.connected()) {
    bleClientConnected = true;
    if (rxCharacteristic.written()) {
      int len = rxCharacteristic.valueLength();
      const uint8_t* data = rxCharacteristic.value();
      for (int i = 0; i < len; i++) {
        feedIncomingByte((char)data[i]);
      }
    }
  } else {
    if (bleClientConnected) {
      bleClientConnected = false;
      pendingDisconnectCleanup = true;
    }
  }
}

void writeBlePacket(const uint8_t* data, size_t len) {
  if (!bleClientConnected) return;
  txCharacteristic.writeValue(data, (int)len);
}

#else // BLE_MODE_HM10

void initBleTransport() {
  #if defined(HM10_USE_SERIAL1)
    Serial1.begin(HM10_BAUD);
  #else
    hm10Serial.begin(HM10_BAUD);
  #endif
  // Passe automatiquement à true dès la première trame reçue (ex: handshake "I?")
  bleClientConnected = false;
}

void pollBleTransport() {
  #if defined(HM10_USE_SERIAL1)
    Stream& port = Serial1;
  #else
    Stream& port = hm10Serial;
  #endif

  while (port.available() > 0) {
    bleClientConnected = true;
    feedIncomingByte((char)port.read());
  }
}

void writeBlePacket(const uint8_t* data, size_t len) {
  #if defined(HM10_USE_SERIAL1)
    Serial1.write(data, len);
  #else
    hm10Serial.write(data, len);
  #endif
}

#endif

// Découpe automatiquement toute réponse en paquets <= 20 octets (compatible BLE 4.0 / HM-10)
void sendBleLine(const char* line) {
  if (line == nullptr) return;
  size_t rawLen = strlen(line);
  if (rawLen == 0) return;

  char packet[20];
  size_t offset = 0;
  bool needsNewline = (line[rawLen - 1] != '\n');

  while (offset < rawLen) {
    size_t chunkLen = rawLen - offset;
    if (chunkLen > 20) chunkLen = 20;

    if (chunkLen < 20 && offset + chunkLen == rawLen && needsNewline) {
      memcpy(packet, line + offset, chunkLen);
      packet[chunkLen] = '\n';
      writeBlePacket((const uint8_t*)packet, chunkLen + 1);
      needsNewline = false;
    } else {
      writeBlePacket((const uint8_t*)(line + offset), chunkLen);
    }

    offset += chunkLen;
    if (offset < rawLen || needsNewline) {
      #if defined(BLE_MODE_ARDUINOBLE)
        BLE.poll();
      #endif
      delay(10);
    }
  }

  if (needsNewline) {
    const uint8_t nl = '\n';
    writeBlePacket(&nl, 1);
  }
}

void sendBleLine_P(const char* progmemStr) {
  #if defined(__AVR__)
    if (progmemStr == nullptr) return;
    char packet[20];
    size_t offset = 0;
    char lastChar = '\0';
    bool ended = false;
    while (!ended) {
      uint8_t chunkLen = 0;
      while (chunkLen < 20) {
        char c = (char)pgm_read_byte(progmemStr + offset + chunkLen);
        if (c == '\0') {
          ended = true;
          break;
        }
        packet[chunkLen++] = c;
        lastChar = c;
      }
      if (offset == 0 && chunkLen == 0) return;
      offset += chunkLen;
      if (ended && lastChar != '\n' && chunkLen < 20) {
        packet[chunkLen++] = '\n';
        lastChar = '\n';
      }
      if (chunkLen > 0) {
        writeBlePacket((const uint8_t*)packet, chunkLen);
      }
      if (!ended) {
        delay(10);
      }
    }
    if (lastChar != '\n') {
      const uint8_t nl = '\n';
      writeBlePacket(&nl, 1);
    }
  #else
    sendBleLine(progmemStr);
  #endif
}

void sendBleLineF(const __FlashStringHelper* msg) {
  #if defined(__AVR__)
    sendBleLine_P(reinterpret_cast<const char*>(msg));
  #else
    sendBleLine(reinterpret_cast<const char*>(msg));
  #endif
}

void sendPinReservedError(int pin) {
  char buf[32];
  snprintf(buf, sizeof(buf), "ERR:PIN_%d_RESERVED", pin);
  sendBleLine(buf);
}

// ============================================================================
// 6. SÉCURITÉ DES BROCHES ET GESTION DES ACTIONNEURS
// ============================================================================

bool isPinAllowed(int pin) {
  if (pin < 0) return false;

  #if defined(BLE_MODE_ESP32)
    // Protéger les broches Flash SPI (6..11 sur ESP32 classique) et entrée seule (34..39)
    #if defined(CONFIG_IDF_TARGET_ESP32)
      if (pin >= 6 && pin <= 11) return false;
      if (pin >= 34 && pin <= 39) return false;
      if (pin > 39) return false;
    #elif defined(CONFIG_IDF_TARGET_ESP32S3)
      if (pin > 48) return false;
    #else
      if (pin > 39) return false;
    #endif
    return true;
  #elif defined(BLE_MODE_ARDUINOBLE)
    // Éviter RX/TX matériel 0 et 1
    if (pin == 0 || pin == 1) return false;
    if (pin > 21) return false;
    return true;
  #else
    // Éviter USB Serial (0, 1) et les broches dédiées au HM-10
    if (pin == 0 || pin == 1) return false;
    #if !defined(HM10_USE_SERIAL1)
      if (pin == HM10_RX_PIN || pin == HM10_TX_PIN) return false;
    #else
      if (pin == 18 || pin == 19) return false;
    #endif
    #if defined(__AVR_ATmega2560__) || defined(__AVR_ATmega1280__)
      if (pin > 53) return false;
    #else
      if (pin > 19) return false;
    #endif
    return true;
  #endif
}

int findOrAllocateManagedPin(int pin) {
  if (pin >= 0 && pin <= MAX_PIN_INDEX) {
    int8_t mapped = pinSlotMap[pin];
    if (mapped >= 0) return (int)mapped;
  } else {
    for (int i = 0; i < MAX_MANAGED_PINS; i++) {
      if (managedPins[i].pin == pin) return i;
    }
  }

  for (int i = 0; i < MAX_MANAGED_PINS; i++) {
    if (managedPins[i].pin < 0) {
      managedPins[i].pin = (int8_t)pin;
      managedPins[i].role = ROLE_NONE;
      managedPins[i].lastValue = -1;
      managedPins[i].servoSlot = -1;
      if (pin >= 0 && pin <= MAX_PIN_INDEX) {
        pinSlotMap[pin] = (int8_t)i;
      }
      return i;
    }
  }
  return -1;
}

void releaseServoSlotIfNeeded(ManagedPin& mp) {
  if (mp.role == ROLE_SERVO && mp.servoSlot >= 0 && mp.servoSlot < MAX_SERVOS) {
    #if defined(BLE_MODE_ESP32)
      #if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
        ledcDetach((uint8_t)mp.pin);
      #else
        ledcDetachPin((uint8_t)mp.pin);
      #endif
      espLedcSlotUsed[mp.servoSlot] = false;
    #else
      servoPool[mp.servoSlot].detach();
      servoSlotUsed[mp.servoSlot] = false;
    #endif
    mp.servoSlot = -1;
  }
}

void applyDigitalOutput(int pin, int value) {
  if (!isPinAllowed(pin)) {
    sendPinReservedError(pin);
    return;
  }
  int idx = findOrAllocateManagedPin(pin);
  if (idx < 0) {
    sendBleLineF(F("ERR:MAX_PINS"));
    return;
  }
  ManagedPin& mp = managedPins[idx];
  int16_t normalized = (value > 0) ? 1 : 0;
  if (mp.role == ROLE_DIGITAL && mp.lastValue == normalized) {
    return;
  }
  releaseServoSlotIfNeeded(mp);
  if (mp.role != ROLE_DIGITAL) {
    pinMode(pin, OUTPUT);
    mp.role = ROLE_DIGITAL;
  }
  digitalWrite(pin, normalized ? HIGH : LOW);
  mp.lastValue = normalized;
}

void applyPwmOutput(int pin, int value) {
  if (!isPinAllowed(pin)) {
    sendPinReservedError(pin);
    return;
  }
  int idx = findOrAllocateManagedPin(pin);
  if (idx < 0) {
    sendBleLineF(F("ERR:MAX_PINS"));
    return;
  }
  ManagedPin& mp = managedPins[idx];
  int16_t clamped = (int16_t)constrain(value, 0, 255);
  if (mp.role == ROLE_PWM && mp.lastValue == clamped) {
    return;
  }
  releaseServoSlotIfNeeded(mp);
  if (mp.role != ROLE_PWM) {
    pinMode(pin, OUTPUT);
    mp.role = ROLE_PWM;
  }
  analogWrite(pin, (int)clamped);
  mp.lastValue = clamped;
}

void applyServoOutput(int pin, int angle) {
  if (!isPinAllowed(pin)) {
    sendPinReservedError(pin);
    return;
  }
  int idx = findOrAllocateManagedPin(pin);
  if (idx < 0) {
    sendBleLineF(F("ERR:MAX_PINS"));
    return;
  }
  ManagedPin& mp = managedPins[idx];
  int16_t clamped = (int16_t)constrain(angle, 0, 180);
  if (mp.role == ROLE_SERVO && mp.lastValue == clamped) {
    return;
  }

  if (mp.role != ROLE_SERVO) {
    int slot = -1;
    for (int s = 0; s < MAX_SERVOS; s++) {
      #if defined(BLE_MODE_ESP32)
        if (!espLedcSlotUsed[s]) { slot = s; espLedcSlotUsed[s] = true; break; }
      #else
        if (!servoSlotUsed[s]) { slot = s; servoSlotUsed[s] = true; break; }
      #endif
    }
    if (slot < 0) {
      sendBleLineF(F("ERR:MAX_SERVOS"));
      return;
    }
    mp.role = ROLE_SERVO;
    mp.servoSlot = (int8_t)slot;

    #if defined(BLE_MODE_ESP32)
      #if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
        ledcAttach((uint8_t)pin, 50, 16);
      #else
        // Utilisation des canaux 8..13 pour éviter tout conflit avec analogWrite()
        ledcSetup((uint8_t)(slot + 8), 50, 16);
        ledcAttachPin((uint8_t)pin, (uint8_t)(slot + 8));
      #endif
    #else
      servoPool[slot].attach(pin);
    #endif
  }

  #if defined(BLE_MODE_ESP32)
    uint32_t pulseUs = (uint32_t)map((int)clamped, 0, 180, 544, 2400);
    uint32_t duty = (pulseUs * 65535UL) / 20000UL;
    #if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
      ledcWrite((uint8_t)pin, duty);
    #else
      ledcWrite((uint8_t)(mp.servoSlot + 8), duty);
    #endif
  #else
    servoPool[mp.servoSlot].write((int)clamped);
  #endif

  mp.lastValue = clamped;
}

void readDigitalPin(int pin) {
  if (!isPinAllowed(pin)) {
    sendPinReservedError(pin);
    return;
  }
  int idx = findOrAllocateManagedPin(pin);
  if (idx >= 0) {
    ManagedPin& mp = managedPins[idx];
    releaseServoSlotIfNeeded(mp);
    if (mp.role != ROLE_INPUT) {
      pinMode(pin, INPUT_PULLUP);
      mp.role = ROLE_INPUT;
    }
  } else {
    pinMode(pin, INPUT_PULLUP);
  }
  int val = digitalRead(pin);
  char buf[28];
  snprintf(buf, sizeof(buf), "DATA:PIN%d=%d", pin, val);
  sendBleLine(buf);
}

void stopAllOutputs() {
  for (int i = 0; i < MAX_MANAGED_PINS; i++) {
    if (managedPins[i].pin < 0) continue;
    int pin = managedPins[i].pin;
    if (managedPins[i].role == ROLE_DIGITAL) {
      digitalWrite(pin, LOW);
      managedPins[i].lastValue = 0;
    } else if (managedPins[i].role == ROLE_PWM) {
      analogWrite(pin, 0);
      managedPins[i].lastValue = 0;
    } else if (managedPins[i].role == ROLE_SERVO) {
      // Détachement propre pour couper le couple moteur en arrêt d'urgence
      releaseServoSlotIfNeeded(managedPins[i]);
      managedPins[i].role = ROLE_NONE;
      managedPins[i].lastValue = 0;
    }
  }
}

// ============================================================================
// 7. TÉLÉMÉTRIE ET CAPTEURS
// ============================================================================

#if TEMP_SENSOR_TYPE != 0
int readAveragedAdc(int pin) {
  long sum = 0;
  for (uint8_t i = 0; i < 4; i++) {
    sum += analogRead(pin);
  }
  return (int)(sum >> 2);
}
#endif

float readTemperatureCelsius(bool& isSimulated) {
  #if TEMP_SENSOR_TYPE == 1
    // LM35 : 10 mV / °C (référence 5.0V sur Uno/Mega, 3.3V sur ESP32/Nano33)
    isSimulated = false;
    #if defined(BLE_MODE_ESP32) || defined(ARDUINO_NANO33BLE) || defined(ARDUINO_SAMD_NANO_33_IOT)
      float vRef = 3.3f;
      float adcMax = 4095.0f;
    #else
      float vRef = 5.0f;
      float adcMax = 1023.0f;
    #endif
    float voltage = (readAveragedAdc(TEMP_ANALOG_PIN) * vRef) / adcMax;
    return voltage * 100.0f;
  #elif TEMP_SENSOR_TYPE == 2
    // TMP36 : (V - 0.5V) * 100
    isSimulated = false;
    #if defined(BLE_MODE_ESP32) || defined(ARDUINO_NANO33BLE) || defined(ARDUINO_SAMD_NANO_33_IOT)
      float vRef = 3.3f;
      float adcMax = 4095.0f;
    #else
      float vRef = 5.0f;
      float adcMax = 1023.0f;
    #endif
    float voltage = (readAveragedAdc(TEMP_ANALOG_PIN) * vRef) / adcMax;
    return (voltage - 0.5f) * 100.0f;
  #elif TEMP_SENSOR_TYPE == 3
    // Thermistance NTC 10k (Beta = 3950) en pont diviseur avec résistance 10k
    isSimulated = false;
    int raw = readAveragedAdc(TEMP_ANALOG_PIN);
    if (raw <= 0) raw = 1;
    #if defined(BLE_MODE_ESP32) || defined(ARDUINO_NANO33BLE) || defined(ARDUINO_SAMD_NANO_33_IOT)
      float adcMax = 4095.0f;
    #else
      float adcMax = 1023.0f;
    #endif
    float rTherm = 10000.0f * (adcMax / (float)raw - 1.0f);
    float steinhart = log(rTherm / 10000.0f) / 3950.0f + (1.0f / (25.0f + 273.15f));
    return (1.0f / steinhart) - 273.15f;
  #else
    // Mode démonstration réaliste lorsqu'aucun capteur physique n'est branché
    isSimulated = true;
    float oscillation = 0.6f * sinf((float)millis() / 6000.0f);
    return demoTempBase + oscillation;
  #endif
}

void sendTelemetry() {
  bool isSim = true;
  float temp = readTemperatureCelsius(isSim);
  int tempTenths = (int)roundf(temp * 10.0f);
  int absTenths = abs(tempTenths);
  const char* sign = (tempTenths < 0) ? "-" : "";

  // Trame compacte <= 20 octets (envoi BLE unique sans découpage ni délai)
  char msg[24];
  snprintf(
    msg, sizeof(msg),
    "DATA:T=%s%d.%d;S=%d",
    sign, absTenths / 10, absTenths % 10, isSim ? 1 : 0
  );
  sendBleLine(msg);
}

void sendBoardInfo() {
  #if defined(__AVR__)
    // Stockage intégral en Flash (PROGMEM) : 0 octet de SRAM consommé sur AVR
    static const char INFO_PAYLOAD[] PROGMEM =
      "INFO:BOARD=" BOARD_ID_STR ";PINS=" PINS_LIST_STR ";PWM=" PWM_LIST_STR ";TEMP=1\n";
    sendBleLine_P(INFO_PAYLOAD);
  #else
    static const char INFO_PAYLOAD[] =
      "INFO:BOARD=" BOARD_ID_STR ";PINS=" PINS_LIST_STR ";PWM=" PWM_LIST_STR ";TEMP=1\n";
    sendBleLine(INFO_PAYLOAD);
  #endif
}

// ============================================================================
// 8. INTERPRÉTEUR DE COMMANDES (SANS ALLOCATION DYNAMIQUE)
// ============================================================================

// Exécute un lot multi-broches atomique : M:<pin><D|P|V><val>,<pin><D|P|V><val>...
void applyBatchCommand(char* cursor) {
  while (cursor != nullptr && *cursor != '\0') {
    char* comma = strchr(cursor, ',');
    if (comma != nullptr) {
      *comma = '\0';
    }
    char* endPtr = nullptr;
    long pin = strtol(cursor, &endPtr, 10);
    if (endPtr != cursor && endPtr != nullptr && *endPtr != '\0') {
      char kind = (char)toupper((unsigned char)*endPtr);
      int val = atoi(endPtr + 1);
      if (kind == 'D') {
        applyDigitalOutput((int)pin, val);
      } else if (kind == 'P') {
        applyPwmOutput((int)pin, val);
      } else if (kind == 'V') {
        applyServoOutput((int)pin, val);
      }
    }
    cursor = (comma != nullptr) ? (comma + 1) : nullptr;
  }
}

// Point d'extension pour vos commandes personnalisées depuis le mode "Commande texte libre"
void handleCustomCommand(const char* cmd) {
  if (strcmp(cmd, "PING") == 0) {
    sendBleLineF(F("PONG"));
    return;
  }
  // Exemple : vous pouvez ajouter ici vos propres commandes :
  // if (strcmp(cmd, "CLIGNOTER") == 0) { ... }
  #if DEBUG_SERIAL >= 1
    Serial.print(F("[CMD PERSO] "));
    Serial.println(cmd);
  #endif

  char ack[RX_BUFFER_SIZE + 8];
  snprintf(ack, sizeof(ack), "ACK:%s", cmd);
  sendBleLine(ack);
}

void processCommand(char* rawCmd) {
  if (rawCmd == nullptr) return;

  // Suppression des espaces en début et fin directement dans le tampon
  while (*rawCmd == ' ' || *rawCmd == '\t') rawCmd++;
  size_t len = strlen(rawCmd);
  while (len > 0 && (rawCmd[len - 1] == ' ' || rawCmd[len - 1] == '\t')) {
    rawCmd[--len] = '\0';
  }
  if (len == 0) return;

  #if DEBUG_SERIAL >= 2
    Serial.print(F("[BLE RX] "));
    Serial.println(rawCmd);
  #endif

  if (strcmp(rawCmd, "I?") == 0) {
    sendBoardInfo();
    return;
  }
  if (strcmp(rawCmd, "T?") == 0) {
    sendTelemetry();
    return;
  }
  if (strcmp(rawCmd, "X") == 0 || strcmp(rawCmd, "STOP") == 0) {
    stopAllOutputs();
    sendBleLineF(F("OK:STOP"));
    return;
  }

  // Format attendu : <TYPE>:<ARGS>
  if (len >= 3 && rawCmd[1] == ':') {
    char type = (char)toupper((unsigned char)rawCmd[0]);
    char* firstArg = rawCmd + 2;

    if (type == 'M') {
      applyBatchCommand(firstArg);
      return;
    }

    char* secondColon = strchr(firstArg, ':');

    if (type == 'R' && secondColon == nullptr) {
      readDigitalPin(atoi(firstArg));
      return;
    }

    if (secondColon != nullptr && secondColon > firstArg && *(secondColon + 1) != '\0') {
      int pin = atoi(firstArg);
      int val = atoi(secondColon + 1);

      if (type == 'D') {
        applyDigitalOutput(pin, val);
        return;
      } else if (type == 'P') {
        applyPwmOutput(pin, val);
        return;
      } else if (type == 'V') {
        applyServoOutput(pin, val);
        return;
      }
    }
  }

  handleCustomCommand(rawCmd);
}

// ============================================================================
// 9. SETUP & LOOP
// ============================================================================

void setup() {
  Serial.begin(115200);
  // Courte attente pour USB CDC natif (Uno R4, Nano 33 BLE), sans bloquer si non branché
  unsigned long waitStart = millis();
  while (!Serial && (millis() - waitStart < 1200)) {
    delay(10);
  }

  for (int i = 0; i <= MAX_PIN_INDEX; i++) {
    pinSlotMap[i] = -1;
  }
  for (int i = 0; i < MAX_MANAGED_PINS; i++) {
    managedPins[i].pin = -1;
    managedPins[i].role = ROLE_NONE;
    managedPins[i].lastValue = -1;
    managedPins[i].servoSlot = -1;
  }
  for (int s = 0; s < MAX_SERVOS; s++) {
    #if defined(BLE_MODE_ESP32)
      espLedcSlotUsed[s] = false;
    #else
      servoSlotUsed[s] = false;
    #endif
  }

  initBleTransport();

  Serial.println(F("========================================"));
  Serial.print(F("Carte détectée : "));
  Serial.println(F(BOARD_ID_STR));
  Serial.print(F("Nom BLE        : "));
  Serial.println(F(DEVICE_NAME));
  Serial.println(F("En attente de connexion iPhone..."));
  Serial.println(F("========================================"));
}

void loop() {
  pollBleTransport();

  if (pendingDisconnectCleanup) {
    pendingDisconnectCleanup = false;
    stopAllOutputs();
    Serial.println(F("[BLE] Déconnecté -> arrêt de sécurité des sorties."));
  }

  if (bleClientConnected && !wasConnected) {
    wasConnected = true;
    Serial.println(F("[BLE] Client iOS connecté."));
  } else if (!bleClientConnected && wasConnected) {
    wasConnected = false;
  }

  // Envoi périodique de la télémétrie
  unsigned long now = millis();
  if (bleClientConnected && (now - lastTelemetryMs >= TELEMETRY_INTERVAL_MS)) {
    lastTelemetryMs = now;
    sendTelemetry();
  }
}
