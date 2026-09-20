import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/online_gallery/quick_tag_cloud_community.dart';
import 'quick_tag_cloud_community_parser.dart';

/// Public GET only. Login, voting and submissions remain on the source site.
class QuickTagCloudCommunityService {
  QuickTagCloudCommunityService({Dio? dio})
    : _ownsDio = dio == null,
      _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  static const endpoint = 'https://novelai.quicktagcloud.com/api/community';
  static const website = 'https://novelai.quicktagcloud.com/strings.html';

  final Dio _dio;
  final bool _ownsDio;

  Future<QuickTagCloudCommunity> load({CancelToken? cancelToken}) async {
    final response = await _dio.get<Object?>(
      endpoint,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.json,
        followRedirects: false,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'Cache-Control': 'no-cache'},
      ),
    );
    final data = response.data;
    return QuickTagCloudCommunityParser.parse(
      data is String ? jsonDecode(data) : data,
    );
  }

  void dispose() {
    if (_ownsDio) _dio.close(force: true);
  }
}
