import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../models/parking_spot.dart';
import '../models/parking_lot.dart';
import '../utils/app_colors.dart';
import '../screens/booking_screen.dart';
import '../screens/settlement_payment_screen.dart';
import '../utils/mock_parking_data.dart';
import 'shaker_widget.dart';

class ParkingSpotCard extends StatefulWidget {
  final ParkingSpot spot;

  const ParkingSpotCard({super.key, required this.spot});

  @override
  State<ParkingSpotCard> createState() => _ParkingSpotCardState();
}

class _ParkingSpotCardState extends State<ParkingSpotCard> {
  Timer? _graceTimer;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _manageGraceTimer();
  }

  @override
  void didUpdateWidget(covariant ParkingSpotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _manageGraceTimer();
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    super.dispose();
  }

  void _manageGraceTimer() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool shouldRun = widget.spot.userId == currentUid &&
        !widget.spot.occupied &&
        (widget.spot.paymentStatus == 'awaiting_checkin' ||
            widget.spot.paymentStatus == 'active' ||
            widget.spot.status == ParkingSpotStatus.reserved) &&
        widget.spot.bookingStartTime > 0;

    if (shouldRun) {
      _graceTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
        _checkGraceTime();
      });
    } else {
      _graceTimer?.cancel();
      _graceTimer = null;
    }
  }

  void _checkGraceTime() {
    if (!mounted) return;
    final bookingStartTime = DateTime.fromMillisecondsSinceEpoch(widget.spot.bookingStartTime * 1000);
    final int elapsedSeconds = DateTime.now().difference(bookingStartTime).inSeconds;

    if (elapsedSeconds == 40) {
      if (!_isDialogShowing) {
        _showGraceDialog();
      }
    } else if (elapsedSeconds >= 45) {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (_isDialogShowing) {
        Navigator.of(context, rootNavigator: true).pop();
        _isDialogShowing = false;
      }
    }
  }

  void _showGraceDialog() {
    _isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
              SizedBox(width: 8),
              Text('Cảnh báo giữ chỗ', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Sắp hết thời gian giữ chỗ thực tế! Bạn có muốn gia hạn thêm (5.000đ)?',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isDialogShowing = false;
                _graceTimer?.cancel();
                _graceTimer = null;
              },
              child: const Text('Hủy bỏ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isDialogShowing = false;
                _extendBooking();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Gia hạn (5k)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  ParkingLot _getParkingLotFromSpot() {
    final code = widget.spot.code;
    if (code.contains('Ô B')) {
      return const ParkingLot(
        id: 2,
        name: 'Bãi đỗ Mỹ Đình',
        address: 'Sân vận động Mỹ Đình, Nam Từ Liêm, Hà Nội',
        totalSpots: 4,
        availableSpots: 3,
        pricePerHour: 25000,
        latitude: 21.0185,
        longitude: 105.7740,
      );
    } else if (code.contains('Ô C')) {
      return const ParkingLot(
        id: 3,
        name: 'Bãi đỗ Hoàn Kiếm',
        address: 'Hồ Hoàn Kiếm, Lý Thái Tổ, Hà Nội',
        totalSpots: 4,
        availableSpots: 3,
        pricePerHour: 30000,
        latitude: 21.0285,
        longitude: 105.8542,
      );
    } else if (code.contains('Ô D')) {
      return const ParkingLot(
        id: 4,
        name: 'Bãi đỗ Ba Đình',
        address: 'Quảng trường Ba Đình, Hùng Vương, Hà Nội',
        totalSpots: 4,
        availableSpots: 3,
        pricePerHour: 20000,
        latitude: 21.0368,
        longitude: 105.8346,
      );
    } else {
      return const ParkingLot(
        id: 1,
        name: 'Bãi đỗ Cầu Giấy',
        address: '144 Xuân Thủy, Cầu Giấy, Hà Nội',
        totalSpots: 4,
        availableSpots: 3,
        pricePerHour: 20000,
        latitude: 21.0368,
        longitude: 105.7823,
      );
    }
  }

  Future<void> _extendBooking() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    _graceTimer?.cancel();
    _graceTimer = null;

    final userRef = FirebaseDatabase.instance.ref('smart_parking_system/users/$currentUid');
    final balanceRef = userRef.child('balance');
    final historyRef = userRef.child('history');

    try {
      final balanceSnap = await balanceRef.get();
      final currentBalance = int.tryParse(balanceSnap.value?.toString() ?? '0') ?? 0;

      if (currentBalance < 5000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Số dư không đủ để gia hạn (Cần 5.000đ)!'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        return;
      }

      final int lotId = widget.spot.id >= 300
          ? 4
          : (widget.spot.id >= 200
              ? 3
              : (widget.spot.id >= 100 ? 2 : 1));

      if (lotId == 1) {
        final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${widget.spot.id}');
        await Future.wait([
          balanceRef.set(currentBalance - 5000),
          historyRef.push().set({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'slot_name': widget.spot.code,
            'amount': 5000,
            'status': 'Gia hạn giữ chỗ',
          }),
          slotRef.update({
            'booking_start_time': ServerValue.timestamp,
          }),
        ]);
      } else {
        await Future.wait([
          balanceRef.set(currentBalance - 5000),
          historyRef.push().set({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'slot_name': widget.spot.code,
            'amount': 5000,
            'status': 'Gia hạn giữ chỗ',
          }),
        ]);

        final list = MockParkingData.spots[lotId] ?? [];
        final index = list.indexWhere((s) => s.id == widget.spot.id);
        if (index != -1) {
          list[index] = list[index].copyWith(
            bookingStartTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gia hạn giữ chỗ thành công!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi gia hạn: $e');
    }
  }

  void _bookSlot() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingScreen(
          spot: widget.spot,
          parkingLot: _getParkingLotFromSpot(),
        ),
      ),
    );
  }

  Future<void> _checkIn() async {
    try {
      final int lotId = widget.spot.id >= 300
          ? 4
          : (widget.spot.id >= 200
              ? 3
              : (widget.spot.id >= 100 ? 2 : 1));

      if (lotId == 1) {
        final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${widget.spot.id}');
        await slotRef.update({
          'payment_status': 'active',
        });
      } else {
        final list = MockParkingData.spots[lotId] ?? [];
        final index = list.indexWhere((s) => s.id == widget.spot.id);
        if (index != -1) {
          list[index] = list[index].copyWith(
            paymentStatus: 'active',
            occupied: true,
            status: ParkingSpotStatus.occupied,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xác nhận đến bãi đỗ!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi checkin: $e');
    }
  }

  void _settlement() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettlementPaymentScreen(
          spot: widget.spot,
          amount: widget.spot.transactionAmount,
          transactionType: 'Quyết toán rời bãi',
        ),
      ),
    );
  }

  void _payWalkin() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettlementPaymentScreen(
          spot: widget.spot,
          amount: widget.spot.transactionAmount,
          transactionType: 'Thanh toán xe vãng lai',
        ),
      ),
    );
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
    return '${buffer.toString()}đ';
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final spot = widget.spot;

    // 1. Bẫy quyền:
    final bool isMySpot = spot.userId == currentUid;
    final bool isOccupiedByOthers = spot.userId.isNotEmpty && !isMySpot;

    if (isOccupiedByOthers) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              spot.code,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'ĐÃ CÓ NGƯỜI ĐẶT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Chống trốn vé (Rung lắc)
    final bool isViolation = spot.paymentStatus == 'error_unpaid_slots';
    if (isViolation) {
      return ShakerWidget(
        shake: true,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.danger.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 6),
                  Text(
                    spot.code,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'CỔNG KHÓA: BÃI ĐỖ CÓ XE CHƯA THANH TOÁN!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Các trạng thái khác
    Color cardBorderColor = Colors.transparent;
    Color statusBgColor = Colors.transparent;
    Color statusTextColor = Colors.white;
    String statusLabel = '';
    Widget actionButton = const SizedBox.shrink();
    Widget infoText = const SizedBox.shrink();

    // Phân loại logic thẻ
    final bool isAwaitingCheckin = spot.paymentStatus == 'awaiting_checkin';
    final bool isWalkinPending = spot.paymentStatus == 'pending_payment' && spot.userId.isEmpty;
    final bool isSettlementPending = spot.paymentStatus == 'settlement_pending';

    if (isAwaitingCheckin) {
      cardBorderColor = Colors.orange;
      statusBgColor = Colors.orange.withValues(alpha: 0.15);
      statusTextColor = Colors.orange;
      statusLabel = 'Chờ Check-in';
      actionButton = _buildButton(
        text: 'TÔI ĐÃ ĐẾN NƠI',
        icon: Icons.check_circle_outline,
        color: Colors.orange,
        onPressed: _checkIn,
      );
    } else if (isWalkinPending) {
      cardBorderColor = AppColors.danger;
      statusBgColor = AppColors.danger.withValues(alpha: 0.15);
      statusTextColor = AppColors.danger;
      statusLabel = 'Xe Vãng Lai';
      infoText = Text(
        'Phí: ${formatMoney(spot.transactionAmount)}',
        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 13),
      );
      actionButton = _buildButton(
        text: 'NHẬN XE & THANH TOÁN',
        icon: Icons.payment,
        color: AppColors.danger,
        onPressed: _payWalkin,
      );
    } else if (isSettlementPending) {
      cardBorderColor = AppColors.danger;
      statusBgColor = AppColors.danger.withValues(alpha: 0.15);
      statusTextColor = AppColors.danger;
      statusLabel = 'Quyết Toán';
      infoText = Text(
        spot.transactionAmount < 0 
            ? 'Hoàn trả: ${formatMoney(spot.transactionAmount.abs())}' 
            : 'Thu thêm: ${formatMoney(spot.transactionAmount)}',
        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 13),
      );
      actionButton = _buildButton(
        text: 'QUYẾT TOÁN RỜI BÃI',
        icon: Icons.output_rounded,
        color: AppColors.danger,
        onPressed: _settlement,
      );
    } else if (spot.status == ParkingSpotStatus.available) {
      cardBorderColor = AppColors.success;
      statusBgColor = AppColors.success.withValues(alpha: 0.15);
      statusTextColor = AppColors.success;
      statusLabel = 'Trống';
      actionButton = _buildButton(
        text: 'ĐẶT CHỖ MỚI',
        icon: Icons.add_task_rounded,
        color: AppColors.success,
        onPressed: _bookSlot,
      );
    } else if (spot.status == ParkingSpotStatus.reserved) {
      cardBorderColor = AppColors.warning;
      statusBgColor = AppColors.warning.withValues(alpha: 0.15);
      statusTextColor = AppColors.warning;
      statusLabel = 'Đã đặt';
      
      // Hiển thị đếm ngược thời gian thực (giây thực tế)
      if (spot.bookingStartTime > 0) {
        final start = DateTime.fromMillisecondsSinceEpoch(spot.bookingStartTime * 1000);
        final elapsed = DateTime.now().difference(start).inSeconds;
        final remaining = 45 - elapsed;
        infoText = Text(
          remaining > 0 ? 'Hủy giữ chỗ sau: ${remaining}s' : 'Đang đồng bộ...',
          style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textGrey, fontSize: 12),
        );
      }
      
      actionButton = OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          minimumSize: const Size(double.infinity, 40),
        ),
        child: const Text('ĐANG GIỮ CHỖ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
      );
    } else if (spot.status == ParkingSpotStatus.occupied) {
      cardBorderColor = const Color(0xFF1E3A8A);
      statusBgColor = const Color(0xFF1E3A8A).withValues(alpha: 0.15);
      statusTextColor = const Color(0xFF1E3A8A);
      statusLabel = 'Đang đỗ';
      actionButton = OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          minimumSize: const Size(double.infinity, 40),
        ),
        child: const Text('XE ĐANG TRONG BÃI', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold)),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: cardBorderColor.withValues(alpha: 0.5), width: 2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                spot.code,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(child: infoText),
          const SizedBox(height: 6),
          actionButton,
        ],
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        minimumSize: const Size(double.infinity, 40),
      ),
    );
  }
}
