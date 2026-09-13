import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_parser.dart';

/// Why a subscription could not be added or refreshed.
///
/// A code rather than a message, so the screen can say it in the user's
/// language and the data layer never has to know which one that is.
enum SubscriptionProblem {
  invalidUrl,
  duplicate,
  unreachable,
  badStatus,
  empty,
  nothingSupported,
}

/// A subscription link the user added themselves.
///
/// Lives on this phone only. The link and everything it lists are never sent
/// to Verna's server: a personal subscription is often something paid for or
/// shared privately, and the public pool is no place for it.
class UserSubscription {
  const UserSubscription({
    required this.id,
    required this.name,
    required this.url,
    required this.addedAt,
    this.fetchedAt,
    this.uris = const [],
    this.unsupported = 0,
    this.problem,
  });

  final String id;
  final String name;
  final String url;
  final DateTime addedAt;

  /// When the list was last fetched successfully. A failed refresh leaves this
  /// and [uris] alone, so a subscription that is unreachable for a while keeps
  /// serving what it served before rather than emptying.
  final DateTime? fetchedAt;

  /// The share links it listed at [fetchedAt], kept so the servers are there
  /// offline and immediately on launch.
  final List<String> uris;
  final int unsupported;

  /// The last refresh's failure, or null if it succeeded.
  final SubscriptionProblem? problem;

  /// How long a fetched list is trusted before it is fetched again on launch.
  /// The bot refreshes its own subscriptions on the same six-hour rhythm.
  static const Duration staleAfter = Duration(hours: 6);

  bool get isStale =>
      fetchedAt == null || DateTime.now().difference(fetchedAt!) > staleAfter;

  String get host => Uri.tryParse(url)?.host ?? url;

  /// The name the user gave it, or "" for none -- the screen then numbers it.
  ///
  /// Names used to be filled in from the link: its host, or `owner/repo` for
  /// a GitHub link. Both name the publisher, which the app no longer shows, so
  /// a name this code invented is dropped when it is read back.
  static String storedName(String name, String url) {
    final trimmed = name.trim();
    final parsed = Uri.tryParse(url);
    if (parsed == null) return trimmed;
    final parts = parsed.pathSegments.where((p) => p.isNotEmpty).toList();
    final invented = {
      parsed.host,
      if (parts.length >= 2) '${parts[0]}/${parts[1]}',
    };
    return invented.contains(trimmed) ? '' : trimmed;
  }

  UserSubscription copyWith({
    DateTime? fetchedAt,
    List<String>? uris,
    int? unsupported,
    SubscriptionProblem? problem,
    bool clearProblem = false,
  }) =>
      UserSubscription(
        id: id,
        name: name,
        url: url,
        addedAt: addedAt,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        uris: uris ?? this.uris,
        unsupported: unsupported ?? this.unsupported,
        problem: clearProblem ? null : problem ?? this.problem,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'addedAt': addedAt.toIso8601String(),
        'fetchedAt': fetchedAt?.toIso8601String(),
        'uris': uris,
        'unsupported': unsupported,
        'problem': problem?.name,
      };

  static UserSubscription? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final url = json['url'];
    if (id is! String || url is! String) return null;
    return UserSubscription(
      id: id,
      name: storedName(json['name'] as String? ?? '', url),
      url: url,
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.now(),
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
      uris: [
        for (final u in (json['uris'] as List?) ?? const [])
          if (u is String) u,
      ],
      unsupported: (json['unsupported'] as int?) ?? 0,
      problem: SubscriptionProblem.values
          .where((p) => p.name == json['problem'])
          .firstOrNull,
    );
  }
}

/// Where the subscriptions are kept between launches.
class UserSubscriptionStore {
  const UserSubscriptionStore._();

  static const String _key = 'user_subscriptions_v1';

  static Future<List<UserSubscription>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>)
            if (UserSubscription.fromJson(item) case final UserSubscription sub)
              sub,
      ];
    } catch (_) {
      // A corrupt entry must not take the app's server list down with it.
      return const [];
    }
  }

  static Future<void> write(List<UserSubscription> subscriptions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final sub in subscriptions) sub.toJson()]),
      );
    } catch (_) {
      // Nothing useful to do; the in-memory list still works this session.
    }
  }
}

/// The outcome of one fetch: a parsed list, or the reason there is none.
class SubscriptionFetch {
  const SubscriptionFetch.ok(ParsedSubscription this.parsed) : problem = null;
  const SubscriptionFetch.failed(SubscriptionProblem this.problem)
      : parsed = null;

  final ParsedSubscription? parsed;
  final SubscriptionProblem? problem;
}

class SubscriptionFetcher {
  const SubscriptionFetcher._();

  static Future<SubscriptionFetch> fetch(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      // A browser's User-Agent, because Cloudflare answers a library's default
      // with a 403 that looks exactly like a dead link -- the config bot hit
      // this against its own API.
      headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
      },
    ));
    try {
      final response = await dio.get<String>(url);
      final parsed = SubscriptionParser.parse(response.data ?? '');
      if (parsed.uris.isNotEmpty) return SubscriptionFetch.ok(parsed);
      return SubscriptionFetch.failed(parsed.unsupported > 0
          ? SubscriptionProblem.nothingSupported
          : SubscriptionProblem.empty);
    } on DioException catch (e) {
      return SubscriptionFetch.failed(e.type == DioExceptionType.badResponse
          ? SubscriptionProblem.badStatus
          : SubscriptionProblem.unreachable);
    } catch (_) {
      return const SubscriptionFetch.failed(SubscriptionProblem.unreachable);
    } finally {
      dio.close(force: true);
    }
  }
}
