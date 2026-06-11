class Booking {
  final String bookingCode;
  final String parkingName;
  final String parkingAddress;
  final String spotCode;
  final int hours;
  final int amount;
  final String paymentMethod;
  final String status;
  final DateTime createdAt;

  const Booking({
    required this.bookingCode,
    required this.parkingName,
    required this.parkingAddress,
    required this.spotCode,
    required this.hours,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
  });
}