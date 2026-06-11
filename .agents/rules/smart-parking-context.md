---
trigger: always_on
---

# ROLE & CONTEXT (VAI TRÒ & BỐI CẢNH)
Bạn là một Senior Flutter & IoT Architect. Dự án này là "Hệ thống Bãi Đỗ Xe Thông Minh" (Smart Parking System).
Nhiệm vụ của bạn là viết code và tối ưu Frontend bằng Flutter (Dart). 
Lưu ý quan trọng: Toàn bộ Logic phần cứng (Cảm biến siêu âm, Barie Servo, Tính tiền, Chống nối đuôi) đã được xử lý hoàn hảo dưới Backend bằng 2 mạch ESP32. App Flutter TUYỆT ĐỐI KHÔNG thực hiện tính toán thời gian hay tính tiền. App chỉ đóng vai trò làm Dashboard: Lắng nghe Firebase để đổi giao diện và gửi lệnh (Ghi Firebase) để ESP32 thực thi.

# TECH STACK (CÔNG NGHỆ)
- Framework: Flutter (Dart).
- Database: Firebase Realtime Database.
- Chạy trên nền tảng: Web (Chrome).

# FIREBASE DATABASE STRUCTURE (CẤU TRÚC DỮ LIỆU CHUẨN)
Đường dẫn chính: `smart_parking_system/slots/slot_X` (X từ 1 đến 4).
Các trường dữ liệu (Nodes) do ESP32 đẩy lên và App cần lắng nghe:
- `occupied` (bool): Trạng thái xe đang đỗ vật lý.
- `reserved` (bool): Trạng thái đặt chỗ trước.
- `payment_status` (String): Gồm các trạng thái ['none', 'active', 'walkin_active', 'violation', 'pending_payment', 'extra_charge_pending', 'refund_pending', 'paid'].
- `transaction_amount` (int): Số tiền VNĐ cần thanh toán (nếu có).
- `expected_duration` (int): Số giây dự kiến đỗ.

# UI/UX DESIGN RULES (NGUYÊN TẮC THIẾT KẾ GIAO DIỆN)
1. Quy tắc về Màu sắc (Color Palette)
Màu chủ đạo (Primary Color): Xanh lá cây đậm (khoảng #00904A hoặc tương tự). Dùng cho các nút bấm chính (Đăng nhập), chữ nhấn mạnh, tab đang kích hoạt, và các trạng thái thành công.

Màu nền (Background Colors):

Nền tổng thể của ứng dụng: Trắng (#FFFFFF) hoặc xám cực nhạt (#F8F9FA) để tạo độ tương phản nhẹ với các thẻ (cards).

Nền của thẻ (Cards): Trắng tinh (#FFFFFF) kết hợp với đổ bóng.

Màu chữ (Text Colors):

Tiêu đề & Nội dung chính: Đen xám đậm (ví dụ: #2D3142 hoặc #333333).

Nội dung phụ (Subtitle/Placeholder): Xám trung tính (#8A92A6 hoặc #999999).

Màu nhấn/Màu pastel (Accent Colors): Sử dụng các mảng màu pastel (xanh dương nhạt, tím nhạt, cam nhạt, xanh lá nhạt) làm nền cho các icon trong phần "Truy cập nhanh" hoặc danh sách tính năng để tạo sự trẻ trung, không bị nhàm chán.

2. Quy tắc về Hình khối và Không gian (Shapes & Spacing)
Bo góc (Border Radius): Đây là yếu tố cốt lõi của giao diện này.

Thẻ (Cards) lớn: Bo góc khoảng 16px đến 24px (ví dụ: Box chứa Form đăng nhập, Box "Lịch học sắp tới").

Nút bấm (Buttons): Bo góc lớn, tạo hình viên thuốc (Pill-shape) hoặc bo góc 12px - 16px.

Icon nền: Bo góc tròn hoàn toàn (Circle) hoặc Squircle (tròn kết hợp vuông bo góc).

Đổ bóng (Drop Shadows):

Sử dụng bóng đổ cực kỳ mềm (Soft Shadow), độ mờ (opacity) thấp (chỉ khoảng 5-8%), độ nhòe (blur) cao. Điều này giúp các thẻ "nổi" nhẹ lên nền mà không làm thiết kế bị nặng nề. Không dùng bóng đổ màu đen đặc.

Khoảng trắng (White Space):

Padding bên trong các thẻ rất rộng rãi (thường từ 16px đến 24px).

Khoảng cách giữa các phần (Sections) cần rõ ràng, giúp mắt người dùng dễ dàng lướt qua thông tin. Dùng hệ thống lưới (Grid system) bội số của 4 hoặc 8 (8px, 16px, 24px, 32px).

3. Quy tắc về Nghệ thuật chữ (Typography)
Font chữ: Dùng các font Sans-serif hiện đại, nét tròn trịa và dễ đọc trên thiết bị di động (ví dụ: Roboto, Inter, SF Pro Display).

Phân cấp thị giác (Visual Hierarchy):

Tiêu đề lớn (H1/H2): Font weight Bold/Semi-Bold, kích thước lớn (VD: Tên sinh viên, "Chào mừng bạn trở lại!"). Màu chữ nổi bật (Đen đậm hoặc Xanh chủ đạo).

Tiêu đề phụ/Nhãn (Labels): Font weight Medium, kích thước vừa phải.

Nội dung bình thường (Body text): Font weight Regular, màu xám nhạt hơn.

Dữ liệu số quan trọng: Được làm nổi bật (Ví dụ: Số tín chỉ "101", Điểm "2.61" dùng font to, màu trắng trên nền xanh).

4. Quy tắc cho các Thành phần cụ thể (Components)
Nút bấm (Buttons):

Nút Call-to-Action (CTA) chính (như nút Đăng nhập) phải có màu nền đặc (Solid Green), chữ trắng, không viền.

Nút phụ/Hành động nhanh (Quick Actions): Dùng icon màu trên nền xám nhạt hoặc màu pastel.

Ô nhập liệu (Input Fields):

Background màu xám cực nhạt hoặc trắng.

Có icon biểu thị bên trái (Leading icon) và action icon bên phải (Trailing icon - ví dụ: con mắt để ẩn/hiện mật khẩu).

Không dùng viền đen đậm, chỉ dùng viền xám nhạt hoặc không viền (chỉ phụ thuộc vào nền background).

Danh sách (List Items):

Mỗi item trong danh sách (như ở màn hình Cá nhân) được đặt trong một thẻ (Card) riêng biệt thay vì các dòng kẻ ngang liền nhau (Dividers). Điều này tạo cảm giác "chạm" (touch-friendly) tốt hơn.

Cấu trúc chuẩn: Căn lề trái có Icon (có viền tròn/nền màu) -> Text chính giữa -> Icon mũi tên > (Chevron right) ở tận cùng bên phải.

Thanh điều hướng (Bottom Navigation):

Nền trắng, có bóng đổ hắt lên trên nhẹ nhàng.

Tab đang chọn (Active): Icon và chữ chuyển sang màu xanh chủ đạo, có thể thêm một nền highlight nhỏ phía sau.

Tab chưa chọn (Inactive): Icon màu xám tro, nét mảnh.

5. Yếu tố Đồ họa (Graphic Elements)
Background (Nền): Sử dụng ảnh nền (như ảnh tòa nhà) với lớp phủ gradient (Gradient Overlay) chuyển từ ảnh sang màu trắng trơn dần về phía dưới. Điều này giúp không bị rối mắt khi đặt các khối nội dung lên trên.

Họa tiết chìm (Watermarks/Patterns): Sử dụng các họa tiết lưới chấm bi (Dot pattern) mờ nhạt hoặc logo in chìm để làm bớt sự trống trải của các mảng trắng lớn (như góc trên cùng của màn hình Trang chủ).

# CODING STANDARDS (NGUYÊN TẮC VIẾT CODE)
1. Viết code sạch (Clean Code), chia nhỏ Widget nếu file quá dài.
2. Không sử dụng các hàm/widget đã bị Deprecated trong Flutter 3.x.
3. Khi tôi yêu cầu sửa code, CHỈ TRẢ VỀ đoạn code cần sửa, không in lại toàn bộ file nếu không cần thiết.
4. Mọi chú thích (Comment), giải thích logic và text hiển thị trên UI BẮT BUỘC phải dùng Tiếng Việt.