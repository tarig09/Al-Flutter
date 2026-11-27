import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPri = Color(0xFF0B4F6C);
const kAcc = Color(0xFFF5A623);
final sb = Supabase.instance.client;

const statusMap = <String, List<dynamic>>{
  'pending': ['بانتظار تأكيد المكتب', Colors.orange],
  'accepted': ['تم القبول — بانتظار الدفع', Colors.blue],
  'payment_review': ['مراجعة الدفع', Colors.blue],
  'confirmed': ['مؤكد', Colors.green],
  'cancelled': ['ملغي', Colors.red],
  'received': ['تم الاستلام', Colors.blue],
  'in_transit': ['في الطريق', Colors.orange],
  'arrived': ['وصلت للوجهة', Colors.blue],
  'delivered': ['تم التسليم', Colors.green],
  'processing': ['قيد التنفيذ', Colors.orange],
  'completed': ['مكتمل', Colors.green],
  'approved': ['تمت الموافقة', Colors.green],
  'rejected': ['مرفوض', Colors.red],
};

String money(num? v) => '${NumberFormat('#,###', 'en').format(v ?? 0)} ج.س';
String dt(String? iso) => iso == null ? '' : DateFormat('yyyy/MM/dd  hh:mm a', 'en').format(DateTime.parse(iso).toLocal());

String errMsg(Object e) {
  final m = e is PostgrestException ? e.message : e.toString();
  const map = {
    'trip_unavailable': 'الرحلة غير متاحة.',
    'seat_taken': 'أحد المقاعد حُجز للتو، اختر مقعداً آخر.',
    'bad_seats': 'اختر من 1 إلى 6 مقاعد.',
    'agency_closed': 'المكتب مغلق حالياً.',
    'bad_transition': 'هذا التغيير غير مسموح في الحالة الحالية.',
    'already_rated': 'سبق تقييم هذا الطلب.',
    'not_eligible': 'لا يمكن التقييم قبل اكتمال الخدمة.',
    'no_agency': 'هذا الطلب غير مرتبط بمكتب.',
    'not_authenticated': 'سجّل الدخول أولاً.',
  };
  for (final k in map.keys) {
    if (m.contains(k)) return map[k]!;
  }
  return m;
}

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class StatusBadge extends StatelessWidget {
  final String status;
  final String? label;
  const StatusBadge(this.status, {super.key, this.label});
  @override
  Widget build(BuildContext context) {
    final s = [label ?? (statusMap[status]?[0] ?? status), statusMap[status]?[1] ?? Colors.grey];
    final col = s[1] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: col.withOpacity(.14), borderRadius: BorderRadius.circular(20)),
      child: Text(s[0] as String, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

class Empty extends StatelessWidget {
  final String text;
  const Empty(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(text, style: const TextStyle(color: Colors.black54), textAlign: TextAlign.center)));
}

class Kv extends StatelessWidget {
  final String k, v;
  const Kv(this.k, this.v, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.black54)),
          Flexible(child: Text(v, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.end)),
        ]),
      );
}

class Load<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T data) builder;
  const Load(this.future, this.builder, {super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return Empty(errMsg(s.error!));
          return builder(s.data as T);
        },
      );
}
