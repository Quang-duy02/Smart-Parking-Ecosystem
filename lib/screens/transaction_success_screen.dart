import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import 'main_screen.dart';

class TransactionSuccessScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String spotCode;
  final String transactionType;
  final int amount;
  final bool isRefund;
  final DateTime transactionTime;

  const TransactionSuccessScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.spotCode,
    required this.transactionType,
    required this.amount,
    required this.isRefund,
    required this.transactionTime,
  });

  String _formatMoney(int value) {
    final text = value.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final reverseIndex = text.length - i;
      buffer.write(text[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write('.');
      }
    }
    return '${isRefund ? "+" : "-"}${buffer.toString()}đ';
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day-$month-$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500), // Tối ưu chiều rộng khi hiển thị trên màn hình Web
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon trạng thái lớn (Hoàn tiền dùng màu xanh dương hoặc xanh lá, thanh toán dùng màu xanh lá)
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: (isRefund ? Colors.blue.withValues(alpha: 0.12) : AppColors.success.withValues(alpha: 0.12)),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRefund ? Icons.keyboard_return_rounded : Icons.check_circle_rounded,
                      color: isRefund ? Colors.blue.shade700 : AppColors.success,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textGrey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),

                  // Thẻ hóa đơn chi tiết
                  _buildReceiptCard(),

                  const SizedBox(height: 32),
                  
                  // Nút bấm quay về
                  SizedBox(
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
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26), // Pill-shaped
                        ),
                      ),
                      child: const Text(
                        'QUAY VỀ TRANG CHỦ',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header của biên lai
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isRefund ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Center(
              child: Text(
                isRefund ? 'HÓA ĐƠN HOÀN TIỀN' : 'HÓA ĐƠN QUYẾT TOÁN',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isRefund ? Colors.blue.shade700 : AppColors.primary,
                  letterSpacing: 0.8,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildReceiptRow('Ô đỗ áp dụng', spotCode, isHighlight: true),
                const SizedBox(height: 12),
                _buildReceiptRow('Loại giao dịch', transactionType),
                const SizedBox(height: 12),
                _buildReceiptRow('Thời gian thực hiện', _formatDateTime(transactionTime)),
                const SizedBox(height: 12),
                _buildReceiptRow('Phương thức', 'Ví tài khoản'),
                const SizedBox(height: 12),
                _buildReceiptRow('Trạng thái', 'Thành công', valColor: AppColors.success),
                
                const SizedBox(height: 16),
                _buildDashedLine(),
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isRefund ? 'SỐ TIỀN HOÀN LẠI' : 'TỔNG TIỀN THANH TOÁN',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      _formatMoney(amount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isRefund ? Colors.blue.shade700 : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isHighlight = false, Color? valColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
              color: valColor ?? (isHighlight ? AppColors.primary : AppColors.textDark),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashedLine() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 5.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0XFFE2E8F0)),
              ),
            );
          }),
        );
      },
    );
  }
}
