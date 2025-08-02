import 'package:flutter/foundation.dart';
import '../models/client.dart';

class AuthService with ChangeNotifier {
  Client? _currentClient;
  bool _isLoggedIn = false;

  Client? get currentClient => _currentClient;
  bool get isLoggedIn => _isLoggedIn;

  // 임시 데이터 (나중에 Firebase로 대체)
  final Map<String, Client> _sampleClients = {
    'CLIENT001': Client(
      code: 'CLIENT001',
      name: '대한숯상회',
      branchId: 'CC001',
      priceTier: 'A',
    ),
    'CLIENT002': Client(
      code: 'CLIENT002',
      name: '중부숯유통',
      branchId: 'CC001',
      priceTier: 'B',
    ),
    'CLIENT003': Client(
      code: 'CLIENT003',
      name: '충남숯도매',
      branchId: 'CC001',
      priceTier: 'C',
    ),
  };

  Future<bool> login(String clientCode) async {
    // 로딩 시뮬레이션
    await Future.delayed(const Duration(seconds: 1));
    
    final client = _sampleClients[clientCode.toUpperCase()];
    if (client != null) {
      _currentClient = client;
      _isLoggedIn = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    _currentClient = null;
    _isLoggedIn = false;
    notifyListeners();
  }
}