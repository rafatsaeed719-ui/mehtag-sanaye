import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/services/api.dart';
import '../../data/session.dart';
import 'report_screen.dart';

/// المساعدة والدعم
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<CatalogRepo>().publicSettings;
    final phone = (s['supportPhone'] ?? '').toString();
    final wa = (s['supportWhatsapp'] ?? '').toString();
    final email = (s['supportEmail'] ?? '').toString();
    final signedIn = context.read<Session>().user != null;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('help_support'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionTitle(context.t('faq')),
        Card(
          child: Column(children: [
            for (var i = 1; i <= 6; i++)
              ExpansionTile(
                title: Text(context.t('faq_q$i'), style: const TextStyle(fontWeight: FontWeight.w700)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [Text(context.t('faq_a$i'), style: const TextStyle(height: 1.5))],
              ),
          ]),
        ),
        SectionTitle(context.t('contact_support')),
        Card(
          child: Column(children: [
            if (phone.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: Text(context.t('support_phone')),
                subtitle: Text(phone, textDirection: TextDirection.ltr),
                onTap: () => launchUrl(Uri.parse('tel:$phone')),
              ),
            if (wa.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.chat_outlined, color: Color(0xFF15803D)),
                title: Text(context.t('whatsapp')),
                subtitle: Text(wa, textDirection: TextDirection.ltr),
                onTap: () => launchUrl(Uri.parse(Fmt.whatsappLink(wa)), mode: LaunchMode.externalApplication),
              ),
            if (email.isNotEmpty)
              ListTile(leading: const Icon(Icons.email_outlined), title: Text(email), onTap: () => launchUrl(Uri.parse('mailto:$email'))),
            if (signedIn) ...[
              ListTile(
                leading: const Icon(Icons.support_agent),
                title: Text(context.t('contact_support')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TicketScreen(kind: 'support'))),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(context.t('report_tech_issue')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TicketScreen(kind: 'technical'))),
              ),
              ListTile(
                leading: const Icon(Icons.report_gmailerrorred_outlined),
                title: Text(context.t('complaints')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(context.t('my_reports')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyReportsScreen())),
              ),
            ],
          ]),
        ),
        SectionTitle(context.t('terms')),
        const PoliciesList(),
      ]),
    );
  }
}

class PoliciesList extends StatelessWidget {
  const PoliciesList({super.key});
  @override
  Widget build(BuildContext context) {
    final cat = context.watch<CatalogRepo>();
    final items = {
      'terms': 'policy_terms',
      'privacy_policy': 'policy_privacy',
      'cancellation_policy': 'policy_cancellation',
      'rating_policy': 'policy_rating',
      'commission_policy': 'policy_commission',
    };
    return Card(
      child: Column(children: [
        for (final e in items.entries)
          ExpansionTile(
            title: Text(context.t(e.key), style: const TextStyle(fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(context.t(e.value, {'rate': cat.commissionPercent, 'days': cat.overdueDays}), style: const TextStyle(height: 1.6)),
            ],
          ),
      ]),
    );
  }
}

class PoliciesScreen extends StatelessWidget {
  const PoliciesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.t('terms'))),
        body: ListView(padding: const EdgeInsets.all(16), children: const [PoliciesList()]),
      );
}

/// تذكرة دعم / مشكلة تقنية
class TicketScreen extends StatefulWidget {
  final String kind;
  const TicketScreen({super.key, required this.kind});
  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  Future<void> _send() async {
    if (_subject.text.trim().length < 3 || _message.text.trim().length < 10) {
      showSnack(context, context.t('required'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.instance.submitSupportTicket({
        'kind': widget.kind,
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
        'appVersion': '1.0.0',
        'device': 'android',
      });
      if (!mounted) return;
      showSnack(context, context.t('ticket_sent'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.kind == 'technical' ? context.t('report_tech_issue') : context.t('contact_support'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _subject, maxLength: 120, decoration: InputDecoration(labelText: context.t('ticket_subject'))),
          TextField(
            controller: _message,
            maxLines: 6,
            maxLength: 3000,
            decoration: InputDecoration(labelText: context.t('ticket_message'), alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          BusyButton(label: context.t('send'), busy: _busy, onPressed: _send),
          const SizedBox(height: 12),
          const Text('', style: TextStyle(color: AppColors.muted)),
        ]),
      );
}
