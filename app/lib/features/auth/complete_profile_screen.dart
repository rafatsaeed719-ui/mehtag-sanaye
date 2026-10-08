import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/session.dart';

/// استكمال البيانات أول مرة: الاسم + رقم الموبايل (رقم واحد لكل حساب) + نوع الحساب
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController(text: FirebaseAuth.instance.currentUser?.displayName ?? '');
  final _phone = TextEditingController();
  bool _busy = false;
  late String _role;

  @override
  void initState() {
    super.initState();
    final r = context.read<Session>().chosenRole;
    _role = r.isEmpty ? 'customer' : r;
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = Fmt.normalizePhone(_phone.text);
    if (name.length < 2) {
      showSnack(context, '${context.t('your_name')}: ${context.t('required')}', error: true);
      return;
    }
    if (!Fmt.isEgMobile(phone)) {
      showSnack(context, context.t('invalid_phone'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<Session>().completeProfile(name: name, phone: phone, role: _role);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      // القواعد بترفض لو الرقم مسجل بحساب تاني
      showSnack(context, e.code == 'permission-denied' ? context.t('phone_in_use') : context.t('error_generic'), error: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.t('complete_profile')),
          actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<Session>().signOut())],
        ),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: InputDecoration(labelText: context.t('your_name'), prefixIcon: const Icon(Icons.person_outline)),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+٠-٩ ]')), LengthLimitingTextInputFormatter(16)],
              decoration: InputDecoration(
                labelText: context.t('phone_number'),
                hintText: context.t('phone_hint'),
                helperText: context.t('one_account_per_phone'),
                prefixIcon: const Icon(Icons.phone_iphone),
              ),
            ),
            const SizedBox(height: 16),
            Text(context.t('account_type'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'customer', label: Text(context.t('i_am_customer')), icon: const Text('👤')),
                ButtonSegment(value: 'worker', label: Text(context.t('i_am_worker')), icon: const Text('🔧')),
              ],
              selected: {_role},
              onSelectionChanged: (v) => setState(() => _role = v.first),
            ),
            const SizedBox(height: 28),
            BusyButton(label: context.t('create_account'), busy: _busy, onPressed: _submit),
          ]),
        ),
      );
}
