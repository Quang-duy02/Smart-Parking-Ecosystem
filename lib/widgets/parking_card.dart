import 'package:flutter/material.dart';

import '../models/parking_lot.dart';
import '../utils/app_colors.dart';

class ParkingCard extends StatelessWidget {
  final ParkingLot parkingLot;
  final VoidCallback onTap;

  const ParkingCard({super.key, required this.parkingLot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final double percent = parkingLot.availableSpots / parkingLot.totalSpots;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                height: 62,
                width: 62,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.local_parking_rounded,
                  color: AppColors.primary,
                  size: 36,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildInfo(percent)),
              const Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfo(double percent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parkingLot.name,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          parkingLot.address,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textGrey),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 7,
            backgroundColor: Colors.grey.shade200,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Còn ${parkingLot.availableSpots}/${parkingLot.totalSpots} chỗ - ${parkingLot.pricePerHour} VNĐ/giờ',
          style: const TextStyle(
            color: AppColors.success,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
