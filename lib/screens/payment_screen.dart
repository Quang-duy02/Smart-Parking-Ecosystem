import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/parking_lot.dart';
import '../models/parking_spot.dart';
import '../utils/app_colors.dart';
import '../widgets/user_balance_widget.dart';
import 'payment_success_screen.dart';

class PaymentScreen extends StatefulWidget {
  final ParkingLot parkingLot;
  final ParkingSpot parkingSpot;

  const PaymentScreen({
    super.key,
    required this.parkingLot,
    required this.parkingSpot,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int selectedHour = 1;
  String selectedMethod = 'MOMO';
  bool isPaying = false;

  int get totalPrice {
    if (widget.parkingSpot.transactionAmount > 0) {
      return widget.parkingSpot.transactionAmount;
    }
    return widget.parkingLot.pricePerHour * selectedHour;
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

  Future<void> _payNow() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để thanh toán')),
      );
      return;
    }

    setState(() {
      isPaying = true;
    });

    try {
      // 1. Kiểm tra số dư người dùng từ Firebase
      final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
      final balanceSnapshot = await balanceRef.get();
      final int balance = int.tryParse(balanceSnapshot.value?.toString() ?? '0') ?? 0;

      if (balance < totalPrice) {
        if (!mounted) return;
        setState(() {
          isPaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Số dư không đủ!'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      // 2. Thực hiện thanh toán và trừ số dư tài khoản
      final newBalance = balance - totalPrice;
      final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${widget.parkingSpot.id}');
      
      final bool hasFixedAmount = widget.parkingSpot.transactionAmount > 0;
      
      final historyRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/history');
      await Future.wait([
        balanceRef.set(newBalance),
        historyRef.push().set({
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'slot_name': widget.parkingSpot.code,
          'amount': totalPrice,
          'status': 'Hoàn thành',
        }),
        hasFixedAmount
            ? slotRef.update({
                'payment_status': 'paid',
                'transaction_amount': 0,
              })
            : slotRef.update({
                'payment_status': 'paid',
                'expected_duration': selectedHour * 3600,
                'booking_start_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              }),
      ]);
    } catch (e) {
      debugPrint('Lỗi thanh toán: $e');
      if (!mounted) return;
      setState(() {
        isPaying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xảy ra lỗi khi thanh toán: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    setState(() {
      isPaying = false;
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(
          parkingLot: widget.parkingLot,
          parkingSpot: widget.parkingSpot,
          amount: totalPrice,
          method: selectedMethod,
          hours: selectedHour,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parkingLot = widget.parkingLot;
    final parkingSpot = widget.parkingSpot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thanh toán'),
        actions: const [
          UserBalanceWidget(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Thông tin đặt chỗ'),
                const SizedBox(height: 16),
                _infoRow('Bãi đỗ', parkingLot.name),
                _infoRow('Vị trí', parkingSpot.code),
                _infoRow('Giá mỗi giờ', formatMoney(parkingLot.pricePerHour)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Thời gian gửi xe'),
                const SizedBox(height: 12),
                widget.parkingSpot.transactionAmount > 0
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: AppColors.primary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Số tiền cần thanh toán được tính toán dựa trên thời gian đỗ xe thực tế của bạn.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : DropdownButtonFormField<int>(
                        initialValue: selectedHour,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 giờ')),
                          DropdownMenuItem(value: 2, child: Text('2 giờ')),
                          DropdownMenuItem(value: 3, child: Text('3 giờ')),
                          DropdownMenuItem(value: 4, child: Text('4 giờ')),
                          DropdownMenuItem(value: 5, child: Text('5 giờ')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              selectedHour = value;
                            });
                          }
                        },
                      ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Phương thức thanh toán'),
                const SizedBox(height: 12),
                _paymentMethodTile(
                  title: 'Ví MoMo demo',
                  value: 'MOMO',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                _paymentMethodTile(
                  title: 'VNPAY demo',
                  value: 'VNPAY',
                  icon: Icons.qr_code_2_outlined,
                ),
                _paymentMethodTile(
                  title: 'Thanh toán tiền mặt',
                  value: 'CASH',
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _totalPriceBox(),
          const SizedBox(height: 24),
          _payButton(),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.textDark,
      ),
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

  Widget _paymentMethodTile({
    required String title,
    required String value,
    required IconData icon,
  }) {
    final bool isSelected = selectedMethod == value;
    return InkWell(
      onTap: () {
        setState(() {
          selectedMethod = value;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : AppColors.card,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textGrey,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : AppColors.textDark,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.grey.shade400,
                  width: isSelected ? 6 : 2,
                ),
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalPriceBox() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Tổng tiền',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          Text(
            formatMoney(totalPrice),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isPaying ? null : _payNow,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isPaying
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text(
                'Xác nhận thanh toán',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
