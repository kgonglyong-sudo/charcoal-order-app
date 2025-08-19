// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 없으면 주석 처리하고 아래 fallback만 남겨도 됨

import 'services/auth_service.dart';
import 'services/cart_service.dart';

import 'screens/login_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/order_history_screen.dart';
import 'screens/manager_home_screen.dart';  // 매니저/관리자 홈
import 'screens/clients_screen.dart';       // 거래처 화면(매니저 홈에서 사용)

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // firebase_options.dart 가 없는 환경이면 기본 초기화
    await Firebase.initializeApp();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _initFirebase();
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Firebase 초기화 실패:\n$e', textAlign: TextAlign.center),
        ),
      ),
    ));
    return;
  }
  runApp(const AppRoot());
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..init()),
        ChangeNotifierProvider(create: (_) => CartService()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '숯 주문 앱',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.orange),
        home: const _HomeRouter(),
        routes: {
          '/login'   : (_) => const LoginScreen(),
          '/products': (_) => const ProductListScreen(),
          '/cart'    : (_) => const CartScreen(),
          '/orders'  : (_) => const OrderHistoryScreen(),
          '/clients' : (_) => const ClientsScreen(),      // ✅ 거래처 라우트 등록
          // '/manager': (_) => const ManagerHomeScreen(), // 원하면 이름으로도 진입 가능
        },
      ),
    );
  }
}

/// 로그인 상태/역할에 따라 분기
class _HomeRouter extends StatelessWidget {
  const _HomeRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.hasError) {
      return Scaffold(
        body: Center(
          child: Text(auth.errorMessage ?? '로그인 오류가 발생했습니다.', textAlign: TextAlign.center),
        ),
      );
    }
    if (!auth.isSignedIn) {
      return const LoginScreen();
    }

    // 역할 기반 분기
    switch (auth.role) {
      case 'admin':
      case 'manager':
        return const ManagerHomeScreen();  // ✅ 매니저/관리자 → 매니저 홈
      case 'client':
      default:
        return const ProductListScreen();  // 거래처 → 상품 목록
    }
  }
}
