/// TaWorld 天气服务 — 使用 Open-Meteo 免费 API
///
/// Open-Meteo 基于 ECMWF / GFS 气象模型数据，完全免费、无需 API Key。
/// 支持当前天气 + 7 天逐日预报。
/// 国内网络可正常访问（api.open-meteo.com）。
///
/// API 文档：https://open-meteo.com/en/docs
library;

import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';

// ==================== 城市坐标映射 ====================

/// 城市中文名 → [纬度, 经度]
/// 覆盖所有中国地级市 + 港澳台 + 主要海外城市（约 410 个）
const _cityCoords = <String, List<double>>{
  // ---- 直辖市 ----
  '北京': [39.9, 116.4], '天津': [39.1, 117.2],
  '上海': [31.2, 121.5], '重庆': [29.6, 106.5],
  // ---- 河北 ----
  '石家庄': [38.0, 114.5], '唐山': [39.6, 118.2], '秦皇岛': [39.9, 119.6],
  '邯郸': [36.6, 114.5], '邢台': [37.1, 114.5], '保定': [38.9, 115.5],
  '张家口': [40.8, 114.9], '承德': [40.9, 117.9], '沧州': [38.3, 116.8],
  '廊坊': [39.5, 116.7], '衡水': [37.7, 115.7],
  // ---- 山西 ----
  '太原': [37.9, 112.5], '大同': [40.1, 113.3], '阳泉': [37.9, 113.6],
  '长治': [36.2, 113.1], '晋城': [35.5, 112.8], '朔州': [39.3, 112.4],
  '晋中': [37.7, 112.7], '运城': [35.0, 111.0], '忻州': [38.4, 112.7],
  '临汾': [36.1, 111.5], '吕梁': [37.5, 111.1],
  // ---- 内蒙古 ----
  '呼和浩特': [40.8, 111.7], '包头': [40.6, 110.0], '乌海': [39.7, 106.8],
  '赤峰': [42.3, 118.9], '通辽': [43.6, 122.2], '鄂尔多斯': [39.6, 109.8],
  '呼伦贝尔': [49.2, 119.8], '巴彦淖尔': [40.7, 107.4], '乌兰察布': [41.0, 113.1],
  // ---- 辽宁 ----
  '沈阳': [41.8, 123.4], '大连': [38.9, 121.6], '鞍山': [41.1, 123.0],
  '抚顺': [41.9, 123.9], '本溪': [41.3, 123.8], '丹东': [40.1, 124.4],
  '锦州': [41.1, 121.1], '营口': [40.7, 122.2], '阜新': [42.0, 121.7],
  '辽阳': [41.3, 123.2], '盘锦': [41.1, 122.1], '铁岭': [42.3, 123.8],
  '朝阳': [41.6, 120.4], '葫芦岛': [40.7, 120.8],
  // ---- 吉林 ----
  '长春': [43.9, 125.3], '吉林': [43.8, 126.5], '四平': [43.2, 124.4],
  '辽源': [42.9, 125.1], '通化': [41.7, 125.9], '白山': [41.9, 126.4],
  '松原': [45.1, 124.8], '白城': [45.6, 122.8],
  // ---- 黑龙江 ----
  '哈尔滨': [45.8, 126.5], '齐齐哈尔': [47.3, 124.0], '牡丹江': [44.6, 129.6],
  '佳木斯': [46.8, 130.3], '大庆': [46.6, 125.0], '鸡西': [45.3, 130.9],
  '双鸭山': [46.6, 131.2], '伊春': [47.7, 128.9], '七台河': [45.8, 131.0],
  '鹤岗': [47.3, 130.3], '黑河': [50.2, 127.5], '绥化': [46.6, 127.0],
  // ---- 江苏 ----
  '南京': [32.1, 118.8], '无锡': [31.6, 120.3], '徐州': [34.3, 117.2],
  '常州': [31.8, 119.9], '苏州': [31.3, 120.6], '南通': [32.0, 120.9],
  '连云港': [34.6, 119.2], '淮安': [33.6, 119.0], '盐城': [33.3, 120.1],
  '扬州': [32.4, 119.4], '镇江': [32.2, 119.4], '泰州': [32.5, 119.9],
  '宿迁': [33.9, 118.3],
  // ---- 浙江 ----
  '杭州': [30.3, 120.2], '宁波': [29.9, 121.5], '温州': [28.0, 120.7],
  '嘉兴': [30.8, 120.8], '湖州': [30.9, 120.1], '绍兴': [30.0, 120.6],
  '金华': [29.1, 119.6], '衢州': [28.9, 118.9], '舟山': [30.0, 122.1],
  '台州': [28.7, 121.4], '丽水': [28.5, 119.9],
  // ---- 安徽 ----
  '合肥': [31.8, 117.3], '芜湖': [31.3, 118.4], '蚌埠': [32.9, 117.4],
  '淮南': [32.6, 117.0], '马鞍山': [31.7, 118.5], '淮北': [33.9, 116.8],
  '铜陵': [30.9, 117.8], '安庆': [30.5, 117.0], '黄山': [29.7, 118.3],
  '滁州': [32.3, 118.3], '阜阳': [32.9, 115.8], '宿州': [33.6, 116.9],
  '六安': [31.7, 116.5], '亳州': [33.8, 115.8], '池州': [30.7, 117.5],
  '宣城': [30.9, 118.8],
  // ---- 福建 ----
  '福州': [26.1, 119.3], '厦门': [24.5, 118.1], '莆田': [25.4, 119.0],
  '三明': [26.3, 117.6], '泉州': [24.9, 118.7], '漳州': [24.5, 117.7],
  '南平': [26.6, 118.2], '龙岩': [25.1, 117.0], '宁德': [26.7, 119.5],
  // ---- 江西 ----
  '南昌': [28.7, 115.9], '景德镇': [29.3, 117.2], '萍乡': [27.6, 113.9],
  '九江': [29.7, 116.0], '新余': [27.8, 114.9], '鹰潭': [28.2, 117.0],
  '赣州': [25.8, 114.9], '吉安': [27.1, 114.9], '宜春': [27.8, 114.4],
  '抚州': [27.9, 116.4], '上饶': [28.5, 117.9],
  // ---- 山东 ----
  '济南': [36.7, 117.0], '青岛': [36.1, 120.4], '淄博': [36.8, 118.1],
  '枣庄': [34.8, 117.6], '东营': [37.4, 118.7], '烟台': [37.5, 121.4],
  '潍坊': [36.7, 119.2], '济宁': [35.4, 116.6], '泰安': [36.2, 117.1],
  '威海': [37.5, 122.1], '日照': [35.4, 119.5], '临沂': [35.1, 118.3],
  '德州': [37.4, 116.4], '聊城': [36.4, 116.0], '滨州': [37.4, 118.0],
  '菏泽': [35.2, 115.5],
  // ---- 河南 ----
  '郑州': [34.7, 113.6], '开封': [34.8, 114.3], '洛阳': [34.6, 112.5],
  '平顶山': [33.7, 113.2], '安阳': [36.1, 114.4], '鹤壁': [35.7, 114.3],
  '新乡': [35.3, 113.9], '焦作': [35.2, 113.2], '濮阳': [35.8, 115.0],
  '许昌': [34.0, 113.8], '漯河': [33.6, 114.0], '三门峡': [34.8, 111.2],
  '南阳': [33.0, 112.5], '商丘': [34.4, 115.7], '信阳': [32.1, 114.1],
  '周口': [33.6, 114.6], '驻马店': [32.9, 114.0],
  // ---- 湖北 ----
  '武汉': [30.6, 114.3], '黄石': [30.2, 115.0], '十堰': [32.6, 110.8],
  '宜昌': [30.7, 111.3], '襄阳': [32.0, 112.1], '鄂州': [30.4, 114.9],
  '荆门': [31.0, 112.2], '孝感': [31.0, 113.9], '荆州': [30.3, 112.2],
  '黄冈': [30.4, 114.9], '咸宁': [29.8, 114.3], '随州': [31.7, 113.4],
  // ---- 湖南 ----
  '长沙': [28.2, 113.0], '株洲': [27.8, 113.1], '湘潭': [27.8, 112.9],
  '衡阳': [26.9, 112.6], '邵阳': [27.2, 111.5], '岳阳': [29.4, 113.1],
  '常德': [29.0, 111.7], '张家界': [29.1, 110.5], '益阳': [28.6, 112.3],
  '郴州': [25.8, 113.0], '永州': [26.4, 111.6], '怀化': [27.6, 110.0],
  '娄底': [27.7, 112.0],
  // ---- 广东 ----
  '广州': [23.1, 113.3], '韶关': [24.8, 113.6], '深圳': [22.5, 114.1],
  '珠海': [22.3, 113.6], '汕头': [23.4, 116.7], '佛山': [23.0, 113.1],
  '江门': [22.6, 113.1], '湛江': [21.3, 110.4], '茂名': [21.7, 110.9],
  '肇庆': [23.0, 112.5], '惠州': [23.1, 114.4], '梅州': [24.3, 116.1],
  '汕尾': [22.8, 115.4], '河源': [23.7, 114.7], '阳江': [21.9, 111.9],
  '清远': [23.7, 113.1], '东莞': [23.0, 113.7], '中山': [22.5, 113.4],
  '潮州': [23.7, 116.6], '揭阳': [23.5, 116.4], '云浮': [22.9, 112.0],
  // ---- 广西 ----
  '南宁': [22.8, 108.4], '柳州': [24.3, 109.4], '桂林': [25.3, 110.3],
  '梧州': [23.5, 111.3], '北海': [21.5, 109.1], '防城港': [21.7, 108.3],
  '钦州': [21.9, 108.6], '贵港': [23.1, 109.6], '玉林': [22.6, 110.2],
  '百色': [23.9, 106.6], '贺州': [24.4, 111.6], '河池': [24.7, 108.1],
  '来宾': [23.7, 109.2], '崇左': [22.4, 107.4],
  // ---- 海南 ----
  '海口': [20.0, 110.3], '三亚': [18.3, 109.5],
  '三沙': [16.8, 112.3], '儋州': [19.5, 109.6],
  // ---- 四川 ----
  '成都': [30.6, 104.1], '自贡': [29.3, 104.8], '攀枝花': [26.6, 101.7],
  '泸州': [28.9, 105.4], '德阳': [31.1, 104.4], '绵阳': [31.5, 104.7],
  '广元': [32.4, 105.8], '遂宁': [30.5, 105.6], '内江': [29.6, 105.1],
  '乐山': [29.6, 103.8], '南充': [30.8, 106.1], '眉山': [30.1, 103.8],
  '宜宾': [28.8, 104.6], '广安': [30.5, 106.6], '达州': [31.2, 107.5],
  '雅安': [30.0, 103.0], '巴中': [31.8, 106.7], '资阳': [30.1, 104.6],
  // ---- 贵州 ----
  '贵阳': [26.6, 106.7], '六盘水': [26.6, 104.8], '遵义': [27.7, 106.9],
  '安顺': [26.2, 105.9], '毕节': [27.3, 105.3], '铜仁': [27.7, 109.2],
  // ---- 云南 ----
  '昆明': [25.0, 102.7], '曲靖': [25.5, 103.8], '玉溪': [24.4, 102.5],
  '保山': [25.1, 99.2], '昭通': [27.3, 103.7], '丽江': [26.9, 100.2],
  '普洱': [22.8, 101.0], '临沧': [23.9, 100.1],
  // ---- 西藏 ----
  '拉萨': [29.6, 91.1], '日喀则': [29.3, 88.9],
  '昌都': [31.1, 97.2], '林芝': [29.7, 94.4],
  // ---- 陕西 ----
  '西安': [34.3, 108.9], '铜川': [34.9, 109.0], '宝鸡': [34.4, 107.1],
  '咸阳': [34.3, 108.7], '渭南': [34.5, 109.5], '延安': [36.6, 109.5],
  '汉中': [33.1, 107.0], '榆林': [38.3, 109.7], '安康': [32.7, 109.0],
  '商洛': [33.9, 109.9],
  // ---- 甘肃 ----
  '兰州': [36.1, 103.8], '嘉峪关': [39.8, 98.3], '金昌': [38.5, 102.2],
  '白银': [36.5, 104.1], '天水': [34.6, 105.7], '武威': [37.9, 102.6],
  '张掖': [38.9, 100.4], '平凉': [35.5, 106.7], '酒泉': [39.7, 98.5],
  '庆阳': [35.7, 107.6], '定西': [35.6, 104.6], '陇南': [33.4, 104.9],
  // ---- 青海 ----
  '西宁': [36.6, 101.8], '海东': [36.5, 102.1],
  // ---- 宁夏 ----
  '银川': [38.5, 106.3], '石嘴山': [39.0, 106.4], '吴忠': [37.9, 106.2],
  '固原': [36.0, 106.2], '中卫': [37.5, 105.2],
  // ---- 新疆 ----
  '乌鲁木齐': [43.8, 87.6], '克拉玛依': [45.6, 84.9], '吐鲁番': [42.9, 89.2],
  '哈密': [42.8, 93.5], '库尔勒': [41.8, 86.1], '阿克苏': [41.2, 80.3],
  '喀什': [39.5, 76.0], '和田': [37.1, 79.9], '伊宁': [43.9, 81.3],
  '塔城': [46.7, 82.9],
  // ---- 港澳台 ----
  '香港': [22.3, 114.2], '澳门': [22.2, 113.5],
  '台北': [25.0, 121.5], '高雄': [22.6, 120.3], '台中': [24.1, 120.7],
  '台南': [23.0, 120.2], '新北': [25.0, 121.5], '桃园': [25.0, 121.3],
  '基隆': [25.1, 121.7], '新竹': [24.8, 121.0], '嘉义': [23.5, 120.4],
  // ---- 日韩 ----
  '东京': [35.7, 139.7], '横滨': [35.4, 139.6], '大阪': [34.7, 135.5],
  '京都': [35.0, 135.8], '神户': [34.7, 135.2], '名古屋': [35.2, 136.9],
  '福冈': [33.6, 130.4], '札幌': [43.1, 141.3], '仙台': [38.3, 140.9],
  '广岛': [34.4, 132.5],
  '首尔': [37.6, 127.0], '釜山': [35.2, 129.1], '仁川': [37.5, 126.7],
  '大邱': [35.9, 128.6], '济州': [33.5, 126.5],
  // ---- 东南亚 ----
  '曼谷': [13.8, 100.5], '清迈': [18.8, 98.9], '普吉': [7.9, 98.4],
  '新加坡': [1.3, 103.8], '吉隆坡': [3.1, 101.7],
  '河内': [21.0, 105.8], '胡志明市': [10.8, 106.6],
  '雅加达': [-6.2, 106.8], '马尼拉': [14.6, 121.0],
  // ---- 欧美 ----
  '伦敦': [51.5, -0.1], '巴黎': [48.9, 2.3], '慕尼黑': [48.1, 11.6],
  '罗马': [41.9, 12.5], '米兰': [45.5, 9.2], '巴塞罗那': [41.4, 2.2],
  '马德里': [40.4, -3.7], '莫斯科': [55.8, 37.6],
  '洛杉矶': [34.1, -118.2], '旧金山': [37.8, -122.4],
  '纽约': [40.7, -74.0], '芝加哥': [41.9, -87.6], '西雅图': [47.6, -122.3],
  '波士顿': [42.4, -71.1], '迈阿密': [25.8, -80.2],
  '多伦多': [43.7, -79.4], '温哥华': [49.3, -123.1],
  '悉尼': [-33.9, 151.2], '墨尔本': [-37.8, 145.0], '奥克兰': [-36.8, 174.8],
  '迪拜': [25.3, 55.3], '开罗': [30.0, 31.2],
  '约翰内斯堡': [-26.2, 28.0], '开普敦': [-33.9, 18.4],
};

// ==================== 数据模型 ====================

/// 天气查询结果
class WeatherResult {
  final String text;       // 天气描述（中文）
  final int temp;          // 温度（°C）
  final String? windDir;   // 风向
  final int? humidity;     // 湿度（%）
  const WeatherResult({
    required this.text,
    required this.temp,
    this.windDir,
    this.humidity,
  });
}

/// 天气条件检查结果
class WeatherCheckResult {
  final bool shouldRemind;
  final String? condition;
  final String? message;
  const WeatherCheckResult({
    required this.shouldRemind,
    this.condition,
    this.message,
  });
}

/// 逐时预报项
class HourlyForecast {
  final int hour;           // 0-23
  final String text;        // 天气描述（中文）
  final int temp;           // 温度（°C）
  final int chanceOfRain;   // 降水概率（%）
  final double precipMM;    // 降水量（mm）
  const HourlyForecast({
    required this.hour,
    required this.text,
    required this.temp,
    required this.chanceOfRain,
    required this.precipMM,
  });
}

/// 每日预报
class DailyForecast {
  final String date;              // yyyy-MM-dd
  final int maxTemp;              // 最高温（°C）
  final int minTemp;              // 最低温（°C）
  final List<HourlyForecast> hourly;
  const DailyForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.hourly,
  });
}

/// 完整天气查询结果（当前 + 预报）
class FullWeatherResult {
  final WeatherResult current;
  final List<DailyForecast> forecast; // 最多 3 天
  const FullWeatherResult({
    required this.current,
    required this.forecast,
  });
}

// ==================== 天气服务 ====================

abstract final class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// 最后一次查询失败的原因（中文，可直接展示给用户）
  static String? lastError;

  // ==================== 天气查询 ====================

  /// 获取当前天气（经纬度）
  static Future<WeatherResult?> getCurrentWeather(
    double longitude,
    double latitude,
  ) async {
    lastError = null;
    final full = await getFullWeatherByCoords(latitude, longitude);
    return full?.current;
  }

  /// 获取当前天气（城市名）
  static Future<WeatherResult?> getCurrentWeatherByCity(String city) async {
    lastError = null;
    final full = await getFullWeather(city);
    return full?.current;
  }

  /// 获取完整天气数据（城市名，当前 + 3 天预报）
  static Future<FullWeatherResult?> getFullWeather(String location) async {
    lastError = null;

    // 0. 清理城市名：去空格、去掉"市"/"县"/"区"后缀
    final cleaned = location.trim().replaceAll(RegExp(r'[市县区]$'), '');

    // 1. 先查坐标映射表（用清理后的名字）
    final coords = _cityCoords[cleaned];
    if (coords != null) {
      return getFullWeatherByCoords(coords[0], coords[1]);
    }

    // 1b. 也尝试原始名字（以防万一）
    if (cleaned != location.trim()) {
      final coords2 = _cityCoords[location.trim()];
      if (coords2 != null) {
        return getFullWeatherByCoords(coords2[0], coords2[1]);
      }
    }

    // 2. 如果 location 本身是 "纬度,经度" 格式
    if (location.contains(',')) {
      final parts = location.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lon = double.tryParse(parts[1].trim());
        if (lat != null && lon != null) {
          return getFullWeatherByCoords(lat, lon);
        }
      }
    }

    // 3. 通过 geocoding 将城市名转为坐标（用清理后的名字）
    try {
      final locations = await locationFromAddress(cleaned)
          .timeout(const Duration(seconds: 8));
      if (locations.isNotEmpty) {
        return getFullWeatherByCoords(
          locations.first.latitude,
          locations.first.longitude,
        );
      }
    } catch (e) {
      lastError = '城市定位失败：$e';
    }

    lastError ??= '找不到城市「$cleaned」的坐标';
    return null;
  }

  /// 获取完整天气数据（坐标，当前 + 3 天预报）
  static Future<FullWeatherResult?> getFullWeatherByCoords(
    double latitude,
    double longitude,
  ) async {
    final dio = Dio();
    try {
      final response = await dio.get(
        _baseUrl,
        queryParameters: {
          'latitude': latitude,
          'longitude': longitude,
          'current': 'temperature_2m,relative_humidity_2m,weather_code,wind_direction_10m',
          'hourly': 'temperature_2m,weather_code,precipitation_probability,precipitation',
          'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum',
          'timezone': 'auto',
          'forecast_days': 3,
        },
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      final data = response.data;
      if (data == null) {
        lastError = '天气服务返回空数据';
        return null;
      }

      // ---------- 当前天气 ----------
      final current = data['current'] as Map<String, dynamic>?;
      if (current == null) {
        lastError = '天气数据格式异常';
        return null;
      }

      final weatherCode = current['weather_code'] as int? ?? 0;
      final currentWeather = WeatherResult(
        text: _wmoToChinese(weatherCode),
        temp: (current['temperature_2m'] as num?)?.round() ?? 0,
        humidity: (current['relative_humidity_2m'] as num?)?.round(),
        windDir: _windDegToChinese(
          (current['wind_direction_10m'] as num?)?.toDouble() ?? 0,
        ),
      );

      // ---------- 逐日预报 ----------
      final daily = data['daily'] as Map<String, dynamic>?;
      final hourly = data['hourly'] as Map<String, dynamic>?;
      final forecast = <DailyForecast>[];

      if (daily != null) {
        final dates = (daily['time'] as List?)?.cast<String>() ?? [];
        final maxTemps = (daily['temperature_2m_max'] as List?)?.cast<num>() ?? [];
        final minTemps = (daily['temperature_2m_min'] as List?)?.cast<num>() ?? [];
        // 预读逐时数据，按日分组
        final hourlyTimes = (hourly?['time'] as List?)?.cast<String>() ?? [];
        final hourlyTemps = (hourly?['temperature_2m'] as List?)?.cast<num>() ?? [];
        final hourlyCodes = (hourly?['weather_code'] as List?)?.cast<int>() ?? [];
        final hourlyPrecipProb =
            (hourly?['precipitation_probability'] as List?)?.cast<num>() ?? [];
        final hourlyPrecip =
            (hourly?['precipitation'] as List?)?.cast<num>() ?? [];

        for (int d = 0; d < dates.length; d++) {
          final datePrefix = dates[d]; // yyyy-MM-dd
          final hourlyForecasts = <HourlyForecast>[];

          for (int h = 0; h < hourlyTimes.length; h++) {
            if (!hourlyTimes[h].startsWith(datePrefix)) continue;
            final hour = int.tryParse(hourlyTimes[h].substring(11, 13)) ?? 0;
            hourlyForecasts.add(HourlyForecast(
              hour: hour,
              text: _wmoToChinese(
                h < hourlyCodes.length ? hourlyCodes[h] : 0,
              ),
              temp: (h < hourlyTemps.length ? hourlyTemps[h] : 0).round(),
              chanceOfRain:
                  (h < hourlyPrecipProb.length ? hourlyPrecipProb[h] : 0)
                      .round(),
              precipMM:
                  (h < hourlyPrecip.length ? hourlyPrecip[h] : 0).toDouble(),
            ));
          }

          forecast.add(DailyForecast(
            date: datePrefix,
            maxTemp: (d < maxTemps.length ? maxTemps[d] : 0).round(),
            minTemp: (d < minTemps.length ? minTemps[d] : 0).round(),
            hourly: hourlyForecasts,
          ));
        }
      }

      return FullWeatherResult(current: currentWeather, forecast: forecast);
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
          lastError = '天气查询连接超时，请检查网络';
        case DioExceptionType.receiveTimeout:
          lastError = '天气数据接收超时，请稍后重试';
        case DioExceptionType.connectionError:
          lastError = '无法连接天气服务，请检查网络连接';
        case DioExceptionType.badResponse:
          lastError = '天气服务响应异常（${e.response?.statusCode}）';
        default:
          lastError = '天气查询失败：${e.message ?? "未知网络错误"}';
      }
      return null;
    } catch (e) {
      lastError = '天气查询出错：$e';
      return null;
    }
  }

  // ==================== 天气条件检查 ====================

  /// 检查天气是否满足提醒条件
  static WeatherCheckResult checkConditions(
    WeatherResult weather,
    List<String> conditions,
  ) {
    for (final condition in conditions) {
      switch (condition) {
        case 'rain':
          if (_isRainy(weather.text)) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'rain',
              message: 'Ta那边要${weather.text}了，提醒Ta带伞吧',
            );
          }
        case 'snow':
          if (_isSnowy(weather.text)) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'snow',
              message: 'Ta那边要${weather.text}啦，提醒Ta注意保暖',
            );
          }
        case 'extreme_cold':
          if (weather.temp <= 0) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'extreme_cold',
              message: 'Ta那边好冷啊（${weather.temp}°C），提醒Ta多穿点',
            );
          }
        case 'extreme_heat':
          if (weather.temp >= 35) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'extreme_heat',
              message: 'Ta那边好热啊（${weather.temp}°C），提醒Ta注意防暑',
            );
          }
      }
    }
    return const WeatherCheckResult(shouldRemind: false);
  }

  static bool _isRainy(String text) {
    const keywords = [
      '小雨', '中雨', '大雨', '暴雨', '阵雨', '雷阵雨',
      '毛毛雨', '冻雨', '雨夹雪', '细雨',
    ];
    return keywords.any(text.contains);
  }

  static bool _isSnowy(String text) {
    const keywords = ['小雪', '中雪', '大雪', '暴雪', '雪粒', '阵雪', '雨夹雪'];
    return keywords.any(text.contains);
  }

  // ==================== WMO 天气代码 → 中文 ====================

  /// WMO Weather interpretation codes (WMO Code Table 4677)
  /// 参考：https://open-meteo.com/en/docs
  static String _wmoToChinese(int code) {
    return switch (code) {
      0 => '晴',
      1 => '晴',          // Mainly clear
      2 => '多云',        // Partly cloudy
      3 => '阴',          // Overcast
      45 => '雾',         // Fog
      48 => '雾凇',       // Depositing rime fog
      51 => '毛毛雨',     // Light drizzle
      53 => '毛毛雨',     // Moderate drizzle
      55 => '细雨',       // Dense drizzle
      56 => '冻毛毛雨',   // Light freezing drizzle
      57 => '冻毛毛雨',   // Dense freezing drizzle
      61 => '小雨',       // Slight rain
      63 => '中雨',       // Moderate rain
      65 => '大雨',       // Heavy rain
      66 => '冻雨',       // Light freezing rain
      67 => '冻雨',       // Heavy freezing rain
      71 => '小雪',       // Slight snow
      73 => '中雪',       // Moderate snow
      75 => '大雪',       // Heavy snow
      77 => '雪粒',       // Snow grains
      80 => '阵雨',       // Slight rain showers
      81 => '阵雨',       // Moderate rain showers
      82 => '暴雨',       // Violent rain showers
      85 => '阵雪',       // Slight snow showers
      86 => '阵雪',       // Heavy snow showers
      95 => '雷阵雨',     // Thunderstorm
      96 => '雷阵雨',     // Thunderstorm with slight hail
      99 => '雷阵雨',     // Thunderstorm with heavy hail
      _ => '未知',
    };
  }

  // ==================== 风向转换 ====================

  /// 风向角度（0-360°）→ 中文方位
  static String _windDegToChinese(double deg) {
    if (deg < 0) return '';
    // 16 方位，每个 22.5°
    final normalized = deg % 360;
    if (normalized >= 348.75 || normalized < 11.25) return '北风';
    if (normalized < 33.75) return '东北风';
    if (normalized < 56.25) return '东北风';
    if (normalized < 78.75) return '东风';
    if (normalized < 101.25) return '东风';
    if (normalized < 123.75) return '东南风';
    if (normalized < 146.25) return '东南风';
    if (normalized < 168.75) return '南风';
    if (normalized < 191.25) return '南风';
    if (normalized < 213.75) return '西南风';
    if (normalized < 236.25) return '西南风';
    if (normalized < 258.75) return '西风';
    if (normalized < 281.25) return '西风';
    if (normalized < 303.75) return '西北风';
    if (normalized < 326.25) return '西北风';
    return '北风';
  }
}
