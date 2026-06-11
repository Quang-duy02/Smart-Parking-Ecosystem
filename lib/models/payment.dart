class Payment {
  final String paymentId;
  final String bookingCode;
  final int amount;
  final String method;
  final String status;
  final DateTime paidAt;

  const Payment({
    required this.paymentId,
    required this.bookingCode,
    required this.amount,
    required this.method,
    required this.status,
    required this.paidAt,
  });
}