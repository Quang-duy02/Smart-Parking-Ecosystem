import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/parking_spot.dart';
import '../utils/app_colors.dart';
import '../utils/mock_parking_data.dart';
import '../widgets/parking_spot_card.dart';
import 'package:url_launcher/url_launcher.dart';

class MainScreen extends StatefulWidget {
  final String userEmail;

  const MainScreen({super.key, required this.userEmail});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  String _selectedZone = 'Cầu Giấy';
  String _selectedMapZone = 'Cầu Giấy';
  final MapController _mapController = MapController();
  bool _isGettingLocation = false;
  bool _isBufferAlertOpen = false;
  bool _isGateDialogOpen = false;
  StreamSubscription<DatabaseEvent>? _slotsSubscription;
  StreamSubscription<DatabaseEvent>? _gateSubscription;

  @override
  void initState() {
    super.initState();
    _initSlotsSubscription();
    _initGateSubscription();
  }

  @override
  void dispose() {
    _slotsSubscription?.cancel();
    _gateSubscription?.cancel();
    super.dispose();
  }

  void _logout() {
    FirebaseAuth.instance.signOut();
  }

  void _initGateSubscription() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    _gateSubscription = FirebaseDatabase.instance
        .ref('smart_parking_system/metadata/car_at_entry_gate')
        .onValue
        .listen((event) async {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return;

      final carAtGate = snapshot.value as bool? ?? false;
      if (carAtGate && !_isGateDialogOpen) {
        // Kiểm tra xem user đang đăng nhập có sở hữu ít nhất một Slot đang ở trạng thái isReserved == true và occupied == false
        final slotsSnapshot = await FirebaseDatabase.instance
            .ref('smart_parking_system/slots')
            .get();

        if (!slotsSnapshot.exists || slotsSnapshot.value == null) return;

        final Map<dynamic, dynamic> slotsMap;
        if (slotsSnapshot.value is Map) {
          slotsMap = slotsSnapshot.value as Map;
        } else if (slotsSnapshot.value is List) {
          final list = slotsSnapshot.value as List;
          slotsMap = {
            for (int i = 0; i < list.length; i++)
              if (list[i] != null) 'slot_${i + 1}': list[i],
          };
        } else {
          return;
        }

        bool hasActiveReservation = false;
        for (var key in slotsMap.keys) {
          final slotData = slotsMap[key];
          if (slotData is Map) {
            final reserved = slotData['reserved'] as bool? ?? false;
            final occupied = slotData['occupied'] as bool? ?? false;
            final userId = slotData['user_id'] as String? ?? '';

            if (userId == currentUid && reserved && !occupied) {
              hasActiveReservation = true;
              break;
            }
          }
        }

        if (hasActiveReservation) {
          _isGateDialogOpen = true;
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showGateOpenDialog();
            });
          }
        }
      }
    });
  }

  void _showGateOpenDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.directions_car_rounded, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Text(
                'BẠN ĐÃ ĐẾN BÃI ĐỖ?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: const Text(
            'Hệ thống phát hiện phương tiện của bạn đang ở trước Cổng Vào. Vui lòng xác nhận để mở Barie.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF2D3142),
              height: 1.5,
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          actions: [
            // Nút màu Xám: KHÔNG PHẢI TÔI
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'KHÔNG PHẢI TÔI',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            // Nút màu Xanh lá: XÁC NHẬN MỞ CỔNG
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                try {
                  await FirebaseDatabase.instance
                      .ref('smart_parking_system/metadata/gate_override')
                      .set(true);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đang mở cổng, vui lòng lái xe vào bãi',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: AppColors.success,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Lỗi ghi gate_override: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'XÁC NHẬN MỞ CỔNG',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isGateDialogOpen = false;
    });
  }



  int _getMockEmptyCount(int id) {
    final list = MockParkingData.spots[id] ?? [];
    return list.where((s) => s.status == ParkingSpotStatus.available).length;
  }

  String formatMoney(int value) {
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

  String formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$min';
  }

  @override
  Widget build(BuildContext context) {
    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _buildBody(currentUid),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.primary),
              label: 'Trang chủ',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.map_rounded, color: AppColors.primary),
              label: 'Bản đồ',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.history_rounded, color: AppColors.primary),
              label: 'Lịch sử',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded, color: AppColors.textGrey),
              selectedIcon: Icon(Icons.person_rounded, color: AppColors.primary),
              label: 'Cá nhân',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String uid) {
    switch (_currentIndex) {
      case 0:
        return _buildDashboardTab(uid);
      case 1:
        return _buildMapTab();
      case 2:
        return _buildHistoryTab(uid);
      case 3:
        return _buildProfileTab(uid);
      default:
        return _buildDashboardTab(uid);
    }
  }

  void _initSlotsSubscription() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    _slotsSubscription = FirebaseDatabase.instance
        .ref('smart_parking_system/slots')
        .onValue
        .listen((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return;

      final Map<dynamic, dynamic> slotsMap;
      if (snapshot.value is Map) {
        slotsMap = snapshot.value as Map;
      } else if (snapshot.value is List) {
        final list = snapshot.value as List;
        slotsMap = {
          for (int i = 0; i < list.length; i++)
            if (list[i] != null) 'slot_${i + 1}': list[i],
        };
      } else {
        return;
      }

      // 1. Kiểm tra cảnh báo cướp chỗ (Buffer Activation) trên slot_4
      final slot4Data = slotsMap['slot_4'];
      if (slot4Data is Map) {
        final paymentStatus = slot4Data['payment_status'] as String? ?? 'none';
        final userId = slot4Data['user_id'] as String? ?? '';
        
        if (paymentStatus == 'buffer_activate_request' &&
            userId == currentUid &&
            !_isBufferAlertOpen) {
          _isBufferAlertOpen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showBufferAlertDialog(currentUid);
          });
        }
      }
    });
  }



  void _showBufferAlertDialog(String uid) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text(
                'CẢNH BÁO: BỊ CHIẾM CHỖ ĐỖ!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: const Text(
            'Rất xin lỗi! Ô đỗ của bạn đã bị phương tiện khác chiếm dụng. '
            'Hệ thống đã tự động dời lịch đặt của bạn sang Ô DỰ PHÒNG (Slot 4). Vui lòng di chuyển đến Slot 4.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF2D3142),
              height: 1.5,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                
                try {
                  await FirebaseDatabase.instance
                      .ref('smart_parking_system/slots/slot_4')
                      .update({'payment_status': 'none'});
                } catch (e) {
                  debugPrint('Lỗi cập nhật payment_status của slot_4: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'TÔI ĐÃ HIỂU',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isBufferAlertOpen = false;
    });
  }



  // TAB 0: TRANG CHỦ DASHBOARD
  Widget _buildDashboardTab(String uid) {
    final slotsStream = FirebaseDatabase.instance.ref('smart_parking_system/slots').onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return <ParkingSpot>[];
      }

      final Map<dynamic, dynamic> slotsMap;
      if (snapshot.value is Map) {
        slotsMap = snapshot.value as Map;
      } else if (snapshot.value is List) {
        final list = snapshot.value as List;
        slotsMap = {
          for (int i = 0; i < list.length; i++)
            if (list[i] != null) 'slot_${i + 1}': list[i],
        };
      } else {
        return <ParkingSpot>[];
      }

      final List<ParkingSpot> spots = [];
      final sortedKeys = slotsMap.keys.map((k) => k.toString()).toList()..sort();

      for (var key in sortedKeys) {
        final slotData = slotsMap[key];
        if (slotData is Map) {
          final occupied = slotData['occupied'] as bool? ?? false;
          final reserved = slotData['reserved'] as bool? ?? false;
          final paymentStatus = slotData['payment_status'] as String? ?? 'none';
          final userId = slotData['user_id'] as String? ?? '';
          final transactionAmount = int.tryParse(slotData['transaction_amount']?.toString() ?? '0') ?? 0;
          final expectedDuration = int.tryParse(slotData['expected_duration']?.toString() ?? '0') ?? 0;
          int rawStartTime = int.tryParse(slotData['booking_start_time']?.toString() ?? '0') ?? 0;
          if (rawStartTime > 9999999999) {
            rawStartTime = rawStartTime ~/ 1000;
          }
          final bookingStartTime = rawStartTime;
          final idString = key.replaceAll(RegExp(r'[^0-9]'), '');
          final id = int.tryParse(idString) ?? 0;
          final code = 'Ô A$id';

          ParkingSpotStatus status = ParkingSpotStatus.available;
          if (paymentStatus == 'violation' ||
              paymentStatus == 'pending_payment' ||
              paymentStatus == 'extra_charge_pending' ||
              paymentStatus == 'settlement_pending') {
            status = ParkingSpotStatus.violationOrPending;
          } else if (occupied) {
            status = ParkingSpotStatus.occupied;
          } else if (reserved) {
            status = ParkingSpotStatus.reserved;
          }

          spots.add(
            ParkingSpot(
              id: id,
              code: code,
              status: status,
              occupied: occupied,
              userId: userId,
              paymentStatus: paymentStatus,
              transactionAmount: transactionAmount,
              expectedDuration: expectedDuration,
              bookingStartTime: bookingStartTime,
            ),
          );
        }
      }
      return spots;
    });

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('smart_parking_system/users/$uid').onValue,
      builder: (context, userSnapshot) {
        String name = 'Khách hàng';
        String codeText = 'MSV: SP-${uid.substring(0, 5).toUpperCase()}';
        String classText = 'Hạng thành viên: VIP';

        if (userSnapshot.hasData && userSnapshot.data!.snapshot.value != null) {
          final data = userSnapshot.data!.snapshot.value as Map?;
          if (data != null) {
            name = data['name']?.toString() ?? 'Khách hàng';
            codeText = 'Tài khoản: ${data['email']?.toString() ?? widget.userEmail}';
          }
        }

        int selectedLotId = 1;
        if (_selectedZone == 'Mỹ Đình') {
          selectedLotId = 2;
        } else if (_selectedZone == 'Hoàn Kiếm') {
          selectedLotId = 3;
        } else if (_selectedZone == 'Ba Đình') {
          selectedLotId = 4;
        }

        final Stream<List<ParkingSpot>> currentSpotsStream = selectedLotId == 1
            ? slotsStream
            : Stream.value(MockParkingData.spots[selectedLotId] ?? []);

        return StreamBuilder<List<ParkingSpot>>(
          stream: currentSpotsStream,
          builder: (context, spotsSnapshot) {
            final spots = spotsSnapshot.data ?? [];
            final int emptyCount = spots.where((s) => s.status == ParkingSpotStatus.available).length;
            final int myReservedCount = spots.where((s) => s.userId == uid && s.status == ParkingSpotStatus.reserved).length;
            final String todayStr = DateFormat('dd/MM').format(DateTime.now());

            final double screenWidth = MediaQuery.of(context).size.width;
            int crossAxisCount = 2;
            double childAspectRatio = 1.25;

            if (screenWidth > 800) {
              crossAxisCount = 4;
              childAspectRatio = 1.35;
            } else if (screenWidth > 550) {
              crossAxisCount = 3;
              childAspectRatio = 1.25;
            } else {
              crossAxisCount = 2;
              childAspectRatio = 1.25;
            }

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header (Screen 2 style)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                codeText,
                                style: const TextStyle(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                classText,
                                style: const TextStyle(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            // Notification Button
                            GestureDetector(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Không có thông báo mới.')),
                                );
                              },
                              child: Stack(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.notifications_none_rounded, color: AppColors.textDark, size: 22),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: AppColors.danger,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Text(
                                        '2',
                                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // QR Scanner Icon Button
                            GestureDetector(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Tính năng quét QR đang được nâng cấp.')),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 22),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Top Row Stats (4 Cards - Screen 2 style)
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildStatCard(Icons.check_circle_outline_rounded, '$emptyCount', 'Ô trống', const Color(0xFF10B981)),
                        _buildStatCard(Icons.bookmark_added_outlined, '$myReservedCount', 'Đã đặt của tôi', const Color(0xFFF59E0B)),
                        _buildStatCard(Icons.chat_bubble_outline_rounded, '0', 'Phản hồi', const Color(0xFF3B82F6)),
                        _buildStatCard(Icons.schedule_rounded, todayStr, 'Hôm nay', const Color(0xFF8B5CF6)),
                      ],
                    ),
                  ),
                ),
                // Zone Switcher / Tab List & Layout Heading
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          // App Icon style Switchers
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildZoneIconApp('Cầu Giấy', Icons.local_parking_rounded, '$emptyCount Trống', AppColors.primary, AppColors.primary.withValues(alpha: 0.1), AppColors.primary),
                              _buildZoneIconApp('Mỹ Đình', Icons.local_parking_rounded, '${_getMockEmptyCount(2)} Trống', AppColors.primary, AppColors.primary.withValues(alpha: 0.1), AppColors.primary),
                              _buildZoneIconApp('Hoàn Kiếm', Icons.local_parking_rounded, '${_getMockEmptyCount(3)} Trống', AppColors.primary, AppColors.primary.withValues(alpha: 0.1), AppColors.primary),
                              _buildZoneIconApp('Ba Đình', Icons.local_parking_rounded, '${_getMockEmptyCount(4)} Trống', AppColors.primary, AppColors.primary.withValues(alpha: 0.1), AppColors.primary),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'DANH SÁCH Ô ĐỖ - $_selectedZone',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 14),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Spot grid list (or list of cards)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: spots.isEmpty
                      ? const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: childAspectRatio,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return ParkingSpotCard(spot: spots[index]);
                            },
                            childCount: spots.length,
                          ),
                        ),
                ),
                // Quick Access (Truy cập nhanh)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TRUY CẬP NHANH',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            TextButton(
                              onPressed: () {},
                              child: const Text(
                                'Ghim >',
                                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildQuickAccessBtn(Icons.bookmark_added_rounded, 'Đặt lịch', const Color(0xFFE0F2FE), Colors.blue),
                            _buildQuickAccessBtn(Icons.account_balance_wallet_rounded, 'Ví của tôi', const Color(0xFFF3E8FF), Colors.purple),
                            _buildQuickAccessBtn(Icons.history_rounded, 'Lịch sử', const Color(0xFFFCE7F3), Colors.pink),
                            _buildQuickAccessBtn(Icons.help_rounded, 'Hỗ trợ', const Color(0xFFDCFCE7), Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
    return Container(
      width: 104,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneIconApp(
    String zone,
    IconData icon,
    String statusText,
    Color activeColor,
    Color badgeBgColor,
    Color badgeTextColor,
  ) {
    final bool isSelected = _selectedZone == zone;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedZone = zone;
        });
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isSelected ? activeColor.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? activeColor : Colors.grey.shade100,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected ? activeColor : Colors.grey.shade400,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    color: isSelected ? badgeTextColor : Colors.grey.shade500,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            zone,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppColors.textDark : AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessBtn(IconData icon, String label, Color bgColor, Color iconColor) {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Stream<List<ParkingSpot>> _getSpotsStream() {
    return FirebaseDatabase.instance.ref('smart_parking_system/slots').onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return <ParkingSpot>[];
      }

      final Map<dynamic, dynamic> slotsMap;
      if (snapshot.value is Map) {
        slotsMap = snapshot.value as Map;
      } else if (snapshot.value is List) {
        final list = snapshot.value as List;
        slotsMap = {
          for (int i = 0; i < list.length; i++)
            if (list[i] != null) 'slot_${i + 1}': list[i],
        };
      } else {
        return <ParkingSpot>[];
      }

      final List<ParkingSpot> spots = [];
      final sortedKeys = slotsMap.keys.map((k) => k.toString()).toList()..sort();

      for (var key in sortedKeys) {
        final slotData = slotsMap[key];
        if (slotData is Map) {
          final occupied = slotData['occupied'] as bool? ?? false;
          final reserved = slotData['reserved'] as bool? ?? false;
          final paymentStatus = slotData['payment_status'] as String? ?? 'none';
          final userId = slotData['user_id'] as String? ?? '';
          final transactionAmount = int.tryParse(slotData['transaction_amount']?.toString() ?? '0') ?? 0;
          final expectedDuration = int.tryParse(slotData['expected_duration']?.toString() ?? '0') ?? 0;
          int rawStartTime = int.tryParse(slotData['booking_start_time']?.toString() ?? '0') ?? 0;
          if (rawStartTime > 9999999999) {
            rawStartTime = rawStartTime ~/ 1000;
          }
          final bookingStartTime = rawStartTime;
          final idString = key.replaceAll(RegExp(r'[^0-9]'), '');
          final id = int.tryParse(idString) ?? 0;
          final code = 'Ô A$id';

          ParkingSpotStatus status = ParkingSpotStatus.available;
          if (paymentStatus == 'violation' ||
              paymentStatus == 'pending_payment' ||
              paymentStatus == 'extra_charge_pending' ||
              paymentStatus == 'settlement_pending') {
            status = ParkingSpotStatus.violationOrPending;
          } else if (occupied) {
            status = ParkingSpotStatus.occupied;
          } else if (reserved) {
            status = ParkingSpotStatus.reserved;
          }

          spots.add(
            ParkingSpot(
              id: id,
              code: code,
              status: status,
              occupied: occupied,
              userId: userId,
              paymentStatus: paymentStatus,
              transactionAmount: transactionAmount,
              expectedDuration: expectedDuration,
              bookingStartTime: bookingStartTime,
            ),
          );
        }
      }
      return spots;
    });
  }

  int _getLotIdFromName(String name) {
    if (name == 'Mỹ Đình') {
      return 2;
    }
    if (name == 'Hoàn Kiếm') {
      return 3;
    }
    if (name == 'Ba Đình') {
      return 4;
    }
    return 1;
  }

  LatLng _getLotCoordinate(int lotId) {
    switch (lotId) {
      case 1:
        return const LatLng(21.037814, 105.781313);
      case 2:
        return const LatLng(21.0185, 105.7740);
      case 3:
        return const LatLng(21.0285, 105.8542);
      case 4:
        return const LatLng(21.0368, 105.8346);
      default:
        return const LatLng(21.037814, 105.781313);
    }
  }

  String _getLotName(int lotId) {
    switch (lotId) {
      case 1:
        return 'Bãi đỗ Cầu Giấy';
      case 2:
        return 'Bãi đỗ Mỹ Đình';
      case 3:
        return 'Bãi đỗ Hoàn Kiếm';
      case 4:
        return 'Bãi đỗ Ba Đình';
      default:
        return 'Bãi đỗ Cầu Giấy';
    }
  }

  String _getLotAddress(int lotId) {
    switch (lotId) {
      case 1:
        return '144 Xuân Thủy, Cầu Giấy, Hà Nội';
      case 2:
        return 'Sân vận động Mỹ Đình, Nam Từ Liêm, Hà Nội';
      case 3:
        return 'Hồ Hoàn Kiếm, Lý Thái Tổ, Hà Nội';
      case 4:
        return 'Quảng trường Ba Đình, Hùng Vương, Hà Nội';
      default:
        return '144 Xuân Thủy, Cầu Giấy, Hà Nội';
    }
  }

  Future<void> _startNavigation(LatLng destination) async {
    setState(() {
      _isGettingLocation = true;
    });

    double lat = 0.0;
    double lng = 0.0;
    bool hasLocation = false;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
          lat = position.latitude;
          lng = position.longitude;
          hasLocation = true;
        }
      }
    } catch (e) {
      debugPrint('Lỗi geolocator: $e');
    }

    setState(() {
      _isGettingLocation = false;
    });

    final String urlString = hasLocation
        ? 'https://www.google.com/maps/dir/?api=1&origin=$lat,$lng&destination=${destination.latitude},${destination.longitude}'
        : 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}';

    final Uri url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở Google Maps. Vui lòng thử lại.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi launcher: $e');
    }
  }

  Widget _buildMapSection(int lotId, int cauGiayEmptyCount) {
    final LatLng coord = _getLotCoordinate(lotId);
    final String lotName = _getLotName(lotId);
    final String lotAddress = _getLotAddress(lotId);

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chỉ đường vệ tinh',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.directions_rounded, color: Colors.blue.shade700, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Định vị GPS',
                        style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Bản đồ OpenStreetMap thực tế
            Container(
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: coord,
                  initialZoom: 16.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.APPSmartpak.smart_parking_app',
                  ),
                  MarkerLayer(
                    markers: [1, 2, 3, 4].map((id) {
                      final LatLng p = _getLotCoordinate(id);
                      final String name = _getLotName(id);
                      final bool isSelected = (id == lotId);
                      final int emptyCount = id == 1 ? cauGiayEmptyCount : _getMockEmptyCount(id);
                      
                      return Marker(
                        point: p,
                        width: 140,
                        height: 90,
                        child: GestureDetector(
                          onTap: () {
                            final zoneName = (id == 1
                                ? 'Cầu Giấy'
                                : (id == 2 ? 'Mỹ Đình' : (id == 3 ? 'Hoàn Kiếm' : 'Ba Đình')));
                            setState(() {
                              _selectedMapZone = zoneName;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _mapController.move(p, 16.0);
                            });
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.red.shade600 : Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.grey.shade400,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.local_parking_rounded,
                                  color: isSelected ? Colors.white : Colors.grey.shade700,
                                  size: isSelected ? 20 : 16,
                                ),
                              ),
                              Card(
                                color: isSelected ? Colors.red.shade600 : Colors.white,
                                elevation: isSelected ? 4 : 2,
                                margin: const EdgeInsets.only(top: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected ? Colors.red.shade600 : Colors.grey.shade300,
                                    width: isSelected ? 1 : 0.5,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Text(
                                    '$name\n($emptyCount trống)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isSelected ? 8.5 : 7.5,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              lotName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark),
            ),
            Text(
              lotAddress,
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isGettingLocation ? null : () => _startNavigation(coord),
              icon: _isGettingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.navigation_rounded, size: 18, color: Colors.white),
              label: Text(
                _isGettingLocation ? 'ĐANG LẤY TỌA ĐỘ GPS...' : 'BẮT ĐẦU CHỈ ĐƯỜNG',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParkingLayout(int lotId, List<ParkingSpot> spots) {
    final String zoneLabel = lotId == 1
        ? 'Bãi Cầu Giấy'
        : (lotId == 2
            ? 'Bãi Mỹ Đình'
            : (lotId == 3 ? 'Bãi Hoàn Kiếm' : 'Bãi Ba Đình'));

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sơ đồ bãi đỗ thực tế',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    zoneLabel,
                    style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Khung bãi đỗ xe
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200, width: 2),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // CỔNG VÀO ở trên
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_downward_rounded, color: Colors.grey.shade400, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'CỔNG VÀO (BARIE CHỜ)',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 4 Ô đỗ xe
                  spots.isEmpty
                      ? const SizedBox(
                          height: 200,
                          child: Center(child: Text('Không có dữ liệu ô đỗ')),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: spots.length > 4 ? 4 : spots.length,
                          itemBuilder: (context, index) {
                            final spot = spots[index];
                            return ParkingSpotCard(spot: spot);
                          },
                        ),
                  
                  const SizedBox(height: 16),
                  // CỔNG RA ở dưới
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_upward_rounded, color: Colors.grey.shade400, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'LỐI RA (BARIE KIỂM SOÁT)',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegendItem('Trống', AppColors.success),
                _buildLegendItem('Có xe', const Color(0xFF1E3A8A)),
                _buildLegendItem('Đặt trước', AppColors.warning),
                _buildLegendItem('Cảnh báo', AppColors.danger),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapTab() {
    final slotsStream = _getSpotsStream();

    return StreamBuilder<List<ParkingSpot>>(
      stream: slotsStream,
      builder: (context, cauGiaySnapshot) {
        final cauGiaySpots = cauGiaySnapshot.data ?? [];
        final int cauGiayEmptyCount = cauGiaySpots.where((s) => s.status == ParkingSpotStatus.available).length;

        final int selectedLotId = _getLotIdFromName(_selectedMapZone);

        final List<ParkingSpot> currentSpots = selectedLotId == 1
            ? cauGiaySpots
            : (MockParkingData.spots[selectedLotId] ?? []);

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isWeb = screenWidth > 800;

        final Widget mapSection = _buildMapSection(selectedLotId, cauGiayEmptyCount);
        final Widget parkingLayout = _buildParkingLayout(selectedLotId, currentSpots);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BẢN ĐỒ BÃI ĐỖ',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Theo dõi sơ đồ ô đỗ thời gian thực và chỉ đường vệ tinh.',
                  style: TextStyle(fontSize: 13, color: AppColors.textGrey),
                ),
                const SizedBox(height: 20),

                isWeb
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: mapSection),
                          const SizedBox(width: 20),
                          Expanded(flex: 6, child: parkingLayout),
                        ],
                      )
                    : Column(
                        children: [
                          mapSection,
                          const SizedBox(height: 20),
                          parkingLayout,
                        ],
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textGrey, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // TAB 2: LỊCH SỬ GIAO DỊCH
  Widget _buildHistoryTab(String uid) {
    if (uid.isEmpty) {
      return const Center(child: Text('Vui lòng đăng nhập để xem lịch sử'));
    }
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('smart_parking_system/users/$uid/history').onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('Lỗi tải lịch sử giao dịch'));
        }

        final List<Map<dynamic, dynamic>> items = [];
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final val = snapshot.data!.snapshot.value;
          if (val is Map) {
            val.forEach((k, v) {
              if (v is Map) {
                items.add(v);
              }
            });
          }
        }

        items.sort((a, b) {
          final tA = a['timestamp'] as int? ?? 0;
          final tB = b['timestamp'] as int? ?? 0;
          return tB.compareTo(tA);
        });

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.history_toggle_off_rounded, size: 64, color: AppColors.textGrey),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Chưa có giao dịch nào',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final amount = item['amount'] as int? ?? 0;
            final slotName = item['slot_name'] as String? ?? 'N/A';
            final statusText = item['status'] as String? ?? 'Thanh toán';
            final timestamp = item['timestamp'] as int? ?? 0;

            final isCredit = amount < 0 || statusText == 'Nạp tiền';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isCredit
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.textDark.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCredit ? Icons.add_circle_outline_rounded : Icons.check_circle_outline_rounded,
                      color: isCredit ? AppColors.primary : AppColors.textDark,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$statusText - $slotName',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatDate(timestamp),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    isCredit ? '+${formatMoney(amount.abs())}' : '-${formatMoney(amount)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isCredit ? AppColors.primary : AppColors.textDark,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // TAB 3: CÁ NHÂN (Screen 3 style)
  Widget _buildProfileTab(String uid) {
    if (uid.isEmpty) {
      return const Center(child: Text('Vui lòng đăng nhập để xem thông tin'));
    }
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('smart_parking_system/users/$uid').onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        String name = 'Khách hàng';
        String email = widget.userEmail;
        int balance = 0;

        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final data = snapshot.data!.snapshot.value as Map?;
          if (data != null) {
            name = data['name']?.toString() ?? 'Khách hàng';
            email = data['email']?.toString() ?? widget.userEmail;
            balance = int.tryParse(data['balance']?.toString() ?? '0') ?? 0;
          }
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          physics: const BouncingScrollPhysics(),
          children: [
            // User basic profile row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${uid.substring(0, 10).toUpperCase()}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        email,
                        style: const TextStyle(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const ClipOval(
                    child: Icon(Icons.person_rounded, size: 36, color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Green Stats Bar (Emerald bar style)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildStatCol('12', 'Lượt đỗ'),
                  _buildStatDivider(),
                  _buildStatCol(formatMoney(balance), 'Ví số dư'),
                  _buildStatDivider(),
                  _buildStatCol('Vàng', 'Hạng thành viên'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Profile Options Menu (Screen 3 style)
            _buildProfileMenu(Icons.person_outline_rounded, Colors.blue, 'Thông tin cá nhân'),
            _buildProfileMenu(Icons.history_rounded, Colors.green, 'Lịch sử giao dịch'),
            _buildProfileMenu(Icons.directions_car_filled_rounded, Colors.orange, 'Phương tiện của tôi'),
            
            // Top-up wallet option built beautifully
            _buildTopupMenu(uid, balance),
            
            _buildProfileMenu(Icons.security_rounded, Colors.teal, 'Cài đặt ví điện tử'),
            _buildProfileMenu(Icons.lock_outline_rounded, Colors.indigo, 'Bảo mật & Mật khẩu'),
            _buildProfileMenu(Icons.info_outline_rounded, Colors.green, 'Phiên bản: 2.0.4'),
            const SizedBox(height: 16),
            // Logout
            ElevatedButton(
              onPressed: _logout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger.withValues(alpha: 0.06),
                foregroundColor: AppColors.danger,
                elevation: 0,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Đăng xuất tài khoản', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildStatCol(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1.5,
      height: 28,
      color: Colors.white.withValues(alpha: 0.25),
    );
  }

  Widget _buildProfileMenu(IconData icon, Color iconColor, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 14),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textGrey),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chức năng "$title" đang phát triển.')),
          );
        },
      ),
    );
  }

  Widget _buildTopupMenu(String uid, int balance) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add_card_rounded, color: Colors.purple, size: 20),
        ),
        title: const Text(
          'Nạp tiền vào ví (+50K)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 14),
        ),
        trailing: const Icon(Icons.add_rounded, size: 18, color: Colors.purple),
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final userRef = FirebaseDatabase.instance.ref('smart_parking_system/users/$uid');
          final balanceRef = userRef.child('balance');
          final historyRef = userRef.child('history');
          try {
            await Future.wait([
              balanceRef.set(balance + 50000),
              historyRef.push().set({
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'slot_name': 'Nạp ví',
                'amount': -50000,
                'status': 'Nạp tiền',
              }),
            ]);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Đã nạp 50.000đ vào tài khoản!'),
                backgroundColor: AppColors.success,
              ),
            );
          } catch (e) {
            debugPrint('Lỗi nạp ví: $e');
          }
        },
      ),
    );
  }
}

