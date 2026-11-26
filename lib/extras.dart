import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ui.dart';

/// محوّل العملات: جنيه مصري ⇄ جنيه سوداني بسعر يحدده المدير
class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});
  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  bool egpToSdg = true;
  final amount = TextEditingController();
  late final Future<Map<String, dynamic>?> fut = sb.from('currency_rates').select().eq('pair', 'EGP_SDG').maybeSingle();

  String fmt(num v) => NumberFormat('#,##0.##', 'en').format(v);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('محوّل العملات')),
        body: Load<Map<String, dynamic>?>(fut, (r) {
          if (r == null) return const Empty('لم يحدد سعر الصرف بعد. حاول لاحقاً.');
          final rate = (r['rate'] as num).toDouble();
          final x = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
          final out = egpToSdg ? x * rate : x / rate;
          return ListView(padding: const EdgeInsets.all(16), children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('مصري ← سوداني')), ButtonSegment(value: false, label: Text('سوداني ← مصري'))],
              selected: {egpToSdg},
              onSelectionChanged: (s) => setState(() => egpToSdg = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'المبلغ (${egpToSdg ? 'جنيه مصري' : 'جنيه سوداني'})'),
            ),
            const SizedBox(height: 14),
            Card(
              color: kPri,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Text('المبلغ بعد التحويل', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(x > 0 ? fmt(out) : '—', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  Text(egpToSdg ? 'جنيه سوداني' : 'جنيه مصري', style: const TextStyle(color: kAcc, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            Kv('سعر الفك', '1 جنيه مصري = ${fmt(rate)} جنيه سوداني'),
            if (r['updated_at'] != null) Kv('آخر تحديث', dt('${r['updated_at']}')),
          ]);
        }),
      );
}

IconData _icon(String p) => switch (p) {
      'facebook' => Icons.facebook,
      'tiktok' => Icons.music_note,
      'telegram' => Icons.telegram,
      'whatsapp' => Icons.chat,
      'instagram' => Icons.camera_alt,
      'youtube' => Icons.play_circle_fill,
      'x' => Icons.alternate_email,
      'snapchat' => Icons.photo_camera,
      _ => Icons.public,
    };

Color _color(String p) => switch (p) {
      'facebook' => const Color(0xFF1877F2),
      'tiktok' => Colors.black,
      'telegram' => const Color(0xFF229ED9),
      'whatsapp' => const Color(0xFF25D366),
      'instagram' => const Color(0xFFE1306C),
      'youtube' => const Color(0xFFFF0000),
      'snapchat' => const Color(0xFFF7C600),
      'x' => Colors.black,
      _ => kPri,
    };

/// شريط أيقونات التواصل (تُضاف من لوحة الإدارة)
class SocialBar extends StatelessWidget {
  const SocialBar({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: sb.from('social_links').select().eq('active', true).order('sort'),
        builder: (c, s) {
          final l = ((s.data ?? []) as List).cast<Map<String, dynamic>>();
          if (l.isEmpty) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              const Text('تابعنا على', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Wrap(spacing: 14, runSpacing: 10, alignment: WrapAlignment.center, children: [
                for (final x in l)
                  Tooltip(
                    message: '${x['label'] ?? x['platform']}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () async {
                        final u = Uri.tryParse('${x['url']}');
                        if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
                      },
                      child: CircleAvatar(radius: 22, backgroundColor: _color('${x['platform']}'), child: Icon(_icon('${x['platform']}'), color: Colors.white, size: 22)),
                    ),
                  ),
              ]),
            ]),
          );
        },
      );
}
