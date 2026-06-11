/**
 * @file Node2_CloudApplication.ino
 * @brief MASTER FILE - NODE 2 (Phiên bản Hoàn Hảo & Ổn định nhất)
 * - Mạng dự phòng (Dual WiFi Failover & Failback)
 * - Chống trốn vé (Global Lock), Chống nối đuôi (Anti-tailgating)
 * - Tự động Hủy lịch (Auto Cancel), Báo xe lạ cướp chỗ (Anti-Theft)
 * - Đóng gói dữ liệu JSON 100% chống rớt gói tin
 */

#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <ArduinoJson.h>
#include <time.h>
#include <ESP32Servo.h> 
#include <Wire.h> 
#include <LiquidCrystal_I2C.h>

#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// ================= CẤU HÌNH WIFI & FIREBASE =================
#define WIFI_SSID_1 "YOUR_WIFI_SSID_HERE"
#define WIFI_PASSWORD_1 "YOUR_WIFI_PASSWORD_HERE"

#define WIFI_SSID_2 "YOUR_WIFI_SSID_HERE"
#define WIFI_PASSWORD_2 "YOUR_WIFI_PASSWORD_HERE"

bool isUsingBackupWifi = false; 
unsigned long backupNetworkStartTime = 0;

#define API_KEY "AIzaSyBLYqmYKLz0Y0Dm1gfrqxBN2jsNxxxxxxx"
#define DATABASE_URL "https://xxx-default-rtdb.asia-southeast1.firebasedatabase.app" 

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
bool signupOK = false;

// ================= CẤU HÌNH PHẦN CỨNG =================
#define NUM_SLOTS 4
const uint8_t LED_RED[NUM_SLOTS] = {25, 26, 27, 32}; 

const uint8_t SERVO_ENTRY_PIN = 19; 
const uint8_t SERVO_EXIT_PIN  = 13; 
const uint8_t IR_ENTRY_SENSOR = 4;  
const uint8_t IR_EXIT_SENSOR  = 23; 

LiquidCrystal_I2C lcd(0x27, 16, 2); 
String currentLine1 = "";
String currentLine2 = "";
unsigned long lastScrollTime = 0;
int scrollIndex1 = 0;
int scrollIndex2 = 0;

Servo entryGate;
Servo exitGate;

// ================= BIẾN HỆ THỐNG & LOGIC =================
const unsigned long FIREBASE_SYNC_INTERVAL_MS = 3000; 
const unsigned long RESERVATION_TIMEOUT_SEC = 45; // DEMO: 15 giây hủy lịch
unsigned long lastFirebaseSync = 0;
unsigned long lastValidEntryGateTime = 0; 
bool isWaitingForApp = false;
unsigned long carAtGateTimeout = 0;

struct CloudSlot {
    bool isOccupied = false;
    bool isReserved = false;
    long expectedDurationSec = 0; 
    long actualEntryTime = 0;     
    long bookingStartTime = 0; 
    
    // Lưu hóa đơn khi đứt mạng
    bool hasOfflineBill = false;
    String offlinePaymentStatus = "none";
    long offlineTransactionAmount = 0;
    long offlineTimeDiff = 0; 
};
CloudSlot cloudSlots[NUM_SLOTS];

// ================= PROTOTYPES =================
void initWiFi();
void initFirebase();
void initNTP();
unsigned long getEpochTime();
void handleIncomingUART();
void processVehicleEntry(uint8_t slotIdx);
void processVehicleExit(uint8_t slotIdx, unsigned long durationMs);
void syncFirebaseToLocal();
void dispatchSyncToNode1(uint8_t slotIdx);
void updateRedLEDs();
void calculateBillingAndCheckout(uint8_t slotIdx, unsigned long exitTime, unsigned long durationMs);
void checkEntryGate();
bool processSmartExitGate(uint8_t currentSlotIdx);
bool checkGlobalUnpaidSlots(uint8_t paidSlotIdx); 
void enforceReservationTimeouts();
void enforceAntiTheft();   
void displayLCD(String line1, String line2); 
void updateLCDScrolling();  
bool isParkingFull();

// ================= SETUP =================
void setup() {
    Serial.begin(115200);
    delay(2000); 
    Serial.println("\n=== HỆ THỐNG NODE 2 (MASTER VERSION) ===");

    Serial2.begin(115200, SERIAL_8N1, 16, 17);

    lcd.init();
    lcd.backlight();
    displayLCD("He Thong Bai Do", "Dang khoi dong...");

    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        pinMode(LED_RED[i], OUTPUT);
        digitalWrite(LED_RED[i], LOW);
    }
    pinMode(IR_ENTRY_SENSOR, INPUT_PULLUP);
    pinMode(IR_EXIT_SENSOR, INPUT_PULLUP); 

    ESP32PWM::allocateTimer(0);
    ESP32PWM::allocateTimer(1);
    entryGate.setPeriodHertz(50);
    exitGate.setPeriodHertz(50);
    entryGate.attach(SERVO_ENTRY_PIN, 500, 2400);
    exitGate.attach(SERVO_EXIT_PIN, 500, 2400);
    entryGate.write(0); 
    exitGate.write(0);  

    initWiFi();
    initNTP();
    delay(1000); 
    initFirebase();
    
    displayLCD("SMART PARKING", "Cam On Quy Khach");
    Serial.println("=== KHOI DONG HOAN TAT ===");
}

// ================= MAIN LOOP =================
void loop() {
    unsigned long currentMillis = millis();
    
    handleIncomingUART();
    checkEntryGate();
    enforceReservationTimeouts();
    updateLCDScrolling(); 

    if (currentMillis - lastFirebaseSync >= FIREBASE_SYNC_INTERVAL_MS) {
        lastFirebaseSync = currentMillis;
        syncFirebaseToLocal();
    }
}

// ================= HÀM LCD =================
void displayLCD(String line1, String line2) {
    if (line1 != currentLine1 || line2 != currentLine2) {
        currentLine1 = line1;
        currentLine2 = line2;
        scrollIndex1 = 0; 
        scrollIndex2 = 0;
        lcd.clear(); 
        lcd.setCursor(0, 0);
        lcd.print(line1.substring(0, 16));
        lcd.setCursor(0, 1);
        lcd.print(line2.substring(0, 16));
    }
}

void updateLCDScrolling() {
    if (currentLine1.length() <= 16 && currentLine2.length() <= 16) return;
    unsigned long currentMillis = millis();
    if (currentMillis - lastScrollTime >= 400) {
        lastScrollTime = currentMillis;
        lcd.setCursor(0, 0);
        if (currentLine1.length() <= 16) { lcd.print(currentLine1); } 
        else {
            String displayStr = currentLine1.substring(scrollIndex1) + "   " + currentLine1.substring(0, scrollIndex1);
            lcd.print(displayStr.substring(0, 16));
            scrollIndex1++;
            if (scrollIndex1 >= currentLine1.length()) scrollIndex1 = 0; 
        }
        lcd.setCursor(0, 1);
        if (currentLine2.length() <= 16) { lcd.print(currentLine2); } 
        else {
            String displayStr = currentLine2.substring(scrollIndex2) + "   " + currentLine2.substring(0, scrollIndex2);
            lcd.print(displayStr.substring(0, 16));
            scrollIndex2++;
            if (scrollIndex2 >= currentLine2.length()) scrollIndex2 = 0; 
        }
    }
}

// ================= QUẢN LÝ CỔNG VÀO / KIỂM TRA BÃI =================
bool isParkingFull() {
    int usedSlots = 0;
    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        if (cloudSlots[i].isOccupied || cloudSlots[i].isReserved) usedSlots++;
    }
    return (usedSlots >= NUM_SLOTS);
}


void checkEntryGate() {
    // 1. NẾU ĐANG CHỜ KHÁCH BẤM APP (STATE: WAITING)
    if (isWaitingForApp) {
        static unsigned long lastCheckOverride = 0;
        if (millis() - lastCheckOverride > 1000) {
            lastCheckOverride = millis();
            
            // Đọc câu trả lời từ App
            if (Firebase.RTDB.getBool(&fbdo, "/smart_parking_system/metadata/gate_override")) {
                if (fbdo.boolData() == true) {
                    Serial.println("\n[APP LỆNH] Khach da xac nhan! MO BARIE.");
                    
                    // Reset sạch sẽ 2 cờ trên Firebase
                    FirebaseJson resetGateJson;
                    resetGateJson.set("gate_override", false);
                    resetGateJson.set("car_at_entry_gate", false);
                    Firebase.RTDB.updateNode(&fbdo, "/smart_parking_system/metadata", &resetGateJson);

                    // Mở Barie
                    entryGate.write(90); 
                    lastValidEntryGateTime = millis(); 
                    delay(3000); 
                    entryGate.write(0);
                    Serial.println("[CONG VAO] Da dong Barie.");
                    
                    isWaitingForApp = false; // Xong nhiệm vụ
                    return;
                }
            }
        }

        // NẾU XE RÚT LUI HOẶC KHÁCH LƯỜI KHÔNG BẤM APP SAU 60 GIÂY -> HỦY BỎ!
        if (digitalRead(IR_ENTRY_SENSOR) == HIGH || millis() - carAtGateTimeout > 60000) {
            Serial.println("\n[HUY YEU CAU] Xe roi di hoac qua han. Xoa co bao Dong.");
            Firebase.RTDB.setBool(&fbdo, "/smart_parking_system/metadata/car_at_entry_gate", false);
            isWaitingForApp = false;
        }
        return; // Đang chờ thì không quét cảm biến nữa
    }

    // ==============================================================
    // 2. NẾU CỔNG ĐANG RẢNH -> QUÉT CẢM BIẾN IR
    // ==============================================================
    if (digitalRead(IR_ENTRY_SENSOR) == LOW) {
        delay(50); // Chống nhiễu
        if (digitalRead(IR_ENTRY_SENSOR) == LOW) { 
            
            // TRƯỜNG HỢP A: BÃI FULL -> PHẢI GỌI APP
            if (isParkingFull()) {
                Serial.println("\n[TỪ CHỐI TỰ ĐỘNG] Bai da Full! Báo lên App chờ Xac nhan...");
                
                // Gửi cờ báo động lên Firebase cho App hiện nút
                Firebase.RTDB.setBool(&fbdo, "/smart_parking_system/metadata/car_at_entry_gate", true);
                
                // Chuyển ESP32 sang trạng thái Ngồi Chờ App
                isWaitingForApp = true;
                carAtGateTimeout = millis();
                return; 
            }

            // TRƯỜNG HỢP B: BÃI CÒN TRỐNG -> MỞ TỰ ĐỘNG CHO VÃNG LAI
            if (millis() - lastValidEntryGateTime > 5000) {
                Serial.println("\n[CONG VAO] Bai con trong. Tu dong mo Barie...");
                entryGate.write(90); 
                lastValidEntryGateTime = millis(); 
                delay(3000); 
                entryGate.write(0);
                Serial.println("[CONG VAO] Da dong Barie.");
            }
        }
    }
}

// ================= QUẢN LÝ CỔNG RA (CHỐNG TRỐN VÉ) =================
bool checkGlobalUnpaidSlots(uint8_t paidSlotIdx) {
    bool hasEvader = false;
    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        if (i == paidSlotIdx) continue; 
        String path = "/smart_parking_system/slots/slot_" + String(i + 1) + "/payment_status";
        if (Firebase.RTDB.getString(&fbdo, path)) {
            String status = fbdo.stringData();
            if (status == "pending_payment" || status == "settlement_pending" || status == "extra_charge_pending") {
                hasEvader = true;
            }
        }
    }
    return hasEvader;
}

bool processSmartExitGate(uint8_t paidSlotIdx) {
    if (checkGlobalUnpaidSlots(paidSlotIdx)) { 
        Serial.println("-> [LOI CONG RA] Co xe KHAC dang tron ve! TỪ CHỐI MỞ CỔNG!");
        displayLCD("LOI THANH TOAN!", "Co xe tron ve!"); 
        String basePath = "/smart_parking_system/slots/slot_" + String(paidSlotIdx + 1);
        Firebase.RTDB.setStringAsync(&fbdo, basePath + "/payment_status", "error_unpaid_slots");
        return false; 
    }

    Serial.println("-> [CONG RA] Mo Barie cho khach ra.");
    displayLCD("THANH TOAN OK", "Moi xe qua cong"); 
    exitGate.write(90); 
    
    unsigned long waitTimeout = millis();
    bool carPassed = false;
    while(millis() - waitTimeout < 15000) {
        if(digitalRead(IR_EXIT_SENSOR) == LOW) { 
            while(digitalRead(IR_EXIT_SENSOR) == LOW) { delay(10); yield(); }
            carPassed = true;
            break; 
        }
        delay(50); yield();
    }

    Serial.println("-> [CONG RA] Dong Barie.");
    exitGate.write(0); 
    displayLCD("SMART PARKING", "Cam On Quy Khach"); 
    return true; 
}

// ================= WIFI & FIREBASE CORE =================
void initWiFi() {
    Serial.println("\n[MANG] Khoi tao ket noi WiFi...");
    WiFi.begin(WIFI_SSID_1, WIFI_PASSWORD_1);
    Serial.print("   -> Dang thu mang CHINH: "); Serial.print(WIFI_SSID_1);
    
    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 15) { Serial.print("."); delay(500); retries++; }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println(" THAT BAI!");
        Serial.print("   -> Dang thu mang DU PHONG: "); Serial.print(WIFI_SSID_2);
        WiFi.disconnect(); 
        WiFi.begin(WIFI_SSID_2, WIFI_PASSWORD_2);
        isUsingBackupWifi = true; 
        
        retries = 0;
        while (WiFi.status() != WL_CONNECTED && retries < 15) { Serial.print("."); delay(500); retries++; }
    } else {
        isUsingBackupWifi = false;
    }

    if (WiFi.status() == WL_CONNECTED) Serial.println(" THANH CONG!");
    else Serial.println(" THAT BAI CA 2 MANG! He thong vao trang thai OFFLINE.");
}
void initNTP() { configTime(0, 0, "pool.ntp.org", "time.nist.gov"); while (time(nullptr) < 100000) { delay(500); } }
unsigned long getEpochTime() { time_t now; time(&now); return now; }
void initFirebase() { 
    config.api_key = API_KEY; 
    config.database_url = DATABASE_URL; 
    fbdo.setBSSLBufferSize(512, 512); 
    if (Firebase.signUp(&config, &auth, "", "")) signupOK = true; 
    config.token_status_callback = tokenStatusCallback; 
    Firebase.begin(&config, &auth); 
    Firebase.reconnectWiFi(true); 
}

// ================= XỬ LÝ SỰ KIỆN TỪ NODE 1 =================
void handleIncomingUART() {
    if (Serial2.available()) {
        StaticJsonDocument<256> doc;
        DeserializationError err = deserializeJson(doc, Serial2);
        if (!err && doc.containsKey("slot")) {
            uint8_t slotIdx = doc["slot"].as<uint8_t>() - 1;
            String event = doc["event"].as<String>();
            Serial.printf("=> [UART] Nhan su kien '%s' tai Slot %d\n", event.c_str(), slotIdx + 1);
            if (slotIdx < NUM_SLOTS) {
                if (event == "vehicle_entry") processVehicleEntry(slotIdx);
                else if (event == "vehicle_exit") {
                    unsigned long durationMs = doc["duration_ms"].as<unsigned long>();
                    processVehicleExit(slotIdx, durationMs);
                }
            }
        }
    }
}

void processVehicleEntry(uint8_t slotIdx) {
    if (millis() - lastValidEntryGateTime > 45000) { 
        Serial.println("   [!] Xe ma hoac khong mo cong -> Tu choi vao!");
        return; 
    }

    lastValidEntryGateTime = 0; // Chống xe ma thứ 2 chui lọt
    unsigned long entryTime = getEpochTime();
    cloudSlots[slotIdx].isOccupied = true;
    cloudSlots[slotIdx].actualEntryTime = entryTime; 
    
    String basePath = "/smart_parking_system/slots/slot_" + String(slotIdx + 1);
    
    // --- BẢN VÁ LỖI HIỂN THỊ CHỜ XÁC NHẬN ---
    // Đóng gói JSON đẩy 1 lần để chống rớt gói tin
    FirebaseJson json;
    json.set("occupied", true);
    json.set("actual_entry_time", entryTime);
    
    if (cloudSlots[slotIdx].isReserved) {
        json.set("payment_status", "awaiting_checkin");
        Serial.println("   [+] Xe vao o Da Dat -> Cho App xac nhan Check-in.");
    } else {
        json.set("payment_status", "walkin_active");
        Serial.println("   [+] Xe vang lai -> Bat dau do xe.");
    }
    
    Firebase.RTDB.updateNode(&fbdo, basePath, &json);
    updateRedLEDs();
}

void processVehicleExit(uint8_t slotIdx, unsigned long durationMs) {
    if (cloudSlots[slotIdx].isOccupied == false) {
        Serial.println("   [!] Phat hien lenh Exit rac (Xe chua vao hoac bi tu choi). Bo qua!");
        return; 
    }

    unsigned long exitTime = getEpochTime();
    cloudSlots[slotIdx].isOccupied = false;
    
    String basePath = "/smart_parking_system/slots/slot_" + String(slotIdx + 1);
    
    FirebaseJson json;
    json.set("occupied", false);
    json.set("reserved", false);
    json.set("actual_exit_time", exitTime);
    Firebase.RTDB.updateNode(&fbdo, basePath, &json);

    Serial.println("   [-] Xe roi di -> Bat dau tinh tien...");
    calculateBillingAndCheckout(slotIdx, exitTime, durationMs); 

    cloudSlots[slotIdx].isReserved = false; 
    cloudSlots[slotIdx].expectedDurationSec = 0; 
    cloudSlots[slotIdx].bookingStartTime = 0;
    
    dispatchSyncToNode1(slotIdx);
    updateRedLEDs();
}

void calculateBillingAndCheckout(uint8_t slotIdx, unsigned long exitTime, unsigned long durationMs) {
    String basePath = "/smart_parking_system/slots/slot_" + String(slotIdx + 1);
    
    long actualRealDurationSec = durationMs / 1000;
    const int TIME_SCALE_FACTOR = 360; 
    long simulatedDurationSec = actualRealDurationSec * TIME_SCALE_FACTOR;
    long expectedDurationSec = cloudSlots[slotIdx].expectedDurationSec;

    const long BASE_PRICE_PER_HOUR = 20000; 
    float pricePerSecond = (float)BASE_PRICE_PER_HOUR / 3600.0; 
    long transactionAmount = 0; 
    long timeDifference = 0; 
    String billingAction;
    
    if (expectedDurationSec <= 0) {
        transactionAmount = simulatedDurationSec * pricePerSecond;
        billingAction = "pending_payment";
        displayLCD("Vui long thanh", "toan tren App"); 
        Serial.printf("       [Hoa don] Vang lai. Thu: %ld VND\n", transactionAmount);
    } else {
        timeDifference = simulatedDurationSec - expectedDurationSec; 
        const long TOLERANCE_SEC = 900; 

        if (abs(timeDifference) <= TOLERANCE_SEC) transactionAmount = 0;
        else transactionAmount = timeDifference * pricePerSecond;
        
        billingAction = "settlement_pending";
        displayLCD("Vui long thanh", "toan tren App"); 
        Serial.printf("       [Hoa don] App User. Leech: %ld VND\n", transactionAmount);
    }

    if (WiFi.status() == WL_CONNECTED && Firebase.ready()) {
        FirebaseJson json;
        json.set("payment_status", billingAction);
        json.set("time_diff_sec", timeDifference); 
        json.set("transaction_amount", transactionAmount);
        Firebase.RTDB.updateNode(&fbdo, basePath, &json);
    } else {
        Serial.println("       [OFFLINE] Mang bi ngat. Da luu tam hoa don vao bo nho!");
        cloudSlots[slotIdx].hasOfflineBill = true;
        cloudSlots[slotIdx].offlinePaymentStatus = billingAction;
        cloudSlots[slotIdx].offlineTransactionAmount = transactionAmount;
        cloudSlots[slotIdx].offlineTimeDiff = timeDifference; 
    }
}

// ================= KIỂM SOÁT THỜI GIAN & CƯỚP CHỖ =================
void enforceReservationTimeouts() {
    unsigned long currentTime = getEpochTime();
    if (currentTime < 300000) return; 

    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        if (cloudSlots[i].isReserved && !cloudSlots[i].isOccupied) {
            if (cloudSlots[i].bookingStartTime > 0 && 
               (currentTime - cloudSlots[i].bookingStartTime >= RESERVATION_TIMEOUT_SEC)) {
                
                Serial.printf("\n[TIMEOUT] Slot %d qua han 45s. Huy lich!\n", i + 1);
                String basePath = "/smart_parking_system/slots/slot_" + String(i + 1);
                
                cloudSlots[i].isReserved = false;
                cloudSlots[i].bookingStartTime = 0;
                cloudSlots[i].expectedDurationSec = 0;

                FirebaseJson cleanJson;
                cleanJson.set("payment_status", "none");
                cleanJson.set("reserved", false);
                cleanJson.set("expected_duration", 0);
                cleanJson.set("booking_start_time", 0);
                cleanJson.set("user_id", ""); 
                
                Firebase.RTDB.updateNode(&fbdo, basePath, &cleanJson);
                dispatchSyncToNode1(i);
            }
        }
    }
}

void enforceAntiTheft() {
    for (uint8_t i = 0; i < 3; i++) { // Chỉ kiểm tra Slot 1, 2, 3
        String path = "/smart_parking_system/slots/slot_" + String(i + 1) + "/payment_status";
        if (Firebase.RTDB.getString(&fbdo, path)) {
            String status = fbdo.stringData();
            
            // NẾU CÓ XE LẠ ĐỖ VÀO MÀ 30 GIÂY KHÔNG CHECK-IN!
            if (status == "awaiting_checkin" && (getEpochTime() - cloudSlots[i].actualEntryTime > 30)) {
                Serial.printf("\n[CUOP CHO] Phat hien xe la chiem dung Slot %d!\n", i + 1);
                
                String stolenPath = "/smart_parking_system/slots/slot_" + String(i + 1);
                String bufferPath = "/smart_parking_system/slots/slot_4";
                
                // 1. KÉO TOÀN BỘ DỮ LIỆU CỦA KHÁCH A (BỊ CƯỚP) VỀ TẠM
                String stolenUserId = "";
                long stolenDuration = 0;
                long stolenStartTime = 0;
                
                if (Firebase.RTDB.getString(&fbdo, stolenPath + "/user_id")) stolenUserId = fbdo.stringData();
                if (Firebase.RTDB.getInt(&fbdo, stolenPath + "/expected_duration")) stolenDuration = fbdo.intData();
                if (Firebase.RTDB.getInt(&fbdo, stolenPath + "/booking_start_time")) stolenStartTime = fbdo.intData();
                
                // 2. NHÉT TOÀN BỘ DỮ LIỆU CỦA KHÁCH A SANG SLOT 4 (Ô DỰ PHÒNG)
                FirebaseJson bufferJson;
                bufferJson.set("occupied", false);
                bufferJson.set("reserved", true);
                bufferJson.set("payment_status", "buffer_activate_request"); // Báo cờ để App rung lên cảnh báo khách
                bufferJson.set("user_id", stolenUserId);
                bufferJson.set("expected_duration", stolenDuration);
                bufferJson.set("booking_start_time", stolenStartTime); // Chuyển luôn cả giờ đặt để ko bị phạt oan
                
                Firebase.RTDB.updateNode(&fbdo, bufferPath, &bufferJson);
                Serial.println("   -> Da bốc toan bo thong tin Khach A sang Slot 4.");
                
                // 3. BIẾN SLOT BỊ CƯỚP THÀNH CỦA XE VÃNG LAI (XÓA SẠCH VẾT TÍCH KHÁCH A)
                FirebaseJson stolenJson;
                stolenJson.set("payment_status", "walkin_active");
                stolenJson.set("reserved", false);
                stolenJson.set("user_id", ""); // Xóa tên khách A
                stolenJson.set("expected_duration", 0); // Vãng lai đỗ tự do
                stolenJson.set("booking_start_time", 0);
                
                Firebase.RTDB.updateNode(&fbdo, stolenPath, &stolenJson);
                Serial.printf("   -> Da chuyen Slot %d thanh bai do cho xe Vang Lai.\n", i + 1);
            }
        }
    }
}

// ================= ĐỒNG BỘ ĐÁM MÂY =================
void syncFirebaseToLocal() {
    if (isUsingBackupWifi && WiFi.status() == WL_CONNECTED) {
        if (millis() - backupNetworkStartTime > 60000) {
            Serial.println("\n[MANG] Da xai 4G 1 phut. Ngat ket noi de do tim Mang Chinh...");
            WiFi.disconnect(true); 
            delay(1000); 
            isUsingBackupWifi = false; 
            signupOK = false;
            return;
        }
    }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("\n[BAO DONG] MAT KET NOI WIFI! He thong hoat dong OFFLINE.");
        WiFi.disconnect(true); 
        delay(500);
        WiFi.mode(WIFI_STA); 

        if (!isUsingBackupWifi) {
            Serial.printf("   -> Dang ket noi Mang Chinh: %s ", WIFI_SSID_1);
            WiFi.begin(WIFI_SSID_1, WIFI_PASSWORD_1);
            int retries = 0;
            while (WiFi.status() != WL_CONNECTED && retries < 15) { delay(500); Serial.print("."); retries++; }
            Serial.println(); 
            if (WiFi.status() != WL_CONNECTED) {
                Serial.println("   -> Mang Chinh khong phan hoi! Chuyen co sang Du Phong.");
                isUsingBackupWifi = true;
            }
        } else {
            Serial.printf("   -> Dang ket noi Mang Du Phong: %s ", WIFI_SSID_2);
            WiFi.begin(WIFI_SSID_2, WIFI_PASSWORD_2);
            backupNetworkStartTime = millis(); 
            int retries = 0;
            while (WiFi.status() != WL_CONNECTED && retries < 15) { delay(500); Serial.print("."); retries++; }
            Serial.println();
            if (WiFi.status() != WL_CONNECTED) {
                Serial.println("   -> Mang Du Phong cung chet! Chuyen co ve Mang Chinh do lai.");
                isUsingBackupWifi = false; 
            }
        }
        signupOK = false; 
        return; 
    }

    if (WiFi.status() == WL_CONNECTED && !signupOK) {
        Serial.printf("\n[MANG] KET NOI THANH CONG (%s). Dang vao Firebase...\n", isUsingBackupWifi ? "4G Du Phong" : "Cap Quang Chinh");
        if (Firebase.signUp(&config, &auth, "", "")) {
            Serial.println("   -> Firebase OK! Dang dong bo hoa don Offline...");
            signupOK = true;
            
            for (uint8_t i = 0; i < NUM_SLOTS; i++) {
                String basePath = "/smart_parking_system/slots/slot_" + String(i + 1);
                FirebaseJson json;
                bool needUpdate = false;

                json.set("occupied", cloudSlots[i].isOccupied);
                needUpdate = true;

                if (cloudSlots[i].hasOfflineBill) {
                    json.set("payment_status", cloudSlots[i].offlinePaymentStatus);
                    json.set("transaction_amount", cloudSlots[i].offlineTransactionAmount);
                    json.set("time_diff_sec", cloudSlots[i].offlineTimeDiff); 
                    json.set("reserved", false); 
                    
                    Serial.printf("   -> [KHOI PHUC] Da day hoa don %ld VND cua Slot %d len mang!\n", cloudSlots[i].offlineTransactionAmount, i + 1);
                    cloudSlots[i].hasOfflineBill = false; 
                }

                if (needUpdate) {
                    Firebase.RTDB.updateNode(&fbdo, basePath, &json);
                }
            }
        } else {
            Serial.printf("   -> LOI FIREBASE: %s\n", config.signer.signupError.message.c_str());
            return;
        }
    }

    if (Firebase.ready() && signupOK) {
        for (uint8_t i = 0; i < NUM_SLOTS; i++) {
            String basePath = "/smart_parking_system/slots/slot_" + String(i + 1);
            
            if (Firebase.RTDB.getBool(&fbdo, basePath + "/reserved")) {
                bool isRes = fbdo.boolData();
                if (isRes != cloudSlots[i].isReserved) {
                    cloudSlots[i].isReserved = isRes;
                    if (isRes) {
                        cloudSlots[i].bookingStartTime = getEpochTime();
                        if (Firebase.RTDB.getInt(&fbdo, basePath + "/expected_duration")) {
                            cloudSlots[i].expectedDurationSec = fbdo.intData();
                        }
                    } else {
                        cloudSlots[i].bookingStartTime = 0;
                    }
                    dispatchSyncToNode1(i);
                }
            }

            if (Firebase.RTDB.getString(&fbdo, basePath + "/payment_status")) {
                String status = fbdo.stringData();
                
                // 1. NẾU APP BÁO ĐÃ THANH TOÁN
                if (status == "paid") {
                    Serial.printf("\n[THANH TOAN] Nhan lenh PAID cho Slot %d!\n", i + 1);
                    
                    if (processSmartExitGate(i) == true) { 
                        FirebaseJson cleanJson;
                        cleanJson.set("occupied", false); 
                        cleanJson.set("payment_status", "none");
                        cleanJson.set("reserved", false);
                        cleanJson.set("transaction_amount", 0);
                        cleanJson.set("expected_duration", 0);
                        cleanJson.set("time_diff_sec", 0);
                        cleanJson.set("booking_start_time", 0);
                        cleanJson.set("user_id", ""); 
                        
                        Firebase.RTDB.updateNode(&fbdo, basePath, &cleanJson);
                        Serial.println("  -> Da xoa sach lich su Firebase.");
                    } else {
                        Serial.println("  -> [HUY XOA] Cong chua mo, giu nguyen du lieu de xu ly phat!");
                        cloudSlots[i].isReserved = false; 
                    }
                }
                
                // ==============================================================
                // 2. VÁ LỖI XUNG ĐỘT KHI KHÁCH ẤN NÚT "BÁO XE LẠ" TRÊN APP
                // Nếu Firebase bị App ép thành "walkin_active", ESP32 phải 
                // tự giác quên hết thông tin của khách cũ!
                // ==============================================================
                else if (status == "walkin_active") {
                    if (cloudSlots[i].expectedDurationSec > 0 || cloudSlots[i].isReserved == true) {
                        Serial.printf("   [DONG BO NGAY] App vua bao co Xe La tai Slot %d. Xoa du lieu Khach A!\n", i + 1);
                        cloudSlots[i].isReserved = false;
                        cloudSlots[i].expectedDurationSec = 0;
                        cloudSlots[i].bookingStartTime = 0;
                        dispatchSyncToNode1(i); // Báo Node 1 tắt đèn vàng ngay lập tức
                    }
                }
            }
        }
        enforceAntiTheft();
    }
}

void dispatchSyncToNode1(uint8_t slotIdx) {
    StaticJsonDocument<128> doc;
    doc["slot"] = slotIdx + 1;
    doc["reserved"] = cloudSlots[slotIdx].isReserved;
    serializeJson(doc, Serial2);
    Serial2.println();
}

void updateRedLEDs() {
    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        if (cloudSlots[i].isOccupied && cloudSlots[i].isReserved == false) {
            digitalWrite(LED_RED[i], HIGH);
        } else {
            digitalWrite(LED_RED[i], LOW); 
        }
    }
}
