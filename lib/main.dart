import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/user_service.dart';
import 'utils/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBLYqmYKLz0Y0Dm1gfrqxBN2jsNCXsS79U",
      authDomain: "n2-smpkcar-project.firebaseapp.com",
      databaseURL: "https://n2-smpkcar-project-default-rtdb.asia-southeast1.firebasedatabase.app",
      projectId: "n2-smpkcar-project",
      storageBucket: "n2-smpkcar-project.firebasestorage.app",
      messagingSenderId: "693513847519",
      appId: "1:693513847519:web:73468d60fe6971c51b9f6a",
      measurementId: "G-NGP9QSDGPK",
    ),
  );

  await UserService.instance.init();
  runApp(const SmartParkingApp());
}

class SmartParkingApp extends StatelessWidget {
  const SmartParkingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Parking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(
            color: AppColors.textDark,
          ),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            return MainScreen(userEmail: snapshot.data!.email ?? '');
          }
          return const LoginScreen();
        },
      ),
    );
  }
}