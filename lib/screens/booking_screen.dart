import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/parking_lot.dart';
import '../models/parking_spot.dart';
import '../utils/app_colors.dart';
import '../utils/mock_parking_data.dart';
import 'booking_success_screen.dart';

class BookingScreen extends StatefulWidget {
  final ParkingSpot spot;
  final ParkingLot parkingLot;

  const BookingScreen({
    super.key,
    required this.spot,
    required this.parkingLot,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  int _selectedHours = 1;
  bool _isBooking = false;
  int _userBalance = 0;
  Stream<DatabaseEvent>? _balanceStream;

  @override
  void initState() {
    super.initState();
    _initBalanceStream();
  }

  void _initBalanceStream() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
      _balanceStream = balanceRef.onValue;
    }
  }

  String _formatMoney(int value) {
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

  Future<void> _topUpMoney(int amount) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Hiển thị dialog xác nhận nạp tiền giả lập
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nạp tiền demo', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Bạn có muốn nạp thêm ${_formatMoney(amount)} vào tài khoản để thực hiện đặt chỗ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
        await balanceRef.set(_userBalance + amount);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nạp thành công ${_formatMoney(amount)} vào ví demo!'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi nạp tiền: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleConfirmBooking() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final pricePerHour = widget.parkingLot.pricePerHour > 0 ? widget.parkingLot.pricePerHour : 20000;
    final totalPrice = _selectedHours * pricePerHour;

    if (_userBalance < totalPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số dư không đủ! Vui lòng nạp thêm tiền vào ví.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _isBooking = true;
    });

    try {
      final newBalance = _userBalance - totalPrice;
      final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
      final historyRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/history');

      if (widget.parkingLot.id == 1) {
        final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${widget.spot.id}');
        await Future.wait([
          balanceRef.set(newBalance),
          slotRef.update({
            'reserved': true,
            'user_id': currentUser.uid,
            'expected_duration': _selectedHours * 3600,
            'payment_status': 'active',
            'actual_entry_time': 0,
            'actual_exit_time': 0,
            'transaction_amount': 0,
            'booking_start_time': ServerValue.timestamp,
          }),
          historyRef.push().set({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'slot_name': widget.spot.code,
            'amount': totalPrice,
            'status': 'Đặt chỗ trước',
          }),
        ]);
      } else {
        // Mock bãi đỗ khác: chỉ ghi ví & lịch sử vào Firebase, cập nhật MockParkingData local
        await Future.wait([
          balanceRef.set(newBalance),
          historyRef.push().set({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'slot_name': '${widget.spot.code} (${widget.parkingLot.name})',
            'amount': totalPrice,
            'status': 'Đặt chỗ trước',
          }),
        ]);

        // Cập nhật MockParkingData
        final lotId = widget.parkingLot.id;
        final list = MockParkingData.spots[lotId] ?? [];
        final index = list.indexWhere((s) => s.id == widget.spot.id);
        if (index != -1) {
          list[index] = list[index].copyWith(
            status: ParkingSpotStatus.reserved,
            userId: currentUser.uid,
            paymentStatus: 'active',
            expectedDuration: _selectedHours * 3600,
            bookingStartTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _isBooking = false;
      });

      // Điều hướng tới BookingSuccessScreen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => BookingSuccessScreen(
            spotCode: widget.spot.code,
            durationHours: _selectedHours,
            amount: totalPrice,
            bookingTime: DateTime.now(),
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBooking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xảy ra lỗi khi đặt chỗ: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pricePerHour = widget.parkingLot.pricePerHour > 0 ? widget.parkingLot.pricePerHour : 20000;
    final totalPrice = _selectedHours * pricePerHour;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Đặt Chỗ Mới', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textDark,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _balanceStream,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            _userBalance = int.tryParse(snapshot.data!.snapshot.value.toString()) ?? 0;
          }

          final bool hasEnoughMoney = _userBalance >= totalPrice;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Thẻ thông tin vị trí đỗ xe
                _buildSpotInfoCard(),
                const SizedBox(height: 20),

                // 2. Thẻ số dư ví và nạp tiền
                _buildWalletCard(hasEnoughMoney),
                const SizedBox(height: 20),

                // 3. Thẻ chọn thời gian đỗ xe
                _buildDurationSelectorCard(pricePerHour),
                const SizedBox(height: 20),

                // 4. Thẻ tóm tắt chi phí
                _buildBillSummaryCard(pricePerHour, totalPrice, hasEnoughMoney),
                const SizedBox(height: 32),

                // 5. Nút bấm đặt chỗ
                _buildConfirmButton(totalPrice),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpotInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.local_parking_rounded,
              color: AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.parkingLot.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.parkingLot.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Ô đỗ: ${widget.spot.code}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 12,
                        ),
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

  Widget _buildWalletCard(bool hasEnoughMoney) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Số dư ví của bạn',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              if (!hasEnoughMoney)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Không đủ số dư',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.danger,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatMoney(_userBalance),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: hasEnoughMoney ? AppColors.textDark : AppColors.danger,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text(
            'Nạp tiền nhanh (Giả lập demo):',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _topUpMoney(50000),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    '+50.000đ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _topUpMoney(100000),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    '+100.000đ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _topUpMoney(200000),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    '+200.000đ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelectorCard(int pricePerHour) {
    final quickOptions = [1, 2, 3, 4, 8, 12];

    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Thời gian gửi dự kiến',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '$_selectedHours giờ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withValues(alpha: 0.12),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.12),
              valueIndicatorColor: AppColors.primary,
              valueIndicatorTextStyle: const TextStyle(color: Colors.white),
            ),
            child: Slider(
              value: _selectedHours.toDouble(),
              min: 1,
              max: 24,
              divisions: 23,
              label: '$_selectedHours giờ',
              onChanged: (value) {
                setState(() {
                  _selectedHours = value.toInt();
                });
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('1 giờ', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
              Text('24 giờ', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Chọn nhanh thời gian:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quickOptions.map((hours) {
              final isSelected = _selectedHours == hours;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedHours = hours;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$hours Giờ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isSelected ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBillSummaryCard(int pricePerHour, int totalPrice, bool hasEnoughMoney) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Chi tiết thanh toán',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Đơn giá giữ chỗ', style: TextStyle(color: AppColors.textGrey, fontSize: 13.5)),
              Text('${_formatMoney(pricePerHour)}/giờ', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Thời gian dự kiến', style: TextStyle(color: AppColors.textGrey, fontSize: 13.5)),
              Text('$_selectedHours giờ', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tổng thanh toán',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark),
              ),
              Text(
                _formatMoney(totalPrice),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (hasEnoughMoney) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Số dư còn lại sau đặt', style: TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
                Text(
                  _formatMoney(_userBalance - totalPrice),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textGrey,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfirmButton(int totalPrice) {
    final bool hasEnoughMoney = _userBalance >= totalPrice;

    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: (_isBooking || !hasEnoughMoney) ? null : _handleConfirmBooking,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27), // Pill-shaped
          ),
          elevation: 2,
        ),
        child: _isBooking
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                hasEnoughMoney ? 'XÁC NHẬN ĐẶT CHỖ' : 'SỐ DƯ TÀI KHOẢN KHÔNG ĐỦ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}
