import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../i18n/i18n.dart';
import '../theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
}

class EmptyView extends StatelessWidget {
  final String text;
  final IconData icon;
  final Widget? action;
  const EmptyView({super.key, required this.text, this.icon = Icons.inbox_outlined, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppColors.muted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(context.t('retry'))),
            ],
          ]),
        ),
      );
}

class Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;
  const Avatar({super.key, required this.url, required this.name, this.size = 48});
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? Container(
                color: AppColors.amberSoft,
                alignment: Alignment.center,
                child: Text(initial, style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: AppColors.navy)),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).toInt(),
                errorWidget: (_, __, ___) => Container(color: AppColors.amberSoft, child: const Icon(Icons.person, color: AppColors.navy)),
              ),
      ),
    );
  }
}

class NetImage extends StatelessWidget {
  final String url;
  final double? width, height;
  final double radius;
  final BoxFit fit;
  const NetImage({super.key, required this.url, this.width, this.height, this.radius = 12, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          placeholder: (_, __) => Container(color: AppColors.border),
          errorWidget: (_, __, ___) => Container(color: AppColors.border, child: const Icon(Icons.broken_image_outlined)),
        ),
      );
}

void openImageViewer(BuildContext context, String url) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url))),
    ),
  ));
}

class Stars extends StatelessWidget {
  final double value;
  final double size;
  const Stars({super.key, required this.value, this.size = 16});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final v = value - i;
          final icon = v >= 0.75 ? Icons.star_rounded : (v >= 0.25 ? Icons.star_half_rounded : Icons.star_outline_rounded);
          return Icon(icon, size: size, color: AppColors.amber);
        }),
      );
}

class RatingLine extends StatelessWidget {
  final double avg;
  final int count;
  const RatingLine({super.key, required this.avg, required this.count});
  @override
  Widget build(BuildContext context) {
    if (count == 0) return Text(context.t('no_reviews'), style: const TextStyle(color: AppColors.muted, fontSize: 12));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, color: AppColors.amber, size: 18),
      const SizedBox(width: 2),
      Text(avg.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(width: 4),
      Text('(${context.t('reviews_count', {'n': count})})', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }
}

class BadgeChips extends StatelessWidget {
  final List<String> badges;
  final bool small;
  const BadgeChips({super.key, required this.badges, this.small = false});
  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final b in badges)
        Container(
          padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
          decoration: BoxDecoration(
            color: b == 'verified' ? const Color(0xFFE8F5EE) : AppColors.amberSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(context.t('badge_$b'),
              style: TextStyle(fontSize: small ? 10.5 : 12, fontWeight: FontWeight.w700, color: b == 'verified' ? AppColors.success : AppColors.navy)),
        ),
    ]);
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'new':
    case 'proposed':
      return AppColors.warning;
    case 'accepted':
    case 'confirmed':
    case 'on_the_way':
    case 'started':
      return const Color(0xFF2563EB);
    case 'completed':
    case 'price_set':
      return const Color(0xFF7C3AED);
    case 'price_agreed':
    case 'commission_paid':
      return AppColors.success;
    case 'rejected':
    case 'cancelled':
      return AppColors.emergency;
  }
  return AppColors.muted;
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(context.t('status_$status'), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// أيقونة المهنة: صورة مرفوعة من لوحة التحكم أو أيقونة Material
const Map<String, IconData> kCategoryIcons = {
  'plumbing': Icons.plumbing,
  'electrical_services': Icons.electrical_services,
  'carpenter': Icons.carpenter,
  'format_paint': Icons.format_paint,
  'ac_unit': Icons.ac_unit,
  'car_repair': Icons.car_repair,
  'kitchen': Icons.kitchen,
  'grid_on': Icons.grid_on,
  'construction': Icons.construction,
  'hardware': Icons.hardware,
  'window': Icons.window,
  'satellite_alt': Icons.satellite_alt,
  'cleaning_services': Icons.cleaning_services,
  'local_shipping': Icons.local_shipping,
  'handyman': Icons.handyman,
  'roofing': Icons.roofing,
  'water_drop': Icons.water_drop,
  'bolt': Icons.bolt,
  'build': Icons.build,
  'pest_control': Icons.pest_control,
  'yard': Icons.yard,
  'pool': Icons.pool,
  'solar_power': Icons.solar_power,
  'computer': Icons.computer,
  'phone_android': Icons.phone_android,
  'lock': Icons.lock,
  'chair': Icons.chair,
  'bathtub': Icons.bathtub,
};

class CategoryIcon extends StatelessWidget {
  final JobCategory category;
  final double size;
  final Color color;
  const CategoryIcon({super.key, required this.category, this.size = 28, this.color = AppColors.navy});
  @override
  Widget build(BuildContext context) {
    if (category.iconUrl.isNotEmpty) {
      return CachedNetworkImage(imageUrl: category.iconUrl, width: size, height: size, errorWidget: (_, __, ___) => Icon(Icons.handyman, size: size, color: color));
    }
    return Icon(kCategoryIcons[category.icon] ?? Icons.handyman, size: size, color: color);
  }
}

/// زر بحالة تحميل
class BusyButton extends StatelessWidget {
  final String label;
  final Future<void> Function()? onPressed;
  final bool busy;
  final Color? color;
  final IconData? icon;
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.color, this.icon});
  @override
  Widget build(BuildContext context) => ElevatedButton(
        style: color == null ? null : ElevatedButton.styleFrom(backgroundColor: color),
        onPressed: busy || onPressed == null ? null : () => onPressed!(),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ]),
      );
}

Future<bool> confirmDialog(BuildContext context, String message, {String? okText, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.t('no'))),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(okText ?? context.t('yes'), style: TextStyle(color: danger ? AppColors.emergency : null, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r == true;
}

/// اختيار مصدر الصورة (كاميرا/معرض)
Future<bool?> pickSourceSheet(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(context.t('camera')), onTap: () => Navigator.pop(c, true)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(context.t('gallery')), onTap: () => Navigator.pop(c, false)),
        ]),
      ),
    );

class InfoBox extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const InfoBox(this.text, {super.key, this.icon = Icons.info_outline, this.color = AppColors.navy});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.4))),
        ]),
      );
}
