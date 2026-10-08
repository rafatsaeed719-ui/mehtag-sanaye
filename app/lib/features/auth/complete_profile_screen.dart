import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/session.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController(text: FirebaseAuth.instance.currentUser?.displayName ?? '');
  bool _busy = false;
  late String _role;

  @override
  void initState() {
    super.initState();
    final r = context.read<Session>().chosenRole;
    _role = r.isEmpty ? 'customer' : r;
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) {
      showSnack(context, context.t('required'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final s = context.read<Session>();
      await s.chooseRole(_role);
      await s.completeProfile(_name.text.trim());
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
            const SizedBox(height: 8),
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
