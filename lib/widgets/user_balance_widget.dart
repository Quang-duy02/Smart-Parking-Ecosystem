import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class UserBalanceWidget extends StatelessWidget {
  const UserBalanceWidget({super.key});

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

  void _showTopUpDialog(BuildContext context, String uid, int currentBalance) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nạp tiền tài khoản'),
        content: const Text('Bạn có muốn nạp thêm 100.000đ vào số dư tài khoản để thử nghiệm?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final ref = FirebaseDatabase.instance.ref('smart_parking_system/users/$uid');
                await ref.update({
                  'balance': currentBalance + 100000,
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nạp tiền thành công! +100.000đ'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lỗi nạp tiền: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Nạp 100k'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final ref = FirebaseDatabase.instance.ref('smart_parking_system/users/${user.uid}/balance');

    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Lỗi đọc số dư: ${snapshot.error}');
        }

        int balance = 0;
        bool hasData = snapshot.hasData && snapshot.data?.snapshot.value != null;

        if (hasData) {
          balance = int.tryParse(snapshot.data!.snapshot.value.toString()) ?? 0;
        } else if (snapshot.connectionState == ConnectionState.active) {
          // Nếu kết nối đã hoạt động nhưng dữ liệu null, tự động khởi tạo số dư 100k
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final refInit = FirebaseDatabase.instance.ref('smart_parking_system/users/${user.uid}');
            refInit.update({
              'name': user.displayName ?? 'Người dùng',
              'email': user.email ?? '',
              'balance': 100000,
            });
          });
          balance = 100000;
        }

        return InkWell(
          onTap: () => _showTopUpDialog(context, user.uid, balance),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet, color: AppColors.success, size: 18),
                const SizedBox(width: 6),
                Text(
                  formatMoney(balance),
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.add_circle_outline, color: AppColors.success, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }
}
