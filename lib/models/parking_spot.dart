enum ParkingSpotStatus {
  available,            // Trống (Xanh)
  reserved,             // Đã đặt (Vàng)
  occupied,             // Đang đỗ (Xanh đậm)
  violationOrPending,   // Vi phạm/Cần thanh toán (Đỏ)
}

class ParkingSpot {
  final int id;
  final String code;
  final ParkingSpotStatus status;
  final bool occupied;
  final String userId;
  final String paymentStatus;
  final int transactionAmount;
  final int expectedDuration;
  final int bookingStartTime;

  const ParkingSpot({
    required this.id,
    required this.code,
    required this.status,
    required this.occupied,
    required this.userId,
    required this.paymentStatus,
    required this.transactionAmount,
    required this.expectedDuration,
    required this.bookingStartTime,
  });

  ParkingSpot copyWith({
    int? id,
    String? code,
    ParkingSpotStatus? status,
    bool? occupied,
    String? userId,
    String? paymentStatus,
    int? transactionAmount,
    int? expectedDuration,
    int? bookingStartTime,
  }) {
    return ParkingSpot(
      id: id ?? this.id,
      code: code ?? this.code,
      status: status ?? this.status,
      occupied: occupied ?? this.occupied,
      userId: userId ?? this.userId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      transactionAmount: transactionAmount ?? this.transactionAmount,
      expectedDuration: expectedDuration ?? this.expectedDuration,
      bookingStartTime: bookingStartTime ?? this.bookingStartTime,
    );
  }
}