/// TaWorld 城市选择器 — 底部弹出面板
///
/// 三级结构：国家 → 省/州 → 城市。
/// 支持模糊搜索 + 省-市浏览，默认中国。
library;

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../data/city_data.dart';

/// 城市选择器结果
class CitySelection {
  const CitySelection({
    required this.city,
    required this.province,
    this.country = kDefaultCountry,
  });
  final String city;
  final String province;
  final String country;

  /// 显示文本：中国城市显示"省 · 市"，国外显示"国家 · 城市"
  String get displayText {
    if (country == kDefaultCountry) {
      return province.isNotEmpty ? '$province · $city' : city;
    }
    return '$country · $city';
  }

  @override
  String toString() => displayText;
}

/// 弹出城市选择器，返回选中的城市（null 表示取消）
Future<CitySelection?> showCityPicker(BuildContext context) {
  return showModalBottomSheet<CitySelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (_, scrollController) => _CityPickerSheet(
        scrollController: scrollController,
      ),
    ),
  );
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedCountry = kDefaultCountry;
  String? _expandedProvince;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(TaRadius.lg),
        ),
      ),
      child: Column(
        children: [
          // 拖动把手
          Padding(
            padding: const EdgeInsets.only(top: TaSpacing.sm),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TaSpacing.pagePadding, TaSpacing.sm, TaSpacing.pagePadding, 0,
            ),
            child: Row(
              children: [
                Text('选择城市',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),

          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TaSpacing.pagePadding,
              vertical: TaSpacing.xs,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: TaRadius.borderFull,
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '输入城市名搜索...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: TaSpacing.md,
                    vertical: TaSpacing.sm,
                  ),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                  suffixIcon: _isSearching
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),

          // 国家选择（搜索时隐藏）
          if (!_isSearching)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: TaSpacing.pagePadding),
                itemCount: kCountries.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: TaSpacing.xs),
                itemBuilder: (_, i) {
                  final country = kCountries[i];
                  final selected = country == _selectedCountry;
                  return ChoiceChip(
                    label: Text(country),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _selectedCountry = country;
                        _expandedProvince = null;
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),

          // 内容区域
          Expanded(
            child: _isSearching
                ? _buildSearchResults(theme)
                : _buildBrowseView(theme),
          ),

          SizedBox(height: bottom),
        ],
      ),
    );
  }

  // ---- 搜索结果 ----
  Widget _buildSearchResults(ThemeData theme) {
    final results = searchCities(_query);

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: TaSpacing.xs),
            Text(
              '没有找到匹配的城市',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: TaSpacing.pagePadding),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final match = results[index];
        return _CityTile(
          city: match.city,
          subtitle: match.country == kDefaultCountry
              ? match.province
              : '${match.country} · ${match.province}',
          onTap: () => Navigator.of(context).pop(CitySelection(
            city: match.city,
            province: match.province,
            country: match.country,
          )),
        );
      },
    );
  }

  // ---- 省-市浏览 ----
  Widget _buildBrowseView(ThemeData theme) {
    final provinces = provincesOf(_selectedCountry);

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: TaSpacing.pagePadding),
      itemCount: provinces.length,
      itemBuilder: (context, index) {
        final province = provinces[index];
        final isExpanded = _expandedProvince == province;
        final cities = citiesOf(_selectedCountry, province);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _expandedProvince = isExpanded ? null : province;
                });
              },
              borderRadius: TaRadius.borderXs,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: TaSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: TaSpacing.xs),
                    Expanded(
                      child: Text(
                        province,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${cities.length} 市',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: TaSpacing.xs),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: TaAnimation.fast,
                      child: Icon(Icons.expand_more_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Wrap(
                spacing: TaSpacing.xs,
                runSpacing: TaSpacing.xs,
                children: cities.map((city) {
                  return ActionChip(
                    label: Text(city),
                    onPressed: () => Navigator.of(context).pop(
                      CitySelection(
                        city: city,
                        province: province,
                        country: _selectedCountry,
                      ),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: TaAnimation.normal,
            ),
            if (index < provinces.length - 1)
              Divider(
                height: 1,
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
          ],
        );
      },
    );
  }
}

/// 城市列表项
class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.city,
    required this.subtitle,
    required this.onTap,
  });

  final String city;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.location_city_rounded,
          color: theme.colorScheme.primary, size: 22),
      title: Text(city, style: theme.textTheme.bodyLarge),
      subtitle: Text(subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
      trailing: Icon(Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurfaceVariant),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
    );
  }
}
