import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/worker_repo.dart';
import '../shared/location_picker.dart';
import '../shared/widgets.dart';
import 'create_request_screen.dart';
import 'customer_location.dart';
import 'map_screen.dart';
import 'worker_profile_screen.dart';

/// البحث: بالمهنة / بالخدمة / بالاسم / بالموقع + الفلاتر + الترتيب + الخريطة
class SearchScreen extends StatefulWidget {
  final String? categoryId;
  final bool focusSearch;
  final bool startOnMap;
  const SearchScreen({super.key, this.categoryId, this.focusSearch = false, this.startOnMap = false});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late SearchFilters _f;
  final _q = TextEditingController();
  Future<List<Worker>>? _results;
  late bool _map;

  @override
  void initState() {
    super.initState();
    _f = SearchFilters(categoryId: widget.categoryId);
    _map = widget.startOnMap;
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    var loc = context.read<CustomerLocation>().current;
    if (loc == null) {
      final p = await showLocationChooser(context);
      if (p == null) return;
      if (!mounted) return;
      await context.read<CustomerLocation>().set(p);
      loc = p;
    }
    if (!mounted) return;
    _f.nameQuery = _q.text.trim();
    final here = loc;
    setState(() => _results = WorkerRepo.instance.search(lat: here.lat, lng: here.lng, f: _f));
  }

  Future<void> _openFilters() async {
    final f = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: _f.copy()),
    );
    if (f != null) {
      _f = f;
      _run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogRepo>();
    final loc = context.watch<CustomerLocation>().current;
    final lang = context.lang;
    final cat = catalog.category(_f.categoryId);
    final activeFilters = [
      if (_f.serviceId != null) 1,
      if (_f.availableOnly) 1,
      if (_f.verifiedOnly) 1,
      if (_f.sort != SortMode.smart) 1,
      if (_f.radiusKm != 25) 1,
    ].length;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: widget.focusSearch,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: context.t('search_hint'),
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _q.clear();
                      _run();
                    }),
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            tooltip: _map ? context.t('list_view') : context.t('map_view'),
            icon: Icon(_map ? Icons.view_list : Icons.map_outlined),
            onPressed: () => setState(() => _map = !_map),
          ),
        ],
      ),
      body: Column(children: [
        // شريط المهن + الفلاتر
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              ActionChip(
                avatar: Badge(isLabelVisible: activeFilters > 0, label: Text('$activeFilters'), child: const Icon(Icons.tune, size: 18)),
                label: Text(context.t('filters')),
                onPressed: _openFilters,
              ),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.location_on_outlined, size: 18),
                label: Text(loc == null ? context.t('location_unknown') : context.t('within_km', {'km': _f.radiusKm.toInt()})),
                onPressed: () async {
                  final p = await showLocationChooser(context, current: loc);
                  if (p != null) {
                    await context.read<CustomerLocation>().set(p);
                    _run();
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(context.t('all')),
                selected: _f.categoryId == null,
                onSelected: (_) {
                  _f.categoryId = null;
                  _f.serviceId = null;
                  _run();
                },
              ),
              for (final c in catalog.categories) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: CategoryIcon(category: c, size: 18),
                  label: Text(c.name(lang)),
                  selected: _f.categoryId == c.id,
                  onSelected: (_) {
                    _f.categoryId = c.id;
                    _f.serviceId = null;
                    _run();
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _results == null
              ? const LoadingView()
              : FutureBuilder<List<Worker>>(
                  future: _results,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) return const LoadingView();
                    if (snap.hasError) return ErrorView(message: friendlyError(context, snap.error!), onRetry: _run);
                    final list = snap.data ?? [];
                    if (_map && loc != null) {
                      return WorkersMap(center: loc, workers: list);
                    }
                    if (list.isEmpty) {
                      return EmptyView(
                        text: context.t('no_workers_found'),
                        icon: Icons.person_search_outlined,
                        action: cat == null
                            ? null
                            : ElevatedButton.icon(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateRequestScreen(categoryId: cat.id))),
                                icon: const Icon(Icons.campaign_outlined),
                                label: Text(context.t('new_request')),
                              ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: list.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Text('${context.t('search_results')} (${list.length})', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600));
                        }
                        final w = list[i - 1];
                        return WorkerCard(
                          w: w,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerProfileScreen(workerId: w.id, distanceKm: w.distanceKm))),
                        );
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class FilterSheet extends StatefulWidget {
  final SearchFilters initial;
  const FilterSheet({super.key, required this.initial});
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late SearchFilters f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogRepo>();
    final lang = context.lang;
    final services = catalog.servicesOf(f.categoryId);
    final sorts = {
      SortMode.smart: 'sort_smart',
      SortMode.nearest: 'sort_nearest',
      SortMode.rating: 'sort_rating',
      SortMode.reviews: 'sort_reviews',
      SortMode.feeLow: 'sort_fee_low',
      SortMode.feeHigh: 'sort_fee_high',
    };
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Expanded(child: Text(context.t('filters'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          TextButton(onPressed: () => setState(() => f = SearchFilters(categoryId: f.categoryId)), child: Text(context.t('reset'))),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: f.categoryId,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.t('filter_category')),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(context.t('all'))),
            ...catalog.categories.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name(lang)))),
          ],
          onChanged: (v) => setState(() {
            f.categoryId = v;
            f.serviceId = null;
          }),
        ),
        if (services.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: f.serviceId,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.t('filter_service')),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(context.t('all'))),
              ...services.map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name(lang)))),
            ],
            onChanged: (v) => setState(() => f.serviceId = v),
          ),
        ],
        const SizedBox(height: 16),
        Text('${context.t('filter_radius')}: ${f.radiusKm.toInt()} ${context.t('km')}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(
          value: f.radiusKm,
          min: 2,
          max: 100,
          divisions: 49,
          label: '${f.radiusKm.toInt()}',
          onChanged: (v) => setState(() => f.radiusKm = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('filter_available')),
          value: f.availableOnly,
          onChanged: (v) => setState(() => f.availableOnly = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('filter_verified')),
          value: f.verifiedOnly,
          onChanged: (v) => setState(() => f.verifiedOnly = v),
        ),
        const SizedBox(height: 8),
        Text(context.t('sort_by'), style: const TextStyle(fontWeight: FontWeight.w700)),
        RadioGroupFallback(
          value: f.sort,
          options: sorts.map((k, v) => MapEntry(k, context.t(v))),
          onChanged: (v) => setState(() => f.sort = v),
        ),
        InfoBox(context.t('smart_sort_note')),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => Navigator.pop(context, f), child: Text(context.t('apply'))),
      ]),
    );
  }
}

/// قائمة اختيار واحد (بدون الاعتماد على Radio API المتغير بين إصدارات Flutter)
class RadioGroupFallback<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const RadioGroupFallback({super.key, required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final e in options.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            onTap: () => onChanged(e.key),
            leading: Icon(e.key == value ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: AppColors.navy),
            title: Text(e.value),
          ),
      ]);
}
