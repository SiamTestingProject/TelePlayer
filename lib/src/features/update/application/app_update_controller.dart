import 'package:flutter/foundation.dart';

import '../data/app_update_service.dart';
import '../models/app_update.dart';

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  opening,
  downloading,
  downloaded,
  error,
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController(this._service);

  final AppUpdateService _service;

  AppUpdateStatus _status = AppUpdateStatus.idle;
  AppUpdate? _update;
  String? _currentVersion;
  String? _message;
  AppUpdateDownloadProgress? _downloadProgress;
  AppUpdateAsset? _downloadAsset;
  String? _downloadedPath;
  bool _didCheckOnStartup = false;
  Future<AppUpdate?>? _activeCheck;

  AppUpdateStatus get status => _status;
  AppUpdate? get update => _update;
  String? get currentVersion => _currentVersion;
  String? get message => _message;
  AppUpdateDownloadProgress? get downloadProgress => _downloadProgress;
  AppUpdateAsset? get downloadAssetSelection => _downloadAsset;
  String? get downloadedPath => _downloadedPath;
  bool get isBusy =>
      _status == AppUpdateStatus.checking ||
      _status == AppUpdateStatus.opening ||
      _status == AppUpdateStatus.downloading;

  Future<AppUpdate?> checkOnStartup() {
    if (_didCheckOnStartup) {
      return Future<AppUpdate?>.value(_update);
    }
    _didCheckOnStartup = true;
    return check(silent: true);
  }

  Future<AppUpdate?> check({bool silent = false}) {
    final activeCheck = _activeCheck;
    if (activeCheck != null) {
      return activeCheck;
    }
    final check = _runCheck(silent: silent);
    _activeCheck = check;
    return check.whenComplete(() {
      _activeCheck = null;
    });
  }

  Future<AppUpdate?> _runCheck({required bool silent}) async {
    _status = AppUpdateStatus.checking;
    _message = null;
    notifyListeners();
    try {
      final result = await _service.checkForUpdate();
      _currentVersion = result.currentVersion;
      _update = result.update;
      _downloadProgress = null;
      _downloadAsset = null;
      _downloadedPath = null;
      if (result.update == null) {
        _status = AppUpdateStatus.upToDate;
        _message = result.hasPublishedRelease
            ? 'TelePlayer is up to date (v${result.currentVersion}).'
            : 'No public stable GitHub release is available yet.';
      } else {
        _status = AppUpdateStatus.updateAvailable;
        _message = 'TelePlayer v${result.update!.version} is available.';
      }
      return result.update;
    } catch (error) {
      _update = null;
      _message = _errorMessage(error);
      _status = silent ? AppUpdateStatus.idle : AppUpdateStatus.error;
      return null;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> downloadUpdateAsset(AppUpdateAsset asset) async {
    if (_status == AppUpdateStatus.downloading) {
      return false;
    }
    _status = AppUpdateStatus.downloading;
    _message = null;
    _downloadAsset = asset;
    _downloadProgress = AppUpdateDownloadProgress(
      receivedBytes: 0,
      totalBytes: asset.sizeBytes,
      bytesPerSecond: 0,
      isComplete: false,
    );
    _downloadedPath = null;
    notifyListeners();
    try {
      final path = await _service.downloadAsset(
        asset,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );
      _downloadedPath = path;
      _status = AppUpdateStatus.downloaded;
      _message = '${asset.label} update downloaded.';
      return true;
    } catch (error) {
      _status = AppUpdateStatus.error;
      _message = _errorMessage(error);
      return false;
    } finally {
      notifyListeners();
    }
  }

  void clearDownloadedUpdateState() {
    _downloadProgress = null;
    _downloadAsset = null;
    _downloadedPath = null;
    if (_status == AppUpdateStatus.downloaded) {
      _status = _update == null
          ? AppUpdateStatus.idle
          : AppUpdateStatus.updateAvailable;
      _message = _update == null
          ? null
          : 'TelePlayer v${_update!.version} is available.';
    }
    notifyListeners();
  }

  Future<bool> openUpdate(AppUpdate update) async {
    _status = AppUpdateStatus.opening;
    _message = null;
    notifyListeners();
    try {
      await _service.openUpdate(update);
      _status = AppUpdateStatus.updateAvailable;
      _message = update.isDirectDownload
          ? 'The TelePlayer download was opened.'
          : 'The TelePlayer release page was opened.';
      return true;
    } catch (error) {
      _status = AppUpdateStatus.error;
      _message = _errorMessage(error);
      return false;
    } finally {
      notifyListeners();
    }
  }

  String _errorMessage(Object error) {
    if (error is AppUpdateException) {
      return error.message;
    }
    return 'TelePlayer could not complete the update request. Try again.';
  }
}
