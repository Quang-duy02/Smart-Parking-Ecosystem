# 🅿️ Smart Parking Ecosystem (Enterprise-Grade)

An end-to-end, highly resilient IoT Smart Parking System built with **Dual-Node ESP32 Edge Computing**, **Firebase Realtime Database**, and a **Cross-platform Flutter Super App**. This project is designed to solve real-world commercial parking challenges, including Network Failures, Tailgating, and Reservation Thefts.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![C++](https://img.shields.io/badge/C++-00599C?style=for-the-badge&logo=c%2B%2B&logoColor=white)
![ESP32](https://img.shields.io/badge/ESP32-E7352C?style=for-the-badge&logo=espressif&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)

---

## 🌟 Key Features & Innovations

### 1. Dual-Node Distributed Architecture (Hardware)
- **Node 1 (Sensor Hub):** Handles acoustic Time-of-Flight (ToF) calculations from 4 Ultrasonic sensors. Applies **Median Filtering** and **Debouncing (3s)** to eliminate 100% of "ghost vehicle" detections caused by noise.
- **Node 2 (Cloud Gateway):** Handles Firebase atomic transactions, Servo barrier controls, and I2C LCD interfacing.

### 2. High Availability (HA) & Disaster Recovery
- **Dual-WiFi Failover:** Automatically switches to a 4G backup network when the primary optical fiber network fails. 
- **Offline Billing Engine:** During network outages, the system computes parking durations using internal RAM and `millis()`. Bills are safely stored and instantly pushed to Firebase once the network recovers, preventing revenue loss.

### 3. Anti-Fraud & Security Mechanisms
- **Global Exit Lock:** Cross-checks the entire parking lot status before opening the exit barrier. Rejects exit if an unpaid vehicle attempts to swap spots with a paid one.
- **Anti-Tailgating:** The exit barrier drops immediately after the IR sensor detects the vehicle's rear bumper, physically preventing following cars from sneaking out.
- **Single-Entry Interlock:** Rejects any vehicle entering a slot if the Entry Gate was not legitimately opened within the last 45 seconds.

### 4. Smart App Operations (Flutter)
- **Automated Buffer Slot Transfer:** If a reserved slot is physically stolen by a walk-in vehicle, the app instantly notifies the user and migrates their reservation to a hidden "Buffer Slot" (Slot 4).
- **Time-Scaling Simulation:** Specifically configured for rapid demonstrations (10 real-time seconds = 1 simulated hour of parking).

---

## 🏗️ System Architecture
<img width="531" height="263" alt="image" src="https://github.com/user-attachments/assets/bbf38edc-5422-4a01-96ee-ecb3df7639b8" />
<img width="621" height="896" alt="Screenshot 2026-06-09 145314" src="https://github.com/user-attachments/assets/a3522d9c-2ddf-4606-8140-84c980ab0c15" />
<img width="624" height="900" alt="Screenshot 2026-06-09 145251" src="https://github.com/user-attachments/assets/439848e4-a853-41e2-8ea8-79a82dcb8c33" />
<img width="626" height="902" alt="Screenshot 2026-06-09 145218" src="https://github.com/user-attachments/assets/225410f6-8bb8-4c79-8f04-dafbfb9ae0e7" />
<img width="622" height="901" alt="Screenshot 2026-06-09 225555" src="https://github.com/user-attachments/assets/28da15fb-1a51-40de-8f25-d40b2a908044" />

## 🚀 Technologies Used
* **Frontend:** Flutter, Dart, flutter_map (OSM), geolocator.
* **Backend/Cloud:** Firebase Realtime Database (Anonymous Auth & Email Auth), JSON Atomic Transactions.
* **Embedded Software:** C/C++, Arduino IDE, ESP32Servo, LiquidCrystal_I2C.
* **Hardware:** 2x ESP32 DevKit, 4x HC-SR04, 2x IR Sensors, 2x SG90 Servos, I2C LCD 1602.
