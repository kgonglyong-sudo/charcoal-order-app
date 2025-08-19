// lib/screens/cart_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // Clipboard

import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../models/order.dart' as my_order;

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  // 은행 계좌(무통장입금용)
  static const _bankAccount = BankAccount(
    bankName: '기업은행',
    accountNumber: '461-071598-04-060',
    holder: '(주)서울에너지',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('장바구니'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Consumer<CartService>(
        builder: (context, cartService, child) {
          if (cartService.items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('장바구니가 비어있습니다',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          final auth = context.watch<AuthService>();
          final client = auth.currentClient;
          if (client == null) {
            return const Center(child: Text('로그인이 필요합니다.'));
          }

          // ❗ 여기서는 장바구니에 저장된 단가(it.price)를 그대로 사용합니다.
          final lines = cartService.items.map((it) {
            final unit = it.price;                // 저장된 단가
            final sub = unit * it.quantity;       // 소계
            return _LineViewData(
              productId: it.productId,
              productName: it.productName,
              emoji: it.emoji,
              qty: it.quantity,
              unitPrice: unit,
              subtotal: sub,
            );
          }).toList();

          final total = lines.fold<int>(0, (a, b) => a + b.subtotal);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Text(line.emoji, style: const TextStyle(fontSize: 20)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          line.productName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _QtyControl(
                                        qty: line.qty,
                                        onDecrement: () {
                                          if (line.qty > 1) {
                                            context.read<CartService>().updateQuantity(
                                              line.productId,
                                              line.qty - 1,
                                            );
                                          } else {
                                            context.read<CartService>().removeItem(line.productId);
                                          }
                                        },
                                        onIncrement: () => context.read<CartService>().updateQuantity(
                                          line.productId,
                                          line.qty + 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_comma(line.unitPrice)}원 × ${line.qty} = ${_comma(line.subtotal)}원',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => context.read<CartService>().removeItem(line.productId),
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red,
                              tooltip: '삭제',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 하단 합계/주문하기
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('총 금액',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                          '${_comma(total)}원',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _openCheckout(context, total),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('주문하기',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 결제 모달 열기 — total을 그대로 사용
  Future<void> _openCheckout(BuildContext context, int total) async {
    // 필요 시 할인율 조정(0.0 ~ 1.0). 없으면 0.0.
    const double discountRate = 0.0;

    final result = await showDialog<_CheckoutResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(
        totalAmount: total,
        discountRate: discountRate,
        bankAccount: _bankAccount,
      ),
    );

    if (result == null) return;

    await _placeOrder(context, result.method);
  }

  /// 실제 주문 저장
  Future<void> _placeOrder(BuildContext context, PaymentMethod method) async {
    final cartService = Provider.of<CartService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    if (cartService.items.isEmpty) return;

    final client = authService.currentClient;
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final branchDocId = client.branchId.trim();
    if (branchDocId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지점 정보(branchId)가 없습니다.')),
      );
      return;
    }

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        final u = cred.user!;
        await FirebaseFirestore.instance.collection('user').doc(u.uid).set({
          'role': 'client',
          'branchId': client.branchId,
          'clientCode': client.code,
          'priceTier': client.priceTier,
          'name': client.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인증 처리 중 오류: $e')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('주문 처리 중...'),
          ],
        ),
      ),
    );

    // 결제수단 문자열
    String _methodStr(PaymentMethod m) {
      switch (m) {
        case PaymentMethod.bank:
          return 'bank';
        case PaymentMethod.card:
          return 'card';
        case PaymentMethod.toss:
          return 'toss';
        case PaymentMethod.kakao:
          return 'kakao';
      }
    }

    // 상태 및 결제 정보 구성
    final isBank = method == PaymentMethod.bank;
    final orderStatus = isBank ? '입금대기' : '주문완료';
    final Map<String, dynamic> payment = isBank
        ? {
            'method': _methodStr(method),
            'status': '입금대기',
            'account': {
              'bankName': _bankAccount.bankName,
              'accountNumber': _bankAccount.accountNumber,
              'holder': _bankAccount.holder,
            },
            'createdAt': FieldValue.serverTimestamp(),
          }
        : {
            'method': _methodStr(method),
            'status': '결제완료(모의)',
            'approvedAt': FieldValue.serverTimestamp(),
          };

    try {
      final orderId = 'O${DateTime.now().millisecondsSinceEpoch}';

      final order = my_order.Order(
        id: orderId,
        clientCode: client.code,
        date: DateTime.now(),
        items: List.from(cartService.items),
        total: cartService.totalAmount, // 저장도 장바구니 가격 기준
      );

      final data = {
        'id': order.id,
        'branchId': client.branchId,
        'clientCode': order.clientCode,
        'clientName': client.name,
        'priceTier': client.priceTier,
        'items': order.items.map((e) => e.toMap()).toList(),
        'total': order.total,
        'status': orderStatus,
        'payment': payment,
        'date': order.date.toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      final db = FirebaseFirestore.instance;
      final branchRef = db.collection('branches').doc(client.branchId);
      final branchSnap = await branchRef.get();
      if (!branchSnap.exists) {
        await branchRef.set({
          'name': client.branchId,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await branchRef.collection('orders').doc(orderId).set(data, SetOptions(merge: true));

      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 닫기
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('주문 완료'),
            content: Text(isBank
                ? '주문이 접수되었습니다. 입금 확인 후 확정됩니다.'
                : '주문이 성공적으로 결제(모의)되었습니다.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Provider.of<CartService>(context, listen: false).clear();
                  Navigator.of(context).pop();
                },
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주문 처리 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
}

class _LineViewData {
  final String productId;
  final String productName;
  final String emoji;
  final int qty;
  final int unitPrice;
  final int subtotal;
  _LineViewData({
    required this.productId,
    required this.productName,
    required this.emoji,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
  });
}

enum PaymentMethod { card, toss, kakao, bank }

class BankAccount {
  final String bankName;
  final String accountNumber;
  final String holder;
  const BankAccount({
    required this.bankName,
    required this.accountNumber,
    required this.holder,
  });
}

class _CheckoutResult {
  final PaymentMethod method;
  final bool agreed;
  const _CheckoutResult({required this.method, required this.agreed});
}

class CheckoutDialog extends StatefulWidget {
  final int totalAmount;       // 참조 합계(여기선 cart 합계)
  final double discountRate;   // 0.0 ~ 1.0
  final BankAccount bankAccount;

  const CheckoutDialog({
    super.key,
    required this.totalAmount,
    this.discountRate = 0.0,
    required this.bankAccount,
  });

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  bool agreed = false;
  PaymentMethod? method;

  int get discounted =>
      (widget.totalAmount * (1 - widget.discountRate)).round();

  @override
  void initState() {
    super.initState();
    method = PaymentMethod.card; // 기본 선택
  }

  @override
  Widget build(BuildContext context) {
    final payable = widget.discountRate > 0 ? discounted : widget.totalAmount;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Row(
                children: [
                  const Text('결제하기',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  )
                ],
              ),
              const SizedBox(height: 8),

              // 합계 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text('총 결제 금액',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.discountRate > 0)
                          Row(
                            children: [
                              Text(
                                '${(widget.discountRate * 100).round()}%',
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_comma(widget.totalAmount)}원',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ),
                        Text(
                          '${_comma(payable)}원',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 결제 수단
              _MethodSelector(
                selected: method!,
                onChanged: (m) => setState(() => method = m),
              ),
              const SizedBox(height: 8),

              // 무통장입금 선택 시 계좌 노출
              if (method == PaymentMethod.bank)
                _BankAccountBox(account: widget.bankAccount),

              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: agreed,
                    onChanged: (v) => setState(() => agreed = v ?? false),
                  ),
                  const Expanded(
                    child: Text('주문 내용을 확인하였으며, 결제 진행에 동의합니다.'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 하단 결제하기 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (agreed && method != null)
                      ? () {
                          Navigator.of(context).pop(
                            _CheckoutResult(method: method!, agreed: agreed),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('${_comma(payable)}원 결제하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodSelector extends StatelessWidget {
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;
  const _MethodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(PaymentMethod m, String label, {Widget? leading}) {
      final isSel = selected == m;
      return Expanded(
        child: OutlinedButton(
          onPressed: () => onChanged(m),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: isSel ? Colors.orange : Colors.grey.shade300,
              width: 2,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: isSel ? Colors.orange.withOpacity(.06) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 6)],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isSel ? Colors.orange : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('결제 방법',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        Row(
          children: [
            btn(PaymentMethod.card, '신용·체크카드', leading: const Icon(Icons.credit_card)),
            const SizedBox(width: 8),
            btn(PaymentMethod.toss, 'toss pay', leading: const Icon(Icons.flash_on)),
            const SizedBox(width: 8),
            btn(PaymentMethod.kakao, '카카오페이', leading: const Icon(Icons.chat_bubble)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            btn(PaymentMethod.bank, '무통장입금', leading: const Icon(Icons.account_balance)),
            const Spacer(),
          ],
        ),
      ],
    );
  }
}

class _BankAccountBox extends StatelessWidget {
  final BankAccount account;
  const _BankAccountBox({required this.account});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('[무통장 입금 계좌]',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${account.bankName}  ${account.accountNumber}\n예금주: ${account.holder}',
                  style: const TextStyle(height: 1.4),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '${account.bankName} ${account.accountNumber}'),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('계좌번호가 복사되었습니다.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('복사'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '입금 확인 후 주문이 확정됩니다.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final int qty;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _QtyControl({
    required this.qty,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            color: Theme.of(context).colorScheme.primary,
            onPressed: onDecrement,
            tooltip: '빼기',
          ),
          Text('$qty', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            color: Theme.of(context).colorScheme.primary,
            onPressed: onIncrement,
            tooltip: '더하기',
          ),
        ],
      ),
    );
  }
}

String _comma(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
