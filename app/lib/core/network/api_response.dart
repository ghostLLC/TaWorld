/// TaWorld 统一 API 响应解析
///
/// 匹配后端的 `{code: 0, message: "success", data: {...}}` 格式。
library;

/// 统一 API 响应
class ApiResponse<T> {
  const ApiResponse({
    required this.code,
    required this.message,
    this.data,
  });

  final int code;
  final String message;
  final T? data;

  /// 是否成功（code == 0）
  bool get isSuccess => code == 0;

  /// 从 JSON Map 解析
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromData,
  ) {
    return ApiResponse(
      code: json['code'] as int? ?? -1,
      message: json['message'] as String? ?? '未知错误',
      data: json['data'] != null && fromData != null
          ? fromData(json['data'])
          : json['data'] as T?,
    );
  }
}

/// 分页响应
class PaginatedResponse<T> {
  const PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;
}
