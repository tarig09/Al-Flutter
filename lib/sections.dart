import 'package:flutter/material.dart';
import 'bookings.dart';
import 'ui.dart';

/// صفحة القسم: مكاتب (السفر) أو نموذج مباشر
class SectionPage extends StatelessWidget {
  final Map<String, dynamic> office;
  const SectionPage(this.office, {super.key});
  @override
  Widget build(BuildContext context) {
    final slug = '${office['slug']}';
    final useAg = office['use_agencies'] == true;
    return Scaffold(
      appBar: AppBar(title: Text('${office['name_ar']}')),
      body: useAg ? AgencyList(slug) : DirectSection(office),
    );
  }
}

class AgencyList extends StatelessWidget {
  final String slug;
  const AgencyList(this.slug, {super.key});
  @override
  Widget build(BuildContext context) => Load<List<dynamic>>(
        sb.from('agencies').select().eq('section_slug', slug).eq('active', true),
        (d) {
          final l = d.cast<Map<String, dynamic>>()..sort((a, b) => ((b['is_open'] == true ? 1 : 0) - (a['is_open'] == true ? 1 : 0)) != 0 ? ((b['is_open'] == true ? 1 : 0) - (a['is_open'] == true ? 1 : 0)) : ((b['rating_avg'] ?? 0) as num).compareTo((a['rating_avg'] ?? 0) as num));
          if (l.isEmpty) return const Empty('لا توجد مكاتب في هذا القسم حالياً');
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final a in l)
              Card(
                child: ListTile(
                  leading: a['logo_url'] != null ? CircleAvatar(backgroundImage: NetworkImage('${a['logo_url']}')) : const CircleAvatar(child: Icon(Icons.business)),
                  title: Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Row(children: [
                    const Icon(Icons.star, size: 16, color: kAcc),
                    Text(' ${((a['rating_avg'] ?? 0) as num).toStringAsFixed(1)} (${a['rating_count'] ?? 0})'),
                  ]),
                  trailing: Text(a['is_open'] == true ? 'مفتوح' : 'مغلق', style: TextStyle(color: a['is_open'] == true ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripsPage(a))),
                ),
              ),
          ]);
        },
      );
}

class TripsPage extends StatelessWidget {
  final Map<String, dynamic> agency;
  const TripsPage(this.agency, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${agency['name']}')),
        body: Load<List<dynamic>>(
          sb.from('trips').select().eq('agency_id', agency['id']).eq('active', true).gt('depart_at', DateTime.now().toUtc().toIso8601String()).order('depart_at'),
          (d) {
            if (d.isEmpty) return const Empty('لا توجد رحلات متاحة حالياً');
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (agency['is_open'] != true) const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('المكتب مغلق حالياً ولا يستقبل حجوزات.', style: TextStyle(color: Colors.red))),
              for (final t in d.cast<Map<String, dynamic>>())
                Card(
                  child: ListTile(
                    title: Text('${t['from_city']}  ←  ${t['to_city']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${dt('${t['depart_at']}')}\n${t['bus_type'] ?? ''}'),
                    isThreeLine: true,
                    trailing: Text(money(t['price'] as num?), style: const TextStyle(color: kPri, fontWeight: FontWeight.bold)),
                    onTap: agency['is_open'] == true ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => SeatsPage(t))) : null,
                  ),
                ),
            ]);
          },
        ),
      );
}

/// يطابق خوارزمية الويب: صفوف 5 خلايا، باب، وصف أخير من 5
({List<List<Object?>> rows, List<int>? back}) busLayout(int n) {
  final back = n >= 12 ? 5 : 0, m = n - back, door = m >= 26;
  final rows = <List<Object?>>[];
  var k = 1;
  List<Object?> fix(List<Object?> r, int lim) => r.map((c) => c is int && c > lim ? null : c).toList();
  List<Object?> cell(int b, bool post) => post ? [b, b + 1, 'g', b + 3, b + 2] : [b + 2, b + 3, 'g', b + 1, b];
  final pre = door ? 6 : (m / 4).ceil();
  for (var i = 0; i < pre; i++) {
    rows.add(fix(cell(k, false), m));
    k += 4;
  }
  if (door) {
    rows.add(['d', 'd', 'g', k + 1, k]);
    k += 2;
    while (k <= m) {
      rows.add(fix(cell(k, true), m));
      k += 4;
    }
  }
  return (rows: rows, back: back > 0 ? [n - 2, n - 1, n, n - 3, n - 4] : null);
}

class SeatsPage extends StatefulWidget {
  final Map<String, dynamic> trip;
  const SeatsPage(this.trip, {super.key});
  @override
  State<SeatsPage> createState() => _SeatsPageState();
}

class _SeatsPageState extends State<SeatsPage> {
  final sel = <int>[];
  late Future<List<dynamic>> fut = sb.from('booking_seats').select('seat_no').eq('trip_id', widget.trip['id']);

  Widget seat(int n, Set<int> taken) {
    final booked = taken.contains(n), on = sel.contains(n);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: booked ? const Color(0xFFE3E7EB) : on ? kAcc : const Color(0xFFE8F5EE),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: booked ? Colors.transparent : on ? kAcc : const Color(0xFF2E7D5B), width: 2)),
            child: InkWell(
              onTap: booked ? null : () => setState(() { on ? sel.remove(n) : (sel.length < 6 ? sel.add(n) : toast(context, 'الحد الأقصى 6 مقاعد')); }),
              child: Center(child: Text('$n', style: TextStyle(fontWeight: FontWeight.bold, color: booked ? Colors.black38 : on ? Colors.white : const Color(0xFF2E7D5B)))),
            ),
          ),
        ),
      ),
    );
  }

  Widget cellW(Object? c, Set<int> taken) => c is int ? seat(c, taken) : const Expanded(child: SizedBox());

  Widget row(List<Object?> r, Set<int> taken) {
    if (r[0] == 'd') {
      return Row(children: [
        Expanded(flex: 2, child: Container(margin: const EdgeInsets.all(3), padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), child: const Center(child: Text('الباب')))),
        for (final c in r.sublist(2)) cellW(c, taken),
      ]);
    }
    return Row(children: [for (final c in r) cellW(c, taken)]);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final price = (t['price'] as num?) ?? 0;
    final L = busLayout((t['seats_total'] as num).toInt());
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار المقعد')),
      body: Load<List<dynamic>>(fut, (d) {
        final taken = d.map((e) => (e['seat_no'] as num).toInt()).toSet();
        return Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(child: ListTile(title: Text('${t['from_city']}  ←  ${t['to_city']}', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(dt('${t['depart_at']}')))),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.grey.shade400, width: 2)),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _cab(Icons.person_outline, 'المضيف')),
                    const SizedBox(width: 8),
                    Expanded(child: _cab(Icons.settings, 'السائق')),
                  ]),
                  const Divider(height: 18),
                  for (final r in L.rows) row(r, taken),
                  if (L.back != null) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [for (final c in L.back!) cellW(c, taken)])),
                ]),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Kv('المقاعد', sel.isEmpty ? '—' : (List.of(sel)..sort()).join('، ')),
              Kv('الإجمالي', money(price * sel.length)),
              const SizedBox(height: 8),
              FilledButton(onPressed: sel.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingForm(t, List.of(sel)..sort()))), child: const Text('متابعة')),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _cab(IconData i, String l) => Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 16), const SizedBox(width: 4), Text(l)]));
}

class BookingForm extends StatefulWidget {
  final Map<String, dynamic> trip;
  final List<int> seats;
  const BookingForm(this.trip, this.seats, {super.key});
  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  final n = TextEditingController(), p = TextEditingController(), w = TextEditingController(), id = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    sb.from('profiles').select().eq('id', sb.auth.currentUser!.id).maybeSingle().then((r) {
      if (r != null && mounted) { n.text = '${r['full_name'] ?? ''}'; p.text = '${r['phone'] ?? ''}'; }
    });
  }

  Future<void> go() async {
    if (n.text.trim().isEmpty || p.text.trim().isEmpty) return toast(context, 'أدخل الاسم ورقم الهاتف');
    setState(() => busy = true);
    try {
      final r = await sb.rpc('create_booking', params: {'p_trip': widget.trip['id'], 'p_seats': widget.seats, 'p_name': n.text.trim(), 'p_phone': p.text.trim(), 'p_id_no': id.text.trim().isEmpty ? null : id.text.trim(), 'p_whatsapp': w.text.trim().isEmpty ? null : w.text.trim()});
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetail((r as Map)['id'] as String)));
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget f(String l, TextEditingController c, {TextInputType? t}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, keyboardType: t, decoration: InputDecoration(labelText: l)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('بيانات المسافر')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          f('اسم المسافر', n), f('رقم الهاتف', p, t: TextInputType.phone), f('واتساب (اختياري)', w, t: TextInputType.phone), f('رقم الهوية/الجواز (اختياري)', id),
          Kv('المقاعد', widget.seats.join('، ')), Kv('الإجمالي', money(((widget.trip['price'] as num?) ?? 0) * widget.seats.length)),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : go, child: const Text('إرسال طلب الحجز')),
          const SizedBox(height: 8),
          const Text('سيصل طلبك إلى مشرفي المكتب، وأول من يستلمه يتابعه معك.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ]),
      );
}

/// قسم مباشر (بدون مكاتب): طلب خدمة عام تتابعه الإدارة
class DirectSection extends StatefulWidget {
  final Map<String, dynamic> office;
  const DirectSection(this.office, {super.key});
  @override
  State<DirectSection> createState() => _DirectSectionState();
}

class _DirectSectionState extends State<DirectSection> {
  final s = TextEditingController(), d = TextEditingController(), p = TextEditingController();
  bool busy = false;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        if ('${widget.office['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('${widget.office['description']}')),
        if (widget.office['ship_base'] != null) Card(child: ListTile(title: const Text('أجرة الإرسالية'), subtitle: Text('${money(widget.office['ship_base'] as num)} + ${money((widget.office['ship_per_kg'] ?? 0) as num)} لكل كجم'))),
        const Text('أرسل طلبك وستتواصل معك الإدارة', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(controller: s, decoration: const InputDecoration(labelText: 'الخدمة المطلوبة')),
        const SizedBox(height: 10),
        TextField(controller: d, maxLines: 3, decoration: const InputDecoration(labelText: 'التفاصيل')),
        const SizedBox(height: 10),
        TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: busy ? null : () async {
            if (s.text.trim().isEmpty || p.text.trim().isEmpty) return toast(context, 'أكمل الخدمة والهاتف');
            setState(() => busy = true);
            try {
              await sb.from('service_requests').insert({'office_slug': widget.office['slug'], 'service_name': s.text.trim(), 'details': d.text.trim(), 'phone': p.text.trim()});
              if (mounted) { toast(context, 'تم إرسال طلبك'); Navigator.pop(context); }
            } catch (e) {
              if (mounted) toast(context, errMsg(e));
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
          child: const Text('إرسال الطلب'),
        ),
      ]);
}
