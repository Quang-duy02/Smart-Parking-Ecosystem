import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/user_account.dart';

class UserService {
  UserService._privateConstructor();

  static final UserService instance = UserService._privateConstructor();

  Future<void> init() async {
    // Session is managed automatically by FirebaseAuth.instance
  }

  Future<bool> isEmailExists(String email) async {
    if (email.toLowerCase() == 'demo@gmail.com') {
      return true;
    }
    return false;
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      await credential.user?.updateDisplayName(fullName);

      // Khởi tạo số dư ban đầu cho người dùng trên Firebase
      if (credential.user != null) {
        final ref = FirebaseDatabase.instance.ref('smart_parking_system/users/${credential.user!.uid}');
        await ref.set({
          'name': fullName,
          'email': email,
          'balance': 100000, // Tặng 100k trải nghiệm
        });
      }
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Register Error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Register Error: $e');
      return false;
    }
  }

  Future<void> migrateUserIfNeeded(User user) async {
    try {
      final email = user.email;
      if (email == null) return;

      final usersRef = FirebaseDatabase.instance.ref('smart_parking_system/users');
      final snapshot = await usersRef.get();
      if (!snapshot.exists || snapshot.value == null) return;

      final Map<dynamic, dynamic> usersMap;
      if (snapshot.value is Map) {
        usersMap = snapshot.value as Map;
      } else {
        return;
      }

      // Tìm kiếm node có email trùng khớp nhưng khóa khác với UID hiện tại
      String? oldKey;
      Map<dynamic, dynamic>? oldUserData;

      usersMap.forEach((key, value) {
        if (key.toString() != user.uid && value is Map) {
          final nodeEmail = value['email'] as String?;
          if (nodeEmail != null && nodeEmail.toLowerCase() == email.toLowerCase()) {
            oldKey = key.toString();
            oldUserData = value;
          }
        }
      });

      if (oldKey != null && oldUserData != null) {
        debugPrint('Phát hiện tài khoản tạm thời cần di trú: $oldKey -> ${user.uid}');
        final newRef = FirebaseDatabase.instance.ref('smart_parking_system/users/${user.uid}');
        
        // Sao chép dữ liệu sang vị trí mới
        await newRef.set({
          'name': oldUserData!['name'] ?? user.displayName ?? 'Khách Hàng VIP',
          'email': email,
          'balance': int.tryParse(oldUserData!['balance'].toString()) ?? 100000,
        });

        // Xóa node cũ
        final oldRef = FirebaseDatabase.instance.ref('smart_parking_system/users/$oldKey');
        await oldRef.remove();
        
        debugPrint('Di trú dữ liệu tài khoản thành công!');
      }
    } catch (e) {
      debugPrint('Lỗi khi di trú tài khoản: $e');
    }
  }

  Future<UserAccount?> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        return UserAccount(
          id: user.uid,
          fullName: user.displayName ?? 'Người dùng Firebase',
          email: user.email ?? email,
          password: password,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Login Error: $e');
      // Fallback for local demo account testing
      if (email.toLowerCase() == 'demo@gmail.com' && password == '123456') {
        return const UserAccount(
          id: '1',
          fullName: 'Demo User',
          email: 'demo@gmail.com',
          password: '123456',
        );
      }
      return null;
    }
  }
}