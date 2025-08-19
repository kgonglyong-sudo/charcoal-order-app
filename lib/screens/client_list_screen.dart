import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'client_edit_screen.dart';

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});
  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  String _query = '';
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final branchId = context.watch<AuthService>().branchId;
    if (branchId == null || branchId.isEmpty) {
      return const Scaffold(body: Center(child: Text('지점 정보가 없습니다.')));
    }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('branches').doc(branchId)
        .collection('clients')
        .orderBy('nameLower');

    final qi = _query.trim().toLowerCase();
    if (qi.isNotEmpty) {
      final end = '$qi\uf8ff';
      q = q.where('nameLower', isGreaterThanOrEqualTo: qi)
           .where('nameLower', isLessThan: end);
    }
    if (!_showInactive) {
      q = q.where('isActive', isEqualTo: true);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('거래처'),
        actions: [
          IconButton(
            tooltip: _showInactive ? '활성만 보기' : '비활성 포함',
            icon: Icon(_showInactive ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '이름/코드 검색',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) return const Center(child: Text('등록된 거래처가 없습니다.'));
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();
                    final code = d.id;
                    final name = (m['name'] as String?) ?? '';
                    final phone = (m['phone'] as String?) ?? '';
                    final tier = (m['priceTier'] as String?) ?? '-';
                    final active = (m['isActive'] as bool?) ?? true;

                    return ListTile(
                      leading: CircleAvatar(child: Text(tier)),
                      title: Text('$name ($code)'),
                      subtitle: Text(phone),
                      trailing: active
                          ? const Text('활성', style: TextStyle(color: Colors.green))
                          : const Text('비활성', style: TextStyle(color: Colors.grey)),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClientEditScreen(code: code, initData: m),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClientEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('거래처 추가'),
      ),
    );
  }
}
