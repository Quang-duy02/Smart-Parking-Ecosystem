import '../models/booking.dart';
import '../models/payment.dart';

class BookingService {
  BookingService._privateConstructor();

  static final BookingService instance = BookingService._privateConstructor();

  final List<Booking> _bookings = [];
  final List<Payment> _payments = [];

  List<Booking> getBookings() {
    return List.unmodifiable(_bookings.reversed);
  }

  List<Payment> getPayments() {
    return List.unmodifiable(_payments.reversed);
  }

  void addBooking({
    required Booking booking,
    required Payment payment,
  }) {
    _bookings.add(booking);
    _payments.add(payment);
  }

  void clearHistory() {
    _bookings.clear();
    _payments.clear();
  }
}