import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'admin_service.dart';
import 'admin_ui.dart';

// =============================================================== المهن والخدمات
class CatalogAdminScreen extends StatelessWidget {
  const CatalogAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('المهن والخدمات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('مهنة جديدة'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: a.col('categories').snapshots(),
        builder: (context, cs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: a.col('services').snapshots(),
          builder: (context, ss) {
            if (!cs.hasData || !ss.hasData) return const LoadingView();
            final cats = cs.data!.docs.toList()..sort((x, y) => ((x.data()['order'] as num?) ?? 0).compareTo((y.data()['order'] as num?) ?? 0));
            final svcs = ss.data!.docs;
            return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
              const InfoBox('أي تعديل هنا بيظهر في التطبيق على طول. التعطيل أحسن من الحذف عشان الطلبات القديمة.'),
              const SizedBox(height: 10),
              for (final c in cats)
                Builder(builder: (context) {
                  final m = c.data();
                  final active = m['active'] != false;
                  final mine = svcs.where((s) => s.data()['categoryId'] == c.id).toList()
                    ..sort((x, y) => ((x.data()['order'] as num?) ?? 0).compareTo((y.data()['order'] as num?) ?? 0));
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Text('${m['nameAr'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w800, color: active ? AppColors.text : AppColors.muted)),
                      subtitle: Text('${m['nameEn'] ?? ''} • ${mine.length} خدمة'),
                      leading: Pill(active ? 'مفعّلة' : 'معطّلة', color: active ? AppColors.success : AppColors.emergency),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [
                            TextButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryEditScreen(id: c.id, data: m))),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('تعديل'),
                            ),
                            TextButton.icon(
                              onPressed: () => runAdmin(context, () => a.toggleActive('categories/${c.id}', !active)),
                              icon: Icon(active ? Icons.block : Icons.check_circle_outline),
                              label: Text(active ? 'تعطيل' : 'تفعيل'),
                            ),
                          ]),
                        ),
                        for (final s in mine)
                          ListTile(
                            dense: true,
                            title: Text('${s.data()['nameAr'] ?? ''}', style: TextStyle(color: s.data()['active'] == false ? AppColors.muted : null)),
                            subtitle: Text('${s.data()['nameEn'] ?? ''}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () async {
                                  final ar = await askText(context, 'اسم الخدمة بالعربي', initial: '${s.data()['nameAr'] ?? ''}');
                                  if (ar == null || !context.mounted) return;
                                  final en = await askText(context, 'الاسم بالإنجليزي', initial: '${s.data()['nameEn'] ?? ''}');
                                  if (en == null || !context.mounted) return;
                                  await runAdmin(context, () => a.editService(s.id, ar, en));
                                },
                              ),
                              Switch(
                                value: s.data()['active'] != false,
                                onChanged: (v) => runAdmin(context, () => a.toggleActive('services/${s.id}', v), ok: ''),
                              ),
                            ]),
                          ),
                        ListTile(
                          leading: const Icon(Icons.add_circle_outline, color: AppColors.navy),
                          title: const Text('إضافة خدمة', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700)),
                          onTap: () async {
                            final ar = await askText(context, 'اسم الخدمة بالعربي');
                            if (ar == null || !context.mounted) return;
                            final en = await askText(context, 'الاسم بالإنجليزي');
                            if (en == null || !context.mounted) return;
                            await runAdmin(context, () => a.addService(c.id, ar, en, mine.length));
                          },
                        ),
                      ],
                    ),
                  );
                }),
            ]);
          },
        ),
      ),
    ));
  }
}

class CategoryEditScreen extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;
  const CategoryEditScreen({super.key, this.id, this.data});
  @override
  State<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends State<CategoryEditScreen> {
  late final _id = TextEditingController(text: widget.id ?? '');
  late final _ar = TextEditingController(text: '${widget.data?['nameAr'] ?? ''}');
  late final _en = TextEditingController(text: '${widget.data?['nameEn'] ?? ''}');
  late final _order = TextEditingController(text: '${widget.data?['order'] ?? 0}');
  late String _icon = '${widget.data?['icon'] ?? 'handyman'}';
  late bool _active = widget.data?['active'] != false;
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    _ar.dispose();
    _en.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rtl(Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'مهنة جديدة' : 'تعديل مهنة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _id,
          enabled: widget.id == null,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'المعرّف (إنجليزي من غير مسافات)', hintText: 'plumber'),
        ),
        const SizedBox(height: 10),
        TextField(controller: _ar, decoration: const InputDecoration(labelText: 'الاسم بالعربي')),
        const SizedBox(height: 10),
        TextField(controller: _en, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الاسم بالإنجليزي')),
        const SizedBox(height: 10),
        TextField(controller: _order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الترتيب')),
        const SizedBox(height: 14),
        const Text('الأيقونة', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in kCategoryIcons.entries)
            InkWell(
              onTap: () => setState(() => _icon = e.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _icon == e.key ? AppColors.amber.withValues(alpha: 0.2) : Colors.white,
                  border: Border.all(color: _icon == e.key ? AppColors.amber : AppColors.border, width: _icon == e.key ? 2 : 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(e.value, color: AppColors.navy),
              ),
            ),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('مفعّلة')),
        const SizedBox(height: 10),
        BusyButton(
          label: 'حفظ',
          busy: _busy,
          onPressed: () async {
            final id = _id.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
            if (id.isEmpty || _ar.text.trim().isEmpty || _en.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كمّل البيانات')));
              return;
            }
            setState(() => _busy = true);
            final ok = await runAdmin(
              context,
              () => AdminService.instance.saveCategory(id, {
                'nameAr': _ar.text.trim(),
                'nameEn': _en.text.trim(),
                'icon': _icon,
                'active': _active,
                'order': int.tryParse(_order.text) ?? 0,
              }),
            );
            if (mounted) setState(() => _busy = false);
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
      ]),
    ));
  }
}

// =============================================================== المناطق
class LocationsAdminScreen extends StatelessWidget {
  const LocationsAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('المناطق')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: a.col('locations').snapshots(),
        builder: (context, s) {
          if (!s.hasData) return const LoadingView();
          final all = s.data!.docs;
          final govs = all.where((d) => d.data()['type'] == 'governorate').toList()
            ..sort((x, y) => '${x.data()['nameAr']}'.compareTo('${y.data()['nameAr']}'));
          List<QueryDocumentSnapshot<Map<String, dynamic>>> kids(String id) => all.where((d) => d.data()['parentId'] == id).toList()
            ..sort((x, y) => '${x.data()['nameAr']}'.compareTo('${y.data()['nameAr']}'));

          Widget toggle(QueryDocumentSnapshot<Map<String, dynamic>> d) => Switch(
                value: d.data()['active'] != false,
                onChanged: (v) => runAdmin(context, () => a.toggleActive('locations/${d.id}', v), ok: ''),
              );
          Widget addBtn(String parentId, String type, String label) => ListTile(
                dense: true,
                leading: const Icon(Icons.add_circle_outline, color: AppColors.navy),
                title: Text(label, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700)),
                onTap: () => _addPlace(context, parentId, type),
              );

          return ListView(padding: const EdgeInsets.all(14), children: [
            const InfoBox('ضيف المراكز والمدن والمناطق تحت كل محافظة. الإحداثيات اختيارية وبتتاخد من خرايط جوجل (ضغطة طويلة على المكان).'),
            const SizedBox(height: 10),
            for (final g in govs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text('${g.data()['nameAr']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${kids(g.id).length} مركز/مدينة'),
                  children: [
                    for (final c in kids(g.id))
                      ExpansionTile(
                        shape: const Border(),
                        tilePadding: const EdgeInsetsDirectional.only(start: 28, end: 12),
                        title: Text('${c.data()['nameAr']}'),
                        trailing: toggle(c),
                        children: [
                          for (final ar in kids(c.id))
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsetsDirectional.only(start: 48, end: 12),
                              title: Text('${ar.data()['nameAr']}'),
                              trailing: toggle(ar),
                            ),
                          addBtn(c.id, 'area', 'إضافة منطقة / قرية'),
                        ],
                      ),
                    addBtn(g.id, 'city', 'إضافة مركز / مدينة'),
                  ],
                ),
              ),
          ]);
        },
      ),
    ));
  }

  Future<void> _addPlace(BuildContext context, String parentId, String type) async {
    final ar = TextEditingController();
    final en = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => rtl(AlertDialog(
        title: Text(type == 'city' ? 'مركز / مدينة جديدة' : 'منطقة / قرية جديدة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ar, decoration: const InputDecoration(labelText: 'الاسم بالعربي')),
            TextField(controller: en, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'English (اختياري)')),
            TextField(controller: lat, textDirection: TextDirection.ltr, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط العرض lat (اختياري)')),
            TextField(controller: lng, textDirection: TextDirection.ltr, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط الطول lng (اختياري)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, ar.text.trim().isNotEmpty), child: const Text('إضافة')),
        ],
      )),
    );
    if (ok != true || !context.mounted) return;
    await runAdmin(
      context,
      () => AdminService.instance.addLocation(
        type: type,
        parentId: parentId,
        ar: ar.text.trim(),
        en: en.text.trim(),
        lat: double.tryParse(lat.text.trim()),
        lng: double.tryParse(lng.text.trim()),
      ),
    );
  }
}

// =============================================================== الإشعارات الجماعية
class BroadcastAdminScreen extends StatefulWidget {
  const BroadcastAdminScreen({super.key});
  @override
  State<BroadcastAdminScreen> createState() => _BroadcastAdminScreenState();
}

class _BroadcastAdminScreenState extends State<BroadcastAdminScreen> {
  final a = AdminService.instance;
  String _target = 'all';
  String _value = '';
  final _user = TextEditingController();
  final _ta = TextEditingController();
  final _ba = TextEditingController();
  final _te = TextEditingController();
  final _be = TextEditingController();
  bool _busy = false;
  static const targets = {
    'all': 'كل المستخدمين',
    'customers': 'كل العملاء',
    'workers': 'كل الصنايعية',
    'category': 'صنايعية مهنة معينة',
    'governorate': 'محافظة معينة',
    'user': 'مستخدم محدد',
  };

  @override
  void dispose() {
    for (final c in [_user, _ta, _ba, _te, _be]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('إرسال إشعار')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          value: _target,
          decoration: const InputDecoration(labelText: 'هيوصل لمين؟'),
          items: [for (final e in targets.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() {
            _target = v ?? 'all';
            _value = '';
          }),
        ),
        const SizedBox(height: 10),
        if (_target == 'category')
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: a.col('categories').snapshots(),
            builder: (context, s) => DropdownButtonFormField<String>(
              value: _value.isEmpty ? null : _value,
              decoration: const InputDecoration(labelText: 'المهنة'),
              items: [for (final d in s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) DropdownMenuItem(value: d.id, child: Text('${d.data()['nameAr']}'))],
              onChanged: (v) => setState(() => _value = v ?? ''),
            ),
          ),
        if (_target == 'governorate')
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: a.col('locations').where('type', isEqualTo: 'governorate').snapshots(),
            builder: (context, s) => DropdownButtonFormField<String>(
              value: _value.isEmpty ? null : _value,
              decoration: const InputDecoration(labelText: 'المحافظة'),
              items: [
                for (final d in s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  DropdownMenuItem(value: '${d.data()['code'] ?? d.id}', child: Text('${d.data()['nameAr']}')),
              ],
              onChanged: (v) => setState(() => _value = v ?? ''),
            ),
          ),
        if (_target == 'user')
          TextField(
            controller: _user,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم الموبايل أو معرّف المستخدم'),
          ),
        const SizedBox(height: 10),
        TextField(controller: _ta, maxLength: 80, decoration: const InputDecoration(labelText: 'العنوان (عربي)')),
        TextField(controller: _ba, maxLength: 400, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'النص (عربي)')),
        TextField(controller: _te, maxLength: 80, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Title (English) — اختياري')),
        TextField(controller: _be, maxLength: 400, minLines: 2, maxLines: 5, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Body (English) — اختياري')),
        const InfoBox('الإشعار بيظهر للمستخدمين جوه التطبيق (صندوق الإشعارات وبانر وهو فاتح التطبيق).'),
        const SizedBox(height: 14),
        BusyButton(
          label: 'إرسال',
          icon: Icons.send,
          busy: _busy,
          onPressed: () async {
            final v = _target == 'user' ? _user.text.trim() : _value;
            if (['category', 'governorate', 'user'].contains(_target) && v.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختار مين هيوصله الإشعار')));
              return;
            }
            if (!await askConfirm(context, 'تأكيد إرسال الإشعار؟') || !mounted) return;
            setState(() => _busy = true);
            final ok = await runAdmin(
              context,
              () => a.broadcast(target: _target, value: v, titleAr: _ta.text.trim(), bodyAr: _ba.text.trim(), titleEn: _te.text.trim(), bodyEn: _be.text.trim()),
              ok: 'تم الإرسال ✅',
            );
            if (mounted) setState(() => _busy = false);
            if (ok) {
              for (final c in [_ta, _ba, _te, _be]) {
                c.clear();
              }
            }
          },
        ),
        const SizedBox(height: 24),
        const Text('آخر الإشعارات المبعوتة', style: TextStyle(fontWeight: FontWeight.w800)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: a.col('broadcasts').orderBy('createdAt', descending: true).limit(20).snapshots(),
          builder: (context, s) => Column(children: [
            for (final d in s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.campaign_outlined, color: AppColors.amber),
                title: Text('${d.data()['titleAr'] ?? ''}'),
                subtitle: Text('${targets[d.data()['target']] ?? d.data()['target']} ${d.data()['value'] ?? ''} • ${fmtTs(d.data()['createdAt'])}'),
              ),
          ]),
        ),
      ]),
    ));
  }
}

// =============================================================== الإعدادات
class SettingsAdminScreen extends StatefulWidget {
  const SettingsAdminScreen({super.key});
  @override
  State<SettingsAdminScreen> createState() => _SettingsAdminScreenState();
}

class _SettingsAdminScreenState extends State<SettingsAdminScreen> {
  final a = AdminService.instance;
  final c = <String, TextEditingController>{};
  bool _loaded = false;
  String? _busy;

  TextEditingController f(String k) => c.putIfAbsent(k, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    a.ref('settings/public').get().then((d) {
      final s = d.data() ?? {};
      final br = Map<String, dynamic>.from(s['badgeRules'] ?? {});
      f('rate').text = (((s['commissionRate'] as num?) ?? 0.05) * 100).toStringAsFixed(1);
      f('overdue').text = '${s['overdueDays'] ?? 7}';
      f('ipa').text = '${s['instapayHandle'] ?? ''}';
      f('ipp').text = '${s['instapayPhone'] ?? ''}';
      f('em').text = '${s['emergencyRadiusKm'] ?? 15}';
      f('op').text = '${s['openRequestRadiusKm'] ?? 25}';
      f('max').text = '${s['maxNotifiedWorkers'] ?? 30}';
      f('trA').text = '${br['topRatedMinAvg'] ?? 4.7}';
      f('trC').text = '${br['topRatedMinCount'] ?? 10}';
      f('mc').text = '${br['mostCompletedMin'] ?? 50}';
      f('ph').text = '${s['supportPhone'] ?? ''}';
      f('wa').text = '${s['supportWhatsapp'] ?? ''}';
      f('mail').text = '${s['supportEmail'] ?? ''}';
      f('play').text = '${s['playStoreUrl'] ?? ''}';
      if (mounted) setState(() => _loaded = true);
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  num _n(String k, num def) => num.tryParse(f(k).text.trim()) ?? def;

  Future<void> _save(String key, Map<String, dynamic> patch) async {
    setState(() => _busy = key);
    await runAdmin(context, () => a.updateSettings(patch), ok: 'اتحفظ ✅');
    if (mounted) setState(() => _busy = null);
  }

  Widget _field(String k, String label, {bool ltr = false, bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: f(k),
          textDirection: ltr ? TextDirection.ltr : null,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _section(String title, IconData icon, List<Widget> fields, String key, Map<String, dynamic> Function() patch, {String? note}) => AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Icon(icon, color: AppColors.navy), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
          const SizedBox(height: 12),
          ...fields,
          if (note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
          BusyButton(label: 'حفظ', busy: _busy == key, onPressed: () => _save(key, patch())),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: !_loaded
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.all(14), children: [
              _section(
                'العمولة والدفع (InstaPay)',
                Icons.payments_outlined,
                [
                  _field('rate', 'نسبة العمولة %', number: true),
                  _field('overdue', 'العمولة تعتبر متأخرة بعد (يوم)', number: true),
                  _field('ipa', 'عنوان InstaPay (مثل name@instapay)', ltr: true),
                  _field('ipp', 'رقم الموبايل المرتبط بـ InstaPay', ltr: true),
                ],
                'pay',
                () => {
                  'commissionRate': _n('rate', 5) / 100,
                  'overdueDays': _n('overdue', 7).toInt(),
                  'instapayHandle': f('ipa').text.trim(),
                  'instapayPhone': f('ipp').text.trim(),
                },
                note: 'تغيير النسبة بيسري على الطلبات اللي سعرها يتأكد بعد الحفظ بس.',
              ),
              _section(
                'بيانات الدعم ورابط التطبيق',
                Icons.support_agent,
                [
                  _field('ph', 'رقم الدعم', ltr: true),
                  _field('wa', 'واتساب الدعم', ltr: true),
                  _field('mail', 'بريد الدعم', ltr: true),
                  _field('play', 'رابط Google Play', ltr: true),
                ],
                'pub',
                () => {
                  'supportPhone': f('ph').text.trim(),
                  'supportWhatsapp': f('wa').text.trim(),
                  'supportEmail': f('mail').text.trim(),
                  'playStoreUrl': f('play').text.trim(),
                },
              ),
              if (a.isSuper) ...[
                _section(
                  'الطوارئ والطلبات المفتوحة',
                  Icons.emergency_outlined,
                  [
                    _field('em', 'نطاق إشعار الطوارئ (كم)', number: true),
                    _field('op', 'نطاق الطلبات المفتوحة (كم)', number: true),
                    _field('max', 'أقصى عدد صنايعية يوصلهم الطلب', number: true),
                  ],
                  'rad',
                  () => {
                    'emergencyRadiusKm': _n('em', 15),
                    'openRequestRadiusKm': _n('op', 25),
                    'maxNotifiedWorkers': _n('max', 30).toInt(),
                  },
                ),
                _section(
                  'قواعد الشارات التلقائية',
                  Icons.workspace_premium_outlined,
                  [
                    _field('trA', '⭐ الأعلى تقييمًا: أقل متوسط', number: true),
                    _field('trC', '⭐ أقل عدد تقييمات', number: true),
                    _field('mc', '🏆 الأكثر إنجازًا: عدد الخدمات المكتملة', number: true),
                  ],
                  'badge',
                  () => {
                    'badgeRules': {
                      'topRatedMinAvg': _n('trA', 4.7),
                      'topRatedMinCount': _n('trC', 10).toInt(),
                      'mostCompletedMin': _n('mc', 50).toInt(),
                    },
                  },
                ),
              ],
            ]),
    ));
  }
}

// =============================================================== فريق الإدارة
class TeamAdminScreen extends StatelessWidget {
  const TeamAdminScreen({super.key});
  static const roles = {'super': 'مدير عام', 'moderator': 'مشرف', 'finance': 'مالية'};

  Future<void> _pickRole(BuildContext context, String id, String email, String current) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => rtl(SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(email, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800))),
          for (final e in roles.entries)
            ListTile(
              leading: Icon(current == e.key ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(e.value),
              onTap: () => Navigator.pop(c, e.key),
            ),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline, color: AppColors.emergency),
            title: const Text('إزالة الصلاحية', style: TextStyle(color: AppColors.emergency)),
            onTap: () => Navigator.pop(c, 'none'),
          ),
        ]),
      )),
    );
    if (r == null || !context.mounted) return;
    await runAdmin(context, () => AdminService.instance.setAdminRole(id, email, r));
  }

  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    return rtl(DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('فريق الإدارة'), bottom: const TabBar(tabs: [Tab(text: 'المديرين'), Tab(text: 'سجل العمليات')])),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(14), children: [
            const InfoBox('عشان تضيف مشرف: يفتح التطبيق ويدوس "دخول الإدارة" ويسجل بحسابه مرة، فيظهر هنا تحت "طلبات صلاحية" وتختار دوره.'),
            const SizedBox(height: 12),
            const Text('طلبات صلاحية جديدة', style: TextStyle(fontWeight: FontWeight.w800)),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: a.col('adminRequests').snapshots(),
              builder: (context, s) {
                final docs = s.data?.docs ?? [];
                if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('لا يوجد', style: TextStyle(color: AppColors.muted)));
                return Column(children: [
                  for (final d in docs)
                    AdminCard(
                      child: Row(children: [
                        Expanded(child: Text('${d.data()['email']}', textDirection: TextDirection.ltr)),
                        TextButton(onPressed: () => _pickRole(context, d.id, '${d.data()['email']}', ''), child: const Text('منح صلاحية')),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => runAdmin(context, () => a.ref('adminRequests/${d.id}').delete()),
                        ),
                      ]),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 12),
            const Text('المديرين الحاليين', style: TextStyle(fontWeight: FontWeight.w800)),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: a.col('admins').snapshots(),
              builder: (context, s) => Column(children: [
                for (final d in s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  AdminCard(
                    onTap: d.data()['owner'] == true ? null : () => _pickRole(context, d.id, '${d.data()['email']}', '${d.data()['role']}'),
                    child: Row(children: [
                      Expanded(child: Text('${d.data()['email']}', textDirection: TextDirection.ltr)),
                      Pill(d.data()['owner'] == true ? 'صاحب التطبيق' : roles[d.data()['role']] ?? '${d.data()['role']}'),
                    ]),
                  ),
              ]),
            ),
          ]),
          QueryList(
            query: a.col('adminActions').orderBy('createdAt', descending: true).limit(150),
            empty: 'لا يوجد',
            itemBuilder: (context, d) {
              final x = d.data();
              return ListTile(
                dense: true,
                title: Text('${x['action']} — ${x['targetType']}'),
                subtitle: Text('${x['adminEmail'] ?? ''} • ${fmtTs(x['createdAt'])}'),
              );
            },
          ),
        ]),
      ),
    ));
  }
}
