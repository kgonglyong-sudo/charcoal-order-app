import 'package:cloud_firestore/cloud_firestore.dart';

class CatalogRepository {
  final FirebaseFirestore db;
  CatalogRepository(this.db);

  CollectionReference<Map<String, dynamic>> get _products => db.collection('products');

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchActiveProducts({String? category}) async {
    var q = _products.where('active', isEqualTo: true);
    if (category != null && category.isNotEmpty) q = q.where('category', isEqualTo: category);
    final snap = await q.get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchVariants(String pid) async {
    final snap = await _products.doc(pid).collection('variants').orderBy('sortOrder').get();
    return snap.docs;
  }

  Future<void> updateGradePrices(String pid, String vid, {required int a, required int b, required int c}) async {
    await _products.doc(pid).collection('variants').doc(vid).update({
      'gradePrices': {'A': a, 'B': b, 'C': c},
    });
  }
}
