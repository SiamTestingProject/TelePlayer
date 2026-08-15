class AppSettings {
  const AppSettings({
    required this.apiId,
    required this.apiHash,
    required this.channelIds,
    required this.cacheLimitMb,
    required this.preferWifi,
    this.windowsTdjsonPath,
  });

  factory AppSettings.empty() => const AppSettings(
        apiId: null,
        apiHash: null,
        channelIds: <int>[],
        cacheLimitMb: 4096,
        preferWifi: true,
        windowsTdjsonPath: null,
      );

  final int? apiId;
  final String? apiHash;
  final List<int> channelIds;
  final int cacheLimitMb;
  final bool preferWifi;
  final String? windowsTdjsonPath;

  bool get hasTelegramConfiguration =>
      apiId != null && apiId! > 0 && apiHash != null && apiHash!.trim().isNotEmpty;

  AppSettings copyWith({
    int? apiId,
    String? apiHash,
    List<int>? channelIds,
    int? cacheLimitMb,
    bool? preferWifi,
    String? windowsTdjsonPath,
  }) {
    return AppSettings(
      apiId: apiId ?? this.apiId,
      apiHash: apiHash ?? this.apiHash,
      channelIds: channelIds ?? this.channelIds,
      cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
      preferWifi: preferWifi ?? this.preferWifi,
      windowsTdjsonPath: windowsTdjsonPath ?? this.windowsTdjsonPath,
    );
  }
}
