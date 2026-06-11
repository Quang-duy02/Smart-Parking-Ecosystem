import 'package:firebase_database/firebase_database.dart';
import '../models/parking_lot.dart';
import '../models/parking_spot.dart';

class ApiService {
  Future<List<ParkingLot>> getParkingLots() async {
    await Future.delayed(const Duration(milliseconds: 500));

    return const [
      ParkingLot(
        id: 1,
        name: 'Bãi đỗ Cầu Giấy',
        address: '144 Xuân Thủy, Cầu Giấy, Hà Nội',
        totalSpots: 4,
        availableSpots: 3,
        pricePerHour: 20000, // Đồng bộ giá 20k/giờ theo yêu cầu
        latitude: 21.0368,
        longitude: 105.7823,
      ),
      ParkingLot(
        id: 2,
        name: 'Bãi đỗ Mỹ Đình',
        address: 'Nam Từ Liêm, Hà Nội',
        totalSpots: 60,
        availableSpots: 25,
        pricePerHour: 20000, // Đồng bộ giá 20k/giờ theo yêu cầu
        latitude: 21.0285,
        longitude: 105.7782,
      ),
      ParkingLot(
        id: 3,
        name: 'Bãi đỗ Hoàn Kiếm',
        address: 'Tràng Tiền, Hoàn Kiếm, Hà Nội',
        totalSpots: 30,
        availableSpots: 5,
        pricePerHour: 20000, // Đồng bộ giá 20k/giờ theo yêu cầu
        latitude: 21.0245,
        longitude: 105.8572,
      ),
    ];
  }

  Future<List<ParkingSpot>> getParkingSpots(int parkingLotId) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final occupiedIds = [2, 8, 16];
    final reservedIds = [5, 11];
    final violationIds = [20];

    return List.generate(24, (index) {
      final spotId = index + 1;

      ParkingSpotStatus status = ParkingSpotStatus.available;
      if (violationIds.contains(spotId)) {
        status = ParkingSpotStatus.violationOrPending;
      } else if (occupiedIds.contains(spotId)) {
        status = ParkingSpotStatus.occupied;
      } else if (reservedIds.contains(spotId)) {
        status = ParkingSpotStatus.reserved;
      }

      return ParkingSpot(
        id: spotId,
        code: 'Ô A$spotId',
        status: status,
        occupied: status == ParkingSpotStatus.occupied,
        userId: status == ParkingSpotStatus.available
            ? ''
            : 'some_mock_user_id',
        paymentStatus: status == ParkingSpotStatus.violationOrPending
            ? 'pending_payment'
            : (status == ParkingSpotStatus.available ? 'none' : 'active'),
        transactionAmount: status == ParkingSpotStatus.violationOrPending
            ? 13999
            : 0,
        expectedDuration: status == ParkingSpotStatus.reserved ? 3600 : 0,
        bookingStartTime: 0,
      );
    });
  }

  Stream<List<ParkingSpot>> getParkingSpotsStream(int parkingLotId) {
    if (parkingLotId == 1) {
      final ref = FirebaseDatabase.instance.ref('smart_parking_system/slots');
      return ref.onValue.map((event) {
        final snapshot = event.snapshot;
        if (!snapshot.exists || snapshot.value == null) {
          return [];
        }

        final Map<dynamic, dynamic> slotsMap;
        if (snapshot.value is Map) {
          slotsMap = snapshot.value as Map;
        } else if (snapshot.value is List) {
          final list = snapshot.value as List;
          slotsMap = {
            for (var i = 0; i < list.length; i++)
              if (list[i] != null) 'slot_${i + 1}': list[i],
          };
        } else {
          return [];
        }

        final List<ParkingSpot> spots = [];
        final sortedKeys = slotsMap.keys.map((k) => k.toString()).toList()
          ..sort();

        for (var key in sortedKeys) {
          final slotData = slotsMap[key];
          if (slotData is Map) {
            final occupied = slotData['occupied'] as bool? ?? false;
            final reserved = slotData['reserved'] as bool? ?? false;
            final paymentStatus =
                slotData['payment_status'] as String? ?? 'none';
            final userId = slotData['user_id'] as String? ?? '';
            final transactionAmount =
                slotData['transaction_amount'] as int? ?? 0;
            final expectedDuration = slotData['expected_duration'] as int? ?? 0;
            final actualEntryTime = slotData['actual_entry_time'] as int? ?? 0;
            int rawStartTime = slotData['booking_start_time'] as int? ?? 0;
            if (rawStartTime > 9999999999) {
              rawStartTime = rawStartTime ~/ 1000;
            }
            final bookingStartTime = rawStartTime;
            final idString = key.replaceAll(RegExp(r'[^0-9]'), '');
            final id = int.tryParse(idString) ?? 0;
            final code = 'Ô A$id';

            ParkingSpotStatus status = ParkingSpotStatus.available;
            if (paymentStatus == 'violation' ||
                paymentStatus == 'pending_payment' ||
                paymentStatus == 'extra_charge_pending' ||
                paymentStatus == 'settlement_pending') {
              status = ParkingSpotStatus.violationOrPending;
            } else if (occupied) {
              status = ParkingSpotStatus.occupied;
            } else if (reserved && actualEntryTime == 0) {
              status = ParkingSpotStatus.reserved;
            }

            spots.add(
              ParkingSpot(
                id: id,
                code: code,
                status: status,
                occupied: occupied,
                userId: userId,
                paymentStatus: paymentStatus,
                transactionAmount: transactionAmount,
                expectedDuration: expectedDuration,
                bookingStartTime: bookingStartTime,
              ),
            );
          }
        }
        return spots;
      });
    } else {
      return Stream.fromFuture(getParkingSpots(parkingLotId));
    }
  }
}
