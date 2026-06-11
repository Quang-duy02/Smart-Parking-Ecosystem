/**
 * @file Node1_SensorProcessing.ino
 * @brief Node 1: Sensor Node (Trang bị Bộ Lọc Trung Vị Median Filter chống nhiễu tuyệt đối)
 */

#include <Arduino.h>
#include <ArduinoJson.h>

#define NUM_SLOTS 4

// HC-SR04 Pins
const uint8_t TRIG_PINS[NUM_SLOTS] = {13, 25, 27, 32};
const uint8_t ECHO_PINS[NUM_SLOTS] = {12, 26, 14, 33};

// LED Indicator Pins
const uint8_t LED_GREEN[NUM_SLOTS]  = {15, 21, 4, 22};
const uint8_t LED_YELLOW[NUM_SLOTS] = {2, 19, 5, 23};

// Tùy chỉnh cho mô hình thu nhỏ
const float DISTANCE_THRESHOLD_CM = 5.0f;        // Tăng lên 5cm để dễ nhận tay hơn
const unsigned long STABILITY_TIMEOUT_MS = 3000; // Giữ tay 3 giây để xác nhận

struct ParkingSlot {
    float currentDistance = 999.0f;
    bool isOccupied = false;
    bool isReserved = false; 
    
    unsigned long consecutiveDetectTime = 0;
    unsigned long consecutiveClearTime = 0;
    unsigned long vehicleEntryMillis = 0;
};

ParkingSlot slots[NUM_SLOTS];
unsigned long lastSensorPoll = 0;

void dispatchEventToNode2(uint8_t slotIndex, const char* eventType, unsigned long durationMs = 0);
float getMedianDistance(uint8_t slotIndex); // Khai báo hàm lọc nhiễu

void setup() {
    Serial.begin(115200);   
    Serial2.begin(115200, SERIAL_8N1, 16, 17);  

    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        pinMode(TRIG_PINS[i], OUTPUT);
        pinMode(ECHO_PINS[i], INPUT);
        digitalWrite(TRIG_PINS[i], LOW);
        
        pinMode(LED_GREEN[i], OUTPUT);
        pinMode(LED_YELLOW[i], OUTPUT);
    }
    
    Serial.println("[NODE 1] Realtime Processing Node Initialized (MEDIAN FILTER).");
}

void loop() {
    unsigned long currentMillis = millis();

    // 1. Quét cảm biến (Chạy qua Bộ lọc Trung vị)
    if (currentMillis - lastSensorPoll >= 100) {
        for (uint8_t i = 0; i < NUM_SLOTS; i++) {
            slots[i].currentDistance = getMedianDistance(i);
        }
        lastSensorPoll = currentMillis;
    }

    // 2. Chạy thuật toán bắt xe (State Machine)
    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        float dist = slots[i].currentDistance;

        if (dist > 0.0f && dist <= DISTANCE_THRESHOLD_CM) {
            slots[i].consecutiveClearTime = 0; 
            if (slots[i].consecutiveDetectTime == 0) slots[i].consecutiveDetectTime = currentMillis;

            if (!slots[i].isOccupied && (currentMillis - slots[i].consecutiveDetectTime >= STABILITY_TIMEOUT_MS)) {
                slots[i].isOccupied = true;
                slots[i].vehicleEntryMillis = currentMillis; 
                Serial.printf(">>> [SLOT %d] CÓ XE VÀO! <<<\n", i + 1);
                dispatchEventToNode2(i, "vehicle_entry"); 
            }
        } else {
            slots[i].consecutiveDetectTime = 0; 
            if (slots[i].consecutiveClearTime == 0) slots[i].consecutiveClearTime = currentMillis;

            if (slots[i].isOccupied && (currentMillis - slots[i].consecutiveClearTime >= STABILITY_TIMEOUT_MS)) {
                slots[i].isOccupied = false;
                unsigned long parkingDurationMs = currentMillis - slots[i].vehicleEntryMillis;
                Serial.printf("<<< [SLOT %d] XE ĐÃ RỜI ĐI! <<<\n", i + 1);
                dispatchEventToNode2(i, "vehicle_exit", parkingDurationMs);
            }
        }
    }

    // 3. Cập nhật đèn LED
    for (uint8_t i = 0; i < NUM_SLOTS; i++) {
        if (slots[i].isOccupied) {
            digitalWrite(LED_GREEN[i], LOW); digitalWrite(LED_YELLOW[i], LOW);
        } else if (slots[i].isReserved) {
            digitalWrite(LED_GREEN[i], LOW); digitalWrite(LED_YELLOW[i], HIGH);
        } else {
            digitalWrite(LED_GREEN[i], HIGH); digitalWrite(LED_YELLOW[i], LOW);
        }
    }

    // 4. Nhận lệnh Firebase từ Node 2
    if (Serial2.available()) {
        StaticJsonDocument<256> doc;
        DeserializationError err = deserializeJson(doc, Serial2);
        if (!err && doc.containsKey("slot")) {
            uint8_t slotIdx = doc["slot"].as<uint8_t>() - 1;
            if (slotIdx < NUM_SLOTS && doc.containsKey("reserved")) {
                slots[slotIdx].isReserved = doc["reserved"].as<bool>();
            }
        }
    }

    // 5. MẮT THẦN (IN RA MÀN HÌNH ĐÃ LỌC NHIỄU)
    static unsigned long lastPrint = 0;
    if (currentMillis - lastPrint > 1000) {
        Serial.printf("KC1: %5.1fcm | KC2: %5.1fcm | KC3: %5.1fcm | KC4: %5.1fcm\n", 
                      slots[0].currentDistance, slots[1].currentDistance, 
                      slots[2].currentDistance, slots[3].currentDistance);
        lastPrint = currentMillis;
    }
}

// ======================================================================
// THUẬT TOÁN LỌC NHIỄU TRUNG VỊ (MEDIAN FILTER)
// ======================================================================
float getMedianDistance(uint8_t slotIndex) {
    float samples[3];
    
    // Bắn 3 lần liên tiếp
    for (int k = 0; k < 3; k++) {
        digitalWrite(TRIG_PINS[slotIndex], LOW);
        delayMicroseconds(2);
        digitalWrite(TRIG_PINS[slotIndex], HIGH);
        delayMicroseconds(10);
        digitalWrite(TRIG_PINS[slotIndex], LOW);

        // Timeout 15000us ~ tối đa 2.5 mét để chống treo mạch
        long duration = pulseIn(ECHO_PINS[slotIndex], HIGH, 15000);
        
        if (duration > 0) {
            samples[k] = duration * 0.0343f / 2.0f;
        } else {
            samples[k] = 999.0f; // Bị lỗi hoặc xa quá
        }
        
        // TRỄ TIÊU ÂM: Bắt buộc đợi 15ms để sóng âm của lần bắn trước tan hết
        delay(15); 
    }

    // Thuật toán sắp xếp nổi bọt (Bubble Sort) đơn giản cho 3 phần tử
    if (samples[0] > samples[1]) { float temp = samples[0]; samples[0] = samples[1]; samples[1] = temp; }
    if (samples[1] > samples[2]) { float temp = samples[1]; samples[1] = samples[2]; samples[2] = temp; }
    if (samples[0] > samples[1]) { float temp = samples[0]; samples[0] = samples[1]; samples[1] = temp; }

    // Trả về giá trị ở GIỮA (Loại bỏ giá trị rác quá lớn hoặc quá nhỏ)
    return samples[1];
}

void dispatchEventToNode2(uint8_t slotIndex, const char* eventType, unsigned long durationMs) {
    StaticJsonDocument<256> doc;
    doc["slot"] = slotIndex + 1;
    doc["event"] = eventType;
    if (strcmp(eventType, "vehicle_exit") == 0) {
        doc["duration_ms"] = durationMs;
    }
    serializeJson(doc, Serial2);
    Serial2.println(); 
}
