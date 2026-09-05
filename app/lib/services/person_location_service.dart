import '../data/city_data.dart';
import '../data/city_coordinates.dart';

class PersonLocation {
  const PersonLocation({
    required this.city,
    required this.country,
    required this.province,
    required this.timezoneId,
    this.latitude,
    this.longitude,
  });
  final String city;
  final String country;
  final String province;
  final String timezoneId;
  final double? latitude;
  final double? longitude;
}

/// Resolves only cities in the app's curated picker, without GPS or a network
/// request. Unknown/ambiguous free text remains unresolved, never guessed.
abstract final class PersonLocationService {
  static PersonLocation? resolve(String? label, {String? country}) {
    if (label == null || label.trim().isEmpty) return null;
    final input = label.trim();
    final matches = <(String, String, String)>[];
    for (final nation in kWorldCities.entries) {
      if (country != null && country != nation.key) continue;
      for (final province in nation.value.entries) {
        for (final city in province.value) {
          if (city == input || '$city市' == input) {
            matches.add((nation.key, province.key, city));
          }
        }
      }
    }
    if (matches.length != 1) return null;
    final (nation, province, city) = matches.single;
    final zone = _zone(nation, province, city);
    if (zone == null) return null;
    final coords = kCityCoordinates[city];
    return PersonLocation(
      city: city,
      country: nation,
      province: province,
      timezoneId: zone,
      latitude: coords?[0],
      longitude: coords?[1],
    );
  }

  static String? _zone(String country, String province, String city) {
    if (country == '中国') {
      return switch (province) {
        '香港' => 'Asia/Hong_Kong',
        '澳门' => 'Asia/Macau',
        '台湾' => 'Asia/Taipei',
        _ => 'Asia/Shanghai',
      };
    }
    if (country == '美国') {
      return switch (province) {
        '加利福尼亚' || '华盛顿州' || '内华达' => 'America/Los_Angeles',
        '伊利诺伊' || '德克萨斯' => 'America/Chicago',
        '科罗拉多' => 'America/Denver',
        '夏威夷' => 'Pacific/Honolulu',
        '纽约州' ||
        '佛罗里达' ||
        '马萨诸塞' ||
        '宾夕法尼亚' ||
        '乔治亚' ||
        '华盛顿特区' => 'America/New_York',
        _ => null,
      };
    }
    if (country == '加拿大') {
      return switch (province) {
        '不列颠哥伦比亚' => 'America/Vancouver',
        '阿尔伯塔' => 'America/Edmonton',
        '安大略' || '魁北克' => 'America/Toronto',
        _ => null,
      };
    }
    if (country == '澳大利亚') {
      return switch (province) {
        '西澳' => 'Australia/Perth',
        '南澳' => 'Australia/Adelaide',
        '昆士兰' => 'Australia/Brisbane',
        '维多利亚' => 'Australia/Melbourne',
        '新南威尔士' || '首都领地' => 'Australia/Sydney',
        _ => null,
      };
    }
    if (country == '印度尼西亚') {
      return province == '巴厘' || city == '万鸦老'
          ? 'Asia/Makassar'
          : 'Asia/Jakarta';
    }
    if (country == '俄罗斯') {
      return switch (city) {
        '莫斯科' || '圣彼得堡' => 'Europe/Moscow',
        '海参崴' || '哈巴罗夫斯克' => 'Asia/Vladivostok',
        '新西伯利亚' => 'Asia/Novosibirsk',
        '伊尔库茨克' => 'Asia/Irkutsk',
        '叶卡捷琳堡' => 'Asia/Yekaterinburg',
        _ => null,
      };
    }
    return const {
      '日本': 'Asia/Tokyo',
      '韩国': 'Asia/Seoul',
      '泰国': 'Asia/Bangkok',
      '新加坡': 'Asia/Singapore',
      '马来西亚': 'Asia/Kuala_Lumpur',
      '越南': 'Asia/Ho_Chi_Minh',
      '菲律宾': 'Asia/Manila',
      '英国': 'Europe/London',
      '法国': 'Europe/Paris',
      '德国': 'Europe/Berlin',
      '意大利': 'Europe/Rome',
      '西班牙': 'Europe/Madrid',
      '新西兰': 'Pacific/Auckland',
      '阿联酋': 'Asia/Dubai',
      '南非': 'Africa/Johannesburg',
      '埃及': 'Africa/Cairo',
    }[country];
  }
}
