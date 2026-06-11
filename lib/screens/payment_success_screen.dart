import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/booking.dart';
import '../models/parking_lot.dart';
import '../models/parking_spot.dart';
import '../models/payment.dart';
import '../services/booking_service.dart';
import '../utils/app_colors.dart';
import 'main_screen.dart';

class PaymentSuccessScreen extends StatefulWidget {
  final ParkingLot parkingLot;
  final ParkingSpot parkingSpot;
  final int amount;
  final String method;
  final int hours;

  const PaymentSuccessScreen({
    super.key,
    required this.parkingLot,
    required this.parkingSpot,
    required this.amount,
    required this.method,
    required this.hours,
  });

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  late final String bookingCode;

  @override
  void initState() {
    super.initState();

    bookingCode = 'SP-${DateTime.now().millisecondsSinceEpoch}';

    _saveBookingHistory();
  }

  void _saveBookingHistory() {
    final now = DateTime.now();

    final booking = Booking(
      bookingCode: bookingCode,
      parkingName: widget.parkingLot.name,
      parkingAddress: widget.parkingLot.address,
      spotCode: widget.parkingSpot.code,
      hours: widget.hours,
      amount: widget.amount,
      paymentMethod: widget.method,
      status: 'PAID',
      createdAt: now,
    );

    final payment = Payment(
      paymentId: 'PAY-${now.millisecondsSinceEpoch}',
      bookingCode: bookingCode,
      amount: widget.amount,
      method: widget.method,
      status: 'PAID',
      paidAt: now,
    );

    BookingService.instance.addBooking(booking: booking, payment: payment);
  }

  String formatMoney(int value) {
    final text = value.toString();
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final reverseIndex = text.length - i;
      buffer.write(text[i]);

      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${buffer.toString()} VNĐ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _successIcon(),
                const SizedBox(height: 20),
                const Text(
                  'Thanh toán thành công',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bạn đã đặt chỗ ${widget.parkingSpot.code} tại ${widget.parkingLot.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 22),
                _infoRow('Số tiền', formatMoney(widget.amount)),
                _infoRow('Thời gian', '${widget.hours} giờ'),
                _infoRow('Phương thức', widget.method),
                _infoRow('Mã đặt chỗ', bookingCode),
                const SizedBox(height: 26),
                _homeButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _successIcon() {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_circle, color: AppColors.success, size: 70),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textGrey)),
          const SizedBox(width: 20),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () {
          final email = FirebaseAuth.instance.currentUser?.email ?? 'demo@gmail.com';
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => MainScreen(userEmail: email),
            ),
            (route) => false,
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Quay về trang chủ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
