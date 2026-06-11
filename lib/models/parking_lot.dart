class ParkingLot {
  final int id;
  final String name;
  final String address;
  final int totalSpots;
  final int availableSpots;
  final int pricePerHour;
  final double latitude;
  final double longitude;

  const ParkingLot({
    required this.id,
    required this.name,
    required this.address,
    required this.totalSpots,
    required this.availableSpots,
    required this.pricePerHour,
    required this.latitude,
    required this.longitude,
  });
}