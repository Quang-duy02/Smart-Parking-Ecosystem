import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/parking_spot.dart';
import '../utils/app_colors.dart';
import '../utils/mock_parking_data.dart';
import 'transaction_success_screen.dart';

class SettlementPaymentScreen extends StatefulWidget {
  final ParkingSpot spot;
  final int amount;
  final String transactionType; // "Quyết toán rời bãi" hoặc "Thanh toán xe vãng lai"

  const SettlementPaymentScreen({
    super.key,
    required this.spot,
    required this.amount,
    required this.transactionType,
  });

  @override
  State<SettlementPaymentScreen> createState() => _SettlementPaymentScreenState();
}

class _SettlementPaymentScreenState extends State<SettlementPaymentScreen> {
  int _userBalance = 0;
  bool _isProcessing = false;
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
    final isNegative = value < 0;
    final absVal = value.abs();
    final text = absVal.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final reverseIndex = text.length - i;
      buffer.write(text[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write('.');
      }
    }
    return '${isNegative ? '-' : ''}${buffer.toString()}đ';
  }

  Future<void> _topUpMoney(int topUpAmount) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nạp tiền demo', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Bạn có muốn nạp thêm ${_formatMoney(topUpAmount)} vào tài khoản?'),
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
        await balanceRef.set(_userBalance + topUpAmount);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nạp thành công ${_formatMoney(topUpAmount)} vào ví demo!'),
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

  Future<void> _handleConfirmPayment() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final requiredAmount = widget.amount;

    if (requiredAmount > 0 && _userBalance < requiredAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số dư ví không đủ! Vui lòng nạp thêm tiền.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final newBalance = _userBalance - requiredAmount;
      final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
      final historyRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/history');

      final String historyStatus = widget.transactionType == 'Thanh toán xe vãng lai'
          ? 'Thanh toán xe vãng lai'
          : (requiredAmount < 0 ? 'Quyết toán hoàn tiền' : 'Quyết toán phụ trội');

      final int lotId = widget.spot.id >= 300
          ? 4
          : (widget.spot.id >= 200
              ? 3
              : (widget.spot.id >= 100 ? 2 : 1));

      if (lotId == 1) {
        final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${widget.spot.id}');
        if (widget.transactionType == 'Thanh toán xe vãng lai') {
          await Future.wait([
            balanceRef.set(newBalance),
            historyRef.push().set({
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'slot_name': widget.spot.code,
              'amount': requiredAmount,
              'status': historyStatus,
            }),
            slotRef.update({
              'user_id': currentUser.uid,
              'payment_status': 'paid',
            }),
          ]);
        } else {
          await Future.wait([
            balanceRef.set(newBalance),
            historyRef.push().set({
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'slot_name': widget.spot.code,
              'amount': requiredAmount,
              'status': historyStatus,
            }),
            slotRef.update({
              'payment_status': 'paid',
              'transaction_amount': 0,
            }),
          ]);
        }
      } else {
        // Mock bãi đỗ khác: chỉ ghi ví & lịch sử vào Firebase, cập nhật MockParkingData local
        await Future.wait([
          balanceRef.set(newBalance),
          historyRef.push().set({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'slot_name': widget.spot.code,
            'amount': requiredAmount,
            'status': historyStatus,
          }),
        ]);

        // Cập nhật MockParkingData local
        final list = MockParkingData.spots[lotId] ?? [];
        final index = list.indexWhere((s) => s.id == widget.spot.id);
        if (index != -1) {
          list[index] = list[index].copyWith(
            status: ParkingSpotStatus.available,
            occupied: false,
            userId: '',
            paymentStatus: 'none',
            transactionAmount: 0,
            expectedDuration: 0,
            bookingStartTime: 0,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });

      // Điều hướng tới TransactionSuccessScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionSuccessScreen(
            title: requiredAmount < 0
                ? 'Quyết Toán Hoàn Tiền Thành Công!'
                : (widget.transactionType == 'Thanh toán xe vãng lai'
                    ? 'Thanh Toán Xe Vãng Lai Thành Công!'
                    : 'Quyết Toán Rời Bãi Thành Công!'),
            subtitle: requiredAmount < 0
                ? 'Số tiền được hoàn trả vào ví của bạn.'
                : 'Thanh toán hoàn tất. Barie cổng đã mở.',
            spotCode: widget.spot.code,
            transactionType: historyStatus,
            amount: requiredAmount,
            isRefund: requiredAmount < 0,
            transactionTime: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xảy ra lỗi khi xử lý: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiredAmount = widget.amount;
    final isRefund = requiredAmount < 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.transactionType, style: const TextStyle(fontWeight: FontWeight.bold)),
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

          final bool hasEnoughMoney = requiredAmount <= 0 || _userBalance >= requiredAmount;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500), // Tối ưu hóa bề rộng trên màn hình Web
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Thẻ thông tin vị trí đỗ xe
                    _buildSpotInfoCard(),
                    const SizedBox(height: 16),

                    // 2. Thẻ số dư ví (chỉ hiển thị nạp tiền nếu là thanh toán thêm, hoàn tiền thì chỉ hiển thị số dư)
                    _buildWalletCard(hasEnoughMoney, isRefund),
                    const SizedBox(height: 16),

                    // 3. Thẻ tóm tắt chi phí thanh toán/quyết toán
                    _buildBillSummaryCard(requiredAmount, isRefund),
                    const SizedBox(height: 16),

                    // 4. Thẻ cảnh báo an toàn di chuyển ra cổng (Yêu cầu quan trọng của user)
                    _buildGateWarningCard(),
                    const SizedBox(height: 24),

                    // 5. Nút bấm Xác nhận & Mở cổng
                    _buildConfirmButton(hasEnoughMoney, isRefund),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
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
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.local_parking_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bãi đỗ Cầu Giấy',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '144 Xuân Thủy, Cầu Giấy, Hà Nội',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Vị trí: ${widget.spot.code}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard(bool hasEnoughMoney, bool isRefund) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Số dư ví của bạn',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
                      fontSize: 10,
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
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: hasEnoughMoney ? AppColors.textDark : AppColors.danger,
            ),
          ),
          // Chỉ hiển thị nạp tiền khi ví cần thanh toán và không đủ tiền
          if (!isRefund && !hasEnoughMoney) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'Nạp tiền nhanh (Giả lập demo):',
              style: TextStyle(
                fontSize: 12,
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text(
                      '+50k',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _topUpMoney(100000),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text(
                      '+100k',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _topUpMoney(200000),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text(
                      '+200k',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBillSummaryCard(int amount, bool isRefund) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Chi tiết quyết toán',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Loại hình', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
              Text(widget.transactionType, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isRefund ? 'Tiền được hoàn lại' : 'Tiền cần đóng thêm', style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
              Text(
                _formatMoney(amount.abs()),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isRefund ? Colors.blue.shade700 : AppColors.danger,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isRefund ? 'Tổng nhận về' : 'Tổng thanh toán',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textDark),
              ),
              Text(
                _formatMoney(amount),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isRefund ? Colors.blue.shade700 : AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGateWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7), // Màu vàng cam pastel nhạt
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), width: 1.5),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LƯU Ý QUAN TRỌNG',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB45309),
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Vui lòng di chuyển xe của bạn đến sát cổng kiểm soát (Barie lối ra) trước khi bấm xác nhận. Khi bạn bấm xác nhận, cổng barie sẽ tự động mở để xe rời bãi.',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton(bool hasEnoughMoney, bool isRefund) {
    String btnText = 'XÁC NHẬN RỜI BÃI & MỞ CỔNG';
    if (widget.amount > 0) {
      btnText = 'XÁC NHẬN THANH TOÁN & MỞ CỔNG';
    } else if (isRefund) {
      btnText = 'XÁC NHẬN NHẬN TIỀN & MỞ CỔNG';
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: (_isProcessing || !hasEnoughMoney) ? null : _handleConfirmPayment,
        style: ElevatedButton.styleFrom(
          backgroundColor: isRefund ? Colors.blue.shade700 : AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26), // Pill-shaped
          ),
          elevation: 1.5,
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                hasEnoughMoney ? btnText : 'SỐ DƯ VÍ KHÔNG ĐỦ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}
