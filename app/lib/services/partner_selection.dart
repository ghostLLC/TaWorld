import '../data/models/partner.dart';

abstract final class PartnerSelection {
  static Partner resolve(List<Partner> people, {String? id, String? name}) {
    final matches = people
        .where(
          (p) => id?.isNotEmpty == true
              ? p.id == id
              : p.nickname.trim() == name?.trim(),
        )
        .toList();
    if (matches.isEmpty) throw StateError('没有找到这位好友，请读取当前人物列表');
    if (matches.length > 1) {
      throw StateError(
        '有多位同名好友，请根据城市或关系确认，再使用 partner_id：'
        '${matches.map((p) => '${p.id} ${p.nickname} ${p.typeLabel} ${p.city ?? '城市未设'}').join('；')}',
      );
    }
    return matches.single;
  }
}
