import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/online_gallery/quick_tag_cloud_community.dart';
import '../../data/services/online_gallery/quick_tag_cloud_community_service.dart';

final quickTagCloudCommunityServiceProvider =
    Provider.autoDispose<QuickTagCloudCommunityService>((ref) {
      final service = QuickTagCloudCommunityService();
      ref.onDispose(service.dispose);
      return service;
    });

final quickTagCloudCommunityProvider =
    FutureProvider.autoDispose<QuickTagCloudCommunity>((ref) {
      final token = CancelToken();
      ref.onDispose(token.cancel);
      return ref.watch(quickTagCloudCommunityServiceProvider)
          .load(cancelToken: token);
    });
