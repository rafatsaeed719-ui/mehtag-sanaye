import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repos/catalog_repo.dart';
import 'admin_service.dart';
import 'admin_ui.dart';

String govName(BuildContext context, dynamic code) {
  for (final g in context.read<CatalogRepo>().governorates) {
    if (g.code == code) return g.nameAr;
  }
  return (code ?? '').toString();
}

// =============================================================== الصنايعية
class WorkersAdminScreen extends StatelessWidget {
  final int initialTab;
  const WorkersAdminScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    Query<Map<String, dynamic>> byStatus(String s) =>
        a.col('workers').where('verificationStatus', isEqualTo: s).orderBy('submittedAt', descending: true).limit(200);
    return rtl(DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الصنايعية'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'قيد المراجعة'),
            Tab(text: 'موثّقون'),
            Tab(text: 'مرفوضون'),
            Tab(text: 'تعديلات معلقة'),
          ]),
        ),
        body: TabBarView(children: [
          for (final s in ['pending', 'approved', 'rejected'])
            QueryList(
              query: byStatus(s),
              empty: 'مفيش صنايعية هنا',
              itemBuilder: (context, d) => _WorkerTile(id: d.id, w: d.data()),
            ),
          QueryList(
            query: a.col('workerChangeRequests').where('status', isEqualTo: 'pending').orderBy('createdAt', descending: true).limit(100),
            empty: 'مفيش تعديلات مستنية',
            itemBuilder: (context, d) => _ChangeTile(id: d.id, c: d.data()),
          ),
        ]),
      ),
    ));
  }
}

class _WorkerTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> w;
  const _WorkerTile({required this.id, required this.w});
  @override
  Widget build(BuildContext context) {
    final cats = List.from(w['categoryNames'] ?? []).map(locName).join('، ');
    final rc = (w['ratingCount'] as num?) ?? 0;
    return AdminCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerReviewScreen(workerId: id))),
      child: Row(children: [
        Avatar(url: (w['photoUrl'] ?? '').toString(), name: (w['name'] ?? '').toString(), size: 50),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text((w['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
              if (w['suspended'] == true) ...[const SizedBox(width: 6), const Pill('موقوف', color: AppColors.emergency)],
              if (w['pendingChange'] == true) ...[const SizedBox(width: 6), const Pill('تعديل معلق')],
            ]),
            Text(cats, style: const TextStyle(color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Text('${govName(context, w['governorate'])} - ${w['city'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
              w['hasIdDoc'] == true
                  ? Pill(w['idVerified'] == true ? 'البطاقة موثّقة' : 'البطاقة مرفوعة', color: w['idVerified'] == true ? AppColors.success : AppColors.warning)
                  : const Pill('من غير بطاقة', color: AppColors.muted),
              if (rc > 0) Text('${(((w['ratingSum'] as num?) ?? 0) / rc).toStringAsFixed(1)} ★ ($rc)', style: const TextStyle(fontSize: 12.5)),
            ]),
          ]),
        ),
        const Icon(Icons.chevron_left),
      ]),
    );
  }
}

class WorkerReviewScreen extends StatefulWidget {
  final String workerId;
  const WorkerReviewScreen({super.key, required this.workerId});
  @override
  State<WorkerReviewScreen> createState() => _WorkerReviewScreenState();
}

class _WorkerReviewScreenState extends State<WorkerReviewScreen> {
  final a = AdminService.instance;
  Map<String, dynamic>? _priv;
  bool _idVerified = false;
  bool _busy = false;
  final _reason = TextEditingController();
  bool _init = false;

  @override
  void initState() {
    super.initState();
    a.workerPrivate(widget.workerId).then((p) => mounted ? setState(() => _priv = p) : null).catchError((_) {
      if (mounted) setState(() => _priv = {});
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _act(String decision) async {
    if (decision == 'reject' && _reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب سبب الرفض الأول')));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAdmin(context, () => a.reviewWorker(widget.workerId, decision, reason: _reason.text.trim(), idVerified: _idVerified));
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('مراجعة صنايعي')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: a.ref('workers/${widget.workerId}').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final w = snap.data!.data() ?? {};
          if (!_init) {
            _init = true;
            _idVerified = w['idVerified'] == true;
            _reason.text = (w['rejectionReason'] ?? '').toString();
          }
          final geo = w['geo'] as Map?;
          final images = List<String>.from(w['workImages'] ?? []);
          final front = (_priv?['idFrontRef'] ?? '').toString();
          final back = (_priv?['idBackRef'] ?? '').toString();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              GestureDetector(
                onTap: () => (w['photoUrl'] ?? '').toString().isEmpty ? null : openImageViewer(context, w['photoUrl']),
                child: Avatar(url: (w['photoUrl'] ?? '').toString(), name: (w['name'] ?? '').toString(), size: 70),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((w['name'] ?? '').toString(), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Pill.status((w['verificationStatus'] ?? '').toString(), kWorkerStatus),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            AdminCard(
              child: Column(children: [
                KV('الموبايل', (w['phone'] ?? '').toString(), ltr: true, trailing: IconButton(icon: const Icon(Icons.call, color: AppColors.navy), onPressed: () => callPhone((w['phone'] ?? '').toString()))),
                KV('واتساب', (w['whatsapp'] ?? '').toString(), ltr: true, trailing: IconButton(icon: const Icon(Icons.chat, color: AppColors.success), onPressed: () => openWhatsapp((w['whatsapp'] ?? w['phone'] ?? '').toString()))),
                KV('المهن', List.from(w['categoryNames'] ?? []).map(locName).join('، ')),
                KV('الخدمات', List.from(w['serviceNames'] ?? []).map(locName).join('، ')),
                KV('المكان', '${govName(context, w['governorate'])} - ${w['city'] ?? ''} - ${w['area'] ?? ''}',
                    trailing: geo == null ? null : IconButton(icon: const Icon(Icons.map_outlined, color: AppColors.navy), onPressed: () => openMap(geo['lat'], geo['lng']))),
                KV('سعر الكشف', w['visitFee'] == null ? '' : money(w['visitFee'])),
                KV('نبذة', (w['bio'] ?? '').toString()),
                KV('الرقم القومي', _priv == null ? '...' : (_priv!['nationalId'] ?? '').toString(), ltr: true),
                KV('تاريخ التقديم', fmtTs(w['submittedAt'])),
              ]),
            ),
            const Text('البطاقة الشخصية (سرية — ماتتشاركش)', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_priv == null)
              const LinearProgressIndicator()
            else if (front.isEmpty && back.isEmpty)
              const Text('لم يرفع بطاقة', style: TextStyle(color: AppColors.muted))
            else
              Row(children: [
                if (front.isNotEmpty) Expanded(child: _IdImage(front)),
                if (front.isNotEmpty && back.isNotEmpty) const SizedBox(width: 8),
                if (back.isNotEmpty) Expanded(child: _IdImage(back)),
              ]),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('أعمال سابقة', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final i in images) Thumb(i)]),
            ],
            const Divider(height: 32),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _idVerified,
              onChanged: w['hasIdDoc'] == true ? (v) => setState(() => _idVerified = v == true) : null,
              title: const Text('البطاقة مطابقة (ياخد علامة موثّق ✓)'),
            ),
            TextField(controller: _reason, decoration: const InputDecoration(labelText: 'سبب الرفض (مطلوب لو هترفض)')),
            const SizedBox(height: 16),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: () => _act('approve'),
                icon: const Icon(Icons.verified),
                label: const Text('قبول وتوثيق'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.emergency),
                    onPressed: () => _act('reject'),
                    icon: const Icon(Icons.close),
                    label: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(onPressed: () => _act('pending'), icon: const Icon(Icons.undo), label: const Text('إرجاع للمراجعة')),
                ),
              ]),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserManageScreen(userId: widget.workerId))),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('إدارة الحساب (إيقاف / حظر / حذف)'),
              ),
            ],
          ]);
        },
      ),
    ));
  }
}

class _IdImage extends StatelessWidget {
  final String src;
  const _IdImage(this.src);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => openImageViewer(context, src),
        child: NetImage(url: src, height: 130, fit: BoxFit.cover),
      );
}

class _ChangeTile extends StatefulWidget {
  final String id;
  final Map<String, dynamic> c;
  const _ChangeTile({required this.id, required this.c});
  @override
  State<_ChangeTile> createState() => _ChangeTileState();
}

class _ChangeTileState extends State<_ChangeTile> {
  bool _idOk = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final ch = Map<String, dynamic>.from(c['changes'] ?? {});
    final cat = context.read<CatalogRepo>();
    String catName(String id) => cat.category(id)?.nameAr ?? id;
    String svcName(String id) {
      for (final s in cat.services) {
        if (s.id == id) return s.nameAr;
      }
      return id;
    }

    final identity = c['identity'] as Map<String, dynamic>?;
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text((c['workerName'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
          Text(fmtTs(c['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        if ((ch['name'] ?? '').toString().isNotEmpty) KV('الاسم الجديد', ch['name'].toString()),
        if (ch['categoryIds'] != null) KV('المهن الجديدة', List<String>.from(ch['categoryIds']).map(catName).join('، ')),
        if (ch['serviceIds'] != null) KV('الخدمات الجديدة', List<String>.from(ch['serviceIds']).map(svcName).join('، ')),
        if (identity != null) ...[
          KV('رقم قومي جديد', (identity['nationalId'] ?? '').toString(), ltr: true),
          Row(children: [
            if ((identity['idFrontRef'] ?? '').toString().isNotEmpty) Expanded(child: _IdImage(identity['idFrontRef'])),
            if ((identity['idBackRef'] ?? '').toString().isNotEmpty) ...[const SizedBox(width: 8), Expanded(child: _IdImage(identity['idBackRef']))],
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _idOk,
            onChanged: (v) => setState(() => _idOk = v == true),
            title: const Text('الهوية مطابقة'),
          ),
        ],
        const SizedBox(height: 8),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else
          Row(children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: () async {
                  setState(() => _busy = true);
                  await runAdmin(context, () => AdminService.instance.reviewChange(widget.id, 'approve', idVerified: _idOk));
                  if (mounted) setState(() => _busy = false);
                },
                child: const Text('اعتماد'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.emergency),
                onPressed: () async {
                  final reason = await askText(context, 'سبب الرفض');
                  if (reason == null || !mounted) return;
                  setState(() => _busy = true);
                  await runAdmin(context, () => AdminService.instance.reviewChange(widget.id, 'reject', reason: reason));
                  if (mounted) setState(() => _busy = false);
                },
                child: const Text('رفض'),
              ),
            ),
          ]),
      ]),
    );
  }
}

// =============================================================== المستخدمون
class UsersAdminScreen extends StatefulWidget {
  const UsersAdminScreen({super.key});
  @override
  State<UsersAdminScreen> createState() => _UsersAdminScreenState();
}

class _UsersAdminScreenState extends State<UsersAdminScreen> {
  final a = AdminService.instance;
  String _role = 'customer';
  String _phone = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _phone.isNotEmpty
        ? a.col('users').where('phone', isEqualTo: _phone)
        : a.col('users').where('role', isEqualTo: _role).orderBy('createdAt', descending: true).limit(200);
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('المستخدمون')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: TextField(
            controller: _search,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'بحث برقم الموبايل 01xxxxxxxxx',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _phone.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _search.clear();
                        _phone = '';
                      }),
                    ),
            ),
            onSubmitted: (v) => setState(() => _phone = v.trim().replaceFirst(RegExp(r'^\+?20'), '0')),
          ),
        ),
        if (_phone.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'customer', label: Text('العملاء')), ButtonSegment(value: 'worker', label: Text('الصنايعية'))],
              selected: {_role},
              onSelectionChanged: (v) => setState(() => _role = v.first),
            ),
          ),
        Expanded(
          child: QueryList(
            key: ValueKey('$_role|$_phone'),
            query: q,
            empty: 'مفيش نتايج',
            itemBuilder: (context, d) {
              final u = d.data();
              return AdminCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserManageScreen(userId: d.id))),
                child: Row(children: [
                  Avatar(url: (u['photoUrl'] ?? '').toString(), name: (u['name'] ?? '').toString(), size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((u['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text((u['phone'] ?? '').toString(), textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.muted)),
                      Text('${u['role'] == 'worker' ? 'صنايعي' : 'عميل'} • سجّل ${fmtTs(u['createdAt'])}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                  ),
                  Pill.status((u['status'] ?? 'active').toString(), kUserStatus),
                ]),
              );
            },
          ),
        ),
      ]),
    ));
  }
}

class UserManageScreen extends StatefulWidget {
  final String userId;
  const UserManageScreen({super.key, required this.userId});
  @override
  State<UserManageScreen> createState() => _UserManageScreenState();
}

class _UserManageScreenState extends State<UserManageScreen> {
  final a = AdminService.instance;
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _reason = TextEditingController();
  DateTime? _until;
  bool _init = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _status(String s) async {
    if (s != 'active' && _reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب السبب الأول (بيظهر للمستخدم)')));
      return;
    }
    setState(() => _busy = true);
    await runAdmin(context, () => a.setUserStatus(widget.userId, s, reason: _reason.text.trim(), until: s == 'banned' ? _until : null));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return rtl(Scaffold(
      appBar: AppBar(title: const Text('إدارة حساب')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: a.ref('users/${widget.userId}').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final u = snap.data!.data();
          if (u == null) return const EmptyView(text: 'الحساب مش موجود');
          if (!_init) {
            _init = true;
            _name.text = (u['name'] ?? '').toString();
            _note.text = (u['adminNote'] ?? '').toString();
          }
          final phone = (u['phone'] ?? '').toString();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Avatar(url: (u['photoUrl'] ?? '').toString(), name: (u['name'] ?? '').toString(), size: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((u['name'] ?? '').toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: [
                    Pill.status((u['status'] ?? 'active').toString(), kUserStatus),
                    Pill(u['role'] == 'worker' ? 'صنايعي' : 'عميل'),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            AdminCard(
              child: Column(children: [
                KV('الموبايل', phone, ltr: true, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.call, color: AppColors.navy), onPressed: () => callPhone(phone)),
                  IconButton(icon: const Icon(Icons.chat, color: AppColors.success), onPressed: () => openWhatsapp(phone)),
                ])),
                KV('البريد', (u['email'] ?? '').toString(), ltr: true),
                KV('آخر دخول', fmtTs(u['lastLoginAt'])),
                KV('التسجيل', fmtTs(u['createdAt'])),
                KV('بلاغات ضده', '${u['reportsCount'] ?? 0}'),
                if ((u['customerRatingCount'] ?? 0) > 0)
                  KV('تقييمه كعميل', '${((u['customerRatingSum'] ?? 0) / u['customerRatingCount']).toStringAsFixed(1)} ★ (${u['customerRatingCount']})'),
                KV('سبب الحالة', (u['statusReason'] ?? '').toString()),
              ]),
            ),
            const Text('تعديل البيانات', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 10),
            TextField(controller: _note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'ملاحظة إدارية داخلية (مش بتظهر للمستخدم)')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => runAdmin(context, () => a.updateUser(widget.userId, name: _name.text.trim(), adminNote: _note.text)),
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ البيانات'),
            ),
            const Divider(height: 32),
            const Text('حالة الحساب', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(controller: _reason, decoration: const InputDecoration(labelText: 'السبب (بيظهر للمستخدم)')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_until == null ? 'حظر مؤقت لحد تاريخ (اختياري)' : 'الحظر لحد: ${_until!.day}/${_until!.month}/${_until!.year}'),
              trailing: _until == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _until = null)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                );
                if (d != null) setState(() => _until = DateTime(d.year, d.month, d.day, 23, 59));
              },
            ),
            const SizedBox(height: 8),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.success), onPressed: () => _status('active'), child: const Text('تفعيل')),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning), onPressed: () => _status('suspended'), child: const Text('إيقاف')),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergency), onPressed: () => _status('banned'), child: const Text('حظر')),
              ]),
            if (a.isSuper) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.emergency),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('حذف الحساب نهائيًا'),
                onPressed: () async {
                  final reason = await askText(context, 'سبب الحذف (إجراء نهائي)');
                  if (reason == null || !context.mounted) return;
                  if (!await askConfirm(context, 'متأكد؟ الحذف مش هينفع يترجع.', danger: true) || !context.mounted) return;
                  final ok = await runAdmin(context, () => a.deleteUser(widget.userId, reason));
                  if (ok && context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ]);
        },
      ),
    ));
  }
}
