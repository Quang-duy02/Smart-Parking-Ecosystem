import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import '../models/parking_lot.dart';
import '../models/parking_spot.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import 'payment_screen.dart';
import '../widgets/user_balance_widget.dart';
import 'booking_screen.dart';

class ParkingDetailScreen extends StatefulWidget {
  final ParkingLot parkingLot;

  const ParkingDetailScreen({super.key, required this.parkingLot});

  @override
  State<ParkingDetailScreen> createState() => _ParkingDetailScreenState();
}

class _ParkingDetailScreenState extends State<ParkingDetailScreen> {
  final ApiService apiService = ApiService();

  late Stream<List<ParkingSpot>> parkingSpotsStream;
  bool _isLoadingLocation = false;
  
  Timer? _periodicTimer;
  List<ParkingSpot> _currentSpots = [];
  BuildContext? _extensionDialogContext;
  int? _lastRemindedTime;
  BuildContext? _currentLoadingContext;

  void _showLoading() {
    _hideLoading(); // Đóng loading cũ nếu có
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _currentLoadingContext = dialogCtx;
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  void _hideLoading() {
    if (_currentLoadingContext != null) {
      try {
        Navigator.of(_currentLoadingContext!).pop();
      } catch (e) {
        debugPrint('Lỗi đóng loading: $e');
      }
      _currentLoadingContext = null;
    }
  }

  @override
  void initState() {
    super.initState();
    parkingSpotsStream = apiService.getParkingSpotsStream(widget.parkingLot.id);
    _periodicTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {}); // Trigger rebuild để cập nhật đếm ngược thực tế
        _checkDemoBookingExtension();
      }
    });
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
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

  Future<void> _bookSlot(ParkingSpot spot) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để thực hiện đặt chỗ')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingScreen(
          spot: spot,
          parkingLot: widget.parkingLot,
        ),
      ),
    );
  }


  Future<void> _handleSettlement(ParkingSpot spot) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Hiển thị loading
    _showLoading();

    int balance = 0;
    try {
      final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
      final balanceSnapshot = await balanceRef.get();
      balance = int.tryParse(balanceSnapshot.value?.toString() ?? '0') ?? 0;
    } catch (e) {
      debugPrint('Lỗi đọc số dư khi quyết toán: $e');
    }

    if (!mounted) return;
    _hideLoading(); // Tắt loading

    final amount = spot.transactionAmount;
    String dialogTitle = 'Quyết toán ô đỗ ${spot.code}';
    String message = '';
    
    if (amount < 0) {
      message = 'Bạn đã ra sớm hơn thời gian dự kiến.\nSố tiền được hoàn lại vào ví: ${formatMoney(amount.abs())}.';
    } else if (amount > 0) {
      message = 'Bạn đã đỗ xe quá thời gian dự kiến.\nSố tiền cần nộp thêm: ${formatMoney(amount)}.';
    } else {
      message = 'Thời gian đỗ xe khớp hoàn hảo với thời gian dự kiến.\nKhông phát sinh chi phí.';
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 16, color: AppColors.textDark)),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lưu ý: Quý khách vui lòng di chuyển xe đến sát cổng ra (thanh chắn Barie) trước khi bấm xác nhận để đảm bảo Barie mở đúng lúc xe đi qua.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              
              if (amount > 0 && balance < amount) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Số dư tài khoản không đủ để thanh toán phần lố giờ!'),
                    backgroundColor: AppColors.danger,
                  ),
                );
                return;
              }

              _showLoading();

              try {
                final newBalance = balance - amount;
                final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
                final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${spot.id}');
                final historyRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/history');

                await Future.wait([
                  balanceRef.set(newBalance),
                  historyRef.push().set({
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                    'slot_name': spot.code,
                    'amount': amount,
                    'status': 'Hoàn thành',
                  }),
                  slotRef.update({
                    'payment_status': 'paid',
                    'transaction_amount': 0,
                  }),
                ]);

                if (!mounted) return;
                _hideLoading(); // Tắt loading

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(amount < 0
                        ? 'Quyết toán thành công! Đã hoàn lại ${formatMoney(amount.abs())} vào ví.'
                        : (amount > 0
                            ? 'Thanh toán phụ trội thành công! Đã trừ ${formatMoney(amount)} từ ví.'
                            : 'Quyết toán thành công! Hãy di chuyển xe qua cổng.')),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                _hideLoading(); // Tắt loading
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi khi quyết toán: $e'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleWalkinPayment(ParkingSpot spot) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để thanh toán')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nhận xe & Thanh toán', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bạn có chắc chắn muốn thanh toán ${formatMoney(spot.transactionAmount)} cho chiếc xe vãng lai ở ô đỗ ${spot.code} không?'),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lưu ý: Quý khách vui lòng di chuyển xe đến sát cổng ra (thanh chắn Barie) trước khi bấm xác nhận để đảm bảo Barie mở đúng lúc xe đi qua.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              _showLoading();

              int balance = 0;
              try {
                final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
                final balanceSnapshot = await balanceRef.get();
                balance = int.tryParse(balanceSnapshot.value?.toString() ?? '0') ?? 0;
              } catch (e) {
                debugPrint('Lỗi đọc số dư: $e');
              }

              if (!mounted) return;
              _hideLoading(); // Tắt loading

              final amount = spot.transactionAmount;
              if (balance < amount) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Số dư không đủ, vui lòng nạp thêm!'),
                    backgroundColor: AppColors.danger,
                  ),
                );
                return;
              }

              _showLoading();

              try {
                final newBalance = balance - amount;
                final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
                final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${spot.id}');
                final historyRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/history');

                await Future.wait([
                  balanceRef.set(newBalance),
                  historyRef.push().set({
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                    'slot_name': spot.code,
                    'amount': amount,
                    'status': 'Hoàn thành',
                  }),
                  slotRef.update({
                    'user_id': currentUser.uid,
                    'payment_status': 'paid',
                  }),
                ]);

                if (!mounted) return;
                _hideLoading(); // Tắt loading

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Thanh toán thành công! Đã trừ ${formatMoney(amount)} từ ví. Barie đang mở.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                _hideLoading(); // Tắt loading
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi khi thanh toán xe vãng lai: $e'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  void _goToPayment(ParkingSpot spot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          parkingLot: widget.parkingLot,
          parkingSpot: spot,
        ),
      ),
    );
  }

  Future<void> _openDirections() async {
    try {
      // Bước a: Xin quyền truy cập vị trí bằng Geolocator.checkPermission() và Geolocator.requestPermission()
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quyền truy cập vị trí bị từ chối! Không thể chỉ đường.'),
              backgroundColor: AppColors.danger,
            ),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quyền truy cập vị trí bị từ chối vĩnh viễn! Vui lòng cấp quyền trong cài đặt.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      // Thay đổi chữ của nút thành "Đang tìm đường..." hoặc hiện biểu tượng loading
      setState(() {
        _isLoadingLocation = true;
      });

      // Bước b: Lấy tọa độ hiện tại của người dùng bằng Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final double userLat = position.latitude;
      final double userLng = position.longitude;

      // Bước c: Xây dựng URL Google Maps mới có CẢ điểm xuất phát (origin) VÀ điểm đến (destination)
      final Uri url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$userLat,$userLng&destination=${widget.parkingLot.latitude},${widget.parkingLot.longitude}',
      );

      // Bước d: Dùng url_launcher để mở cái URL đó ra (launchUrl)
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở bản đồ chỉ đường!'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi lấy GPS hoặc mở bản đồ: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi tìm đường: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Widget _buildMapHeader() {
    final double mapHeight = MediaQuery.of(context).size.height * 0.35;
    final LatLng parkingPosition = LatLng(widget.parkingLot.latitude, widget.parkingLot.longitude);

    return Container(
      height: mapHeight,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: parkingPosition,
                initialZoom: 16.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.smart_parking_app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: parkingPosition,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: FloatingActionButton.extended(
                onPressed: _isLoadingLocation ? null : _openDirections,
                backgroundColor: _isLoadingLocation ? Colors.grey : AppColors.primary,
                foregroundColor: Colors.white,
                icon: _isLoadingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.navigation_outlined, size: 20),
                label: Text(
                  _isLoadingLocation ? 'Đang tìm đường...' : 'Chỉ đường đến bãi',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parkingLot = widget.parkingLot;

    return Scaffold(
      appBar: AppBar(
        title: Text(parkingLot.name),
        actions: const [
          UserBalanceWidget(),
        ],
      ),
      body: Column(
        children: [
          _buildMapHeader(),
          Expanded(
            child: Column(
              children: [
                _buildLegend(),
                const SizedBox(height: 8),
                Expanded(child: _buildSpotGrid()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _checkDemoBookingExtension() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    bool hasActiveReserved = false;
    ParkingSpot? activeSpot;

    for (var spot in _currentSpots) {
      final bool isMySpot = spot.userId == currentUser.uid;
      if (spot.status == ParkingSpotStatus.reserved && isMySpot && spot.bookingStartTime > 0) {
        hasActiveReserved = true;
        activeSpot = spot;

        final int nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final int elapsedSeconds = nowSeconds - spot.bookingStartTime;

        // Nếu đạt 40 giây thực tế (và chưa quá 45 giây)
        if (elapsedSeconds >= 40 && elapsedSeconds < 45) {
          if (_lastRemindedTime != spot.bookingStartTime) {
            _lastRemindedTime = spot.bookingStartTime;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showDemoExtensionDialog(spot);
            });
          }
        }
        break; // Tại một thời điểm chỉ xử lý một lịch reserved của user hiện tại
      }
    }

    // Nếu không còn lịch reserved nào đang chờ (đã bị hủy hoặc xe đã vào đỗ), tự động đóng dialog nếu đang mở
    if (!hasActiveReserved || (activeSpot != null && _lastRemindedTime != activeSpot.bookingStartTime)) {
      if (_extensionDialogContext != null) {
        try {
          Navigator.of(_extensionDialogContext!).pop();
        } catch (e) {
          debugPrint('Lỗi đóng dialog: $e');
        }
        _extensionDialogContext = null;
      }
    }
  }

  void _showDemoExtensionDialog(ParkingSpot spot) {
    if (_extensionDialogContext != null) {
      try {
        Navigator.of(_extensionDialogContext!).pop();
      } catch (e) {
        debugPrint('Lỗi đóng dialog cũ: $e');
      }
      _extensionDialogContext = null;
    }

    BuildContext? currentDialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        currentDialogContext = dialogContext;
        _extensionDialogContext = dialogContext;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Cảnh báo quá hạn', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Xe của bạn chưa đến bãi! Quá hạn trong 5 giây nữa. Gia hạn thêm (5.000đ)?',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _extensionDialogContext = null;
                Navigator.pop(dialogContext);
              },
              child: const Text('Bỏ qua', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                _extensionDialogContext = null;
                Navigator.pop(dialogContext);
                await _extendBooking(spot);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Gia hạn'),
            ),
          ],
        );
      },
    ).then((_) {
      if (_extensionDialogContext == currentDialogContext) {
        _extensionDialogContext = null;
      }
    });
  }

  Future<void> _extendBooking(ParkingSpot spot) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    int balance = 0;
    try {
      final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
      final balanceSnapshot = await balanceRef.get();
      balance = int.tryParse(balanceSnapshot.value?.toString() ?? '0') ?? 0;
    } catch (e) {
      debugPrint('Lỗi đọc số dư: $e');
    }

    if (!mounted) return;
    Navigator.pop(context);

    const cost = 5000;
    if (balance < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số dư ví không đủ 5.000đ để gia hạn!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final newBalance = balance - cost;
      final balanceRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/balance');
      final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${spot.id}');
      final historyRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${currentUser.uid}/history');

      await Future.wait([
        balanceRef.set(newBalance),
        historyRef.push().set({
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'slot_name': spot.code,
          'amount': cost,
          'status': 'Gia hạn giữ chỗ',
        }),
        slotRef.update({
          'booking_start_time': ServerValue.timestamp,
        }),
      ]);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gia hạn giữ chỗ thành công!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi thực hiện gia hạn: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _legendItem(AppColors.success, 'Trống'),
          _legendItem(AppColors.warning, 'Đã đặt'),
          _legendItem(const Color(0xFF1E3A8A), 'Đang đỗ'),
          _legendItem(AppColors.danger, 'Cần thanh toán'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(text),
      ],
    );
  }

  Widget _buildSpotGrid() {
    return StreamBuilder<List<ParkingSpot>>(
      stream: parkingSpotsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('Không tải được danh sách chỗ đỗ'));
        }

        final spots = snapshot.data ?? [];
        _currentSpots = spots;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: spots.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.28,
          ),
          itemBuilder: (context, index) {
            final spot = spots[index];
            return _spotItem(spot: spot);
          },
        );
      },
    );
  }

  Widget _spotItem({required ParkingSpot spot}) {
    Color statusColor;
    String statusText;

    final bool isWalkinPending = spot.paymentStatus == 'pending_payment' && (spot.userId.isEmpty || spot.userId == '');
    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'user_id_tam_thoi_123';
    final bool isMySpot = spot.userId == currentUid;

    final bool isAwaitingCheckin = spot.paymentStatus == 'awaiting_checkin';

    if (isAwaitingCheckin) {
      statusColor = Colors.orange;
      statusText = 'Chờ xác nhận';
    } else if (isWalkinPending) {
      statusColor = AppColors.danger;
      statusText = 'XE VÃNG LAI CHỜ THANH TOÁN';
    } else if (spot.paymentStatus == 'settlement_pending') {
      statusColor = Colors.orange.shade800;
      statusText = 'Quyết toán';
    } else {
      switch (spot.status) {
        case ParkingSpotStatus.available:
          statusColor = AppColors.success;
          statusText = 'Trống';
          break;
        case ParkingSpotStatus.reserved:
          statusColor = AppColors.warning;
          statusText = 'Đã đặt';
          break;
        case ParkingSpotStatus.occupied:
          statusColor = const Color(0xFF1E3A8A);
          statusText = 'Đang đỗ';
          break;
        case ParkingSpotStatus.violationOrPending:
          statusColor = AppColors.danger;
          statusText = 'Cần thanh toán';
          break;
      }
    }

    Widget actionButton;

    if (isAwaitingCheckin) {
      actionButton = ElevatedButton.icon(
        onPressed: () async {
          _showLoading();
          try {
            final slotRef = FirebaseDatabase.instance.ref('smart_parking_system/slots/slot_${spot.id}');
            await slotRef.update({
              'payment_status': 'active',
            });
            if (!mounted) return;
            _hideLoading();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Xác nhận xe đã đến bãi đỗ thành công!'),
                backgroundColor: AppColors.success,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            _hideLoading();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi xác nhận checkin: $e'),
                backgroundColor: AppColors.danger,
              ),
            );
          }
        },
        icon: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        label: Text(
          (isMySpot || spot.userId.isEmpty) ? 'XÁC NHẬN TÔI ĐÃ ĐẾN BÃI' : 'XÁC NHẬN XE ĐÃ ĐẾN BÃI (HỘ)',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    } else if (isWalkinPending) {
      actionButton = ElevatedButton(
        onPressed: () => _handleWalkinPayment(spot),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          'NHẬN XE NÀY & THANH TOÁN: ${formatMoney(spot.transactionAmount)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold),
        ),
      );
    } else if (spot.paymentStatus == 'settlement_pending') {
      actionButton = ElevatedButton(
        onPressed: () => _handleSettlement(spot),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade800,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          (isMySpot || spot.userId.isEmpty) ? 'XÁC NHẬN RỜI BẾN' : 'XÁC NHẬN RỜI BẾN (HỘ)',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    } else if (spot.status == ParkingSpotStatus.available) {
      actionButton = ElevatedButton(
        onPressed: () => _bookSlot(spot),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'ĐẶT CHỖ',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      );
    } else if (isMySpot) {
      actionButton = ElevatedButton(
        onPressed: () => _goToPayment(spot),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'THANH TOÁN',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      actionButton = OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          'ĐÃ CÓ NGƯỜI ĐẶT',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade400,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    spot.code,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (isAwaitingCheckin) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                  ],
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          _buildTimeOrWalkinInfo(spot, isWalkinPending),
          const SizedBox(height: 4),
          actionButton,
        ],
      ),
    );
  }

  Widget _buildTimeOrWalkinInfo(ParkingSpot spot, bool isWalkinPending) {
    final bool isWalkin = isWalkinPending || 
        spot.paymentStatus == 'walkin_active' || 
        (spot.status == ParkingSpotStatus.occupied && spot.userId.isEmpty);

    if (spot.bookingStartTime > 0) {
      final start = DateTime.fromMillisecondsSinceEpoch(spot.bookingStartTime * 1000);
      final end = start.add(Duration(seconds: spot.expectedDuration));
      final hours = spot.expectedDuration ~/ 3600;
      final startStr = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
      final endStr = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
      
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Lịch: $startStr - $endStr ($hours Giờ)',
          textAlign: TextAlign.left,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    } else if (isWalkin) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Khách vãng lai',
          textAlign: TextAlign.left,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '',
        style: TextStyle(fontSize: 10.5),
      ),
    );
  }
}
