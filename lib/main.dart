import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/cart_service.dart';
import 'screens/login_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/order_history_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CartService()),
      ],
      child: MaterialApp(
        title: '숯 주문 관리',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.orange,
          fontFamily: 'NotoSans',
        ),
        initialRoute: '/login',
        routes: {
          '/login': (context) => const LoginScreen(),
          '/products': (context) => const ProductListScreen(),
          '/cart': (context) => const CartScreen(),
          '/orders': (context) => const OrderHistoryScreen(),
        },
      ),
    );
  }
}
