import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

/// Local HTTP server that serves an upload page.
/// Any device with a browser on the local network can send files to this device.
class BrowserReceiverService {
  HttpServer? _server;
  bool _isRunning = false;
  String? password;

  /// Track failed auth attempts per IP for rate limiting
  final Map<String, _RateLimit> _rateLimits = {};
  static const _maxFailedAttempts = 5;
  static const _rateLimitWindow = Duration(minutes: 1);

  bool get isRunning => _isRunning;
  int get port => AppConstants.browserReceiverPort;

  /// Start the browser receiver HTTP server
  Future<String?> start({String? password}) async {
    if (_isRunning) return null;
    this.password = password;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      _server!.listen(_handleRequest);
      debugPrint('[BrowserReceiver] Server started on port $port (auth: ${password != null ? "enabled" : "disabled"})');
      return 'http://localhost:$port';
    } catch (e) {
      debugPrint('[BrowserReceiver] Failed to start server: $e');
      _isRunning = false;
      return null;
    }
  }

  /// Stop the server
  Future<void> stop() async {
    _isRunning = false;
    await _server?.close(force: true);
    _server = null;
    _rateLimits.clear();
    debugPrint('[BrowserReceiver] Server stopped');
  }

  /// Check if an IP is rate-limited
  bool _isRateLimited(String ip) {
    final limit = _rateLimits[ip];
    if (limit == null) return false;

    // Reset if window has passed
    if (DateTime.now().difference(limit.firstAttempt) > _rateLimitWindow) {
      _rateLimits.remove(ip);
      return false;
    }

    return limit.attempts >= _maxFailedAttempts;
  }

  /// Record a failed auth attempt
  void _recordFailedAttempt(String ip) {
    final existing = _rateLimits[ip];
    if (existing == null || DateTime.now().difference(existing.firstAttempt) > _rateLimitWindow) {
      _rateLimits[ip] = _RateLimit(firstAttempt: DateTime.now(), attempts: 1);
    } else {
      existing.attempts++;
    }
  }

  /// Validate the auth token from a request
  bool _isAuthenticated(HttpRequest request) {
    if (password == null || password!.isEmpty) return true;

    // Check X-Auth-Token header
    final token = request.headers.value('x-auth-token');
    if (token != null && token == password) return true;

    // Check Authorization: Bearer <token>
    final auth = request.headers.value('authorization');
    if (auth != null && auth.startsWith('Bearer ') && auth.substring(7) == password) return true;

    return false;
  }

  /// Validate file name to prevent path traversal attacks
  String? _sanitizeFileName(String fileName) {
    // Remove path separators and parent directory references
    final sanitized = fileName
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll('..', '_')
        .replaceAll('\x00', '') // null bytes
        .trim();

    // Reject empty or hidden files
    if (sanitized.isEmpty || sanitized.startsWith('.')) return null;

    // Limit file name length
    if (sanitized.length > 255) return sanitized.substring(0, 255);

    return sanitized;
  }

  void _handleRequest(HttpRequest request) async {
    final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    // Security headers
    request.response.headers.add('X-Frame-Options', 'DENY');
    request.response.headers.add('X-Content-Type-Options', 'nosniff');
    request.response.headers.add('Referrer-Policy', 'no-referrer');

    // CORS — restrict to same-origin (local network)
    final origin = request.headers.value('origin');
    if (origin != null) {
      // Only allow origins from private IP ranges
      final originUri = Uri.tryParse(origin);
      if (originUri != null && _isLocalOrigin(originUri.host)) {
        request.response.headers.add('Access-Control-Allow-Origin', origin);
      }
    }
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, X-Auth-Token, Authorization');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    // Rate limiting check
    if (_isRateLimited(clientIp)) {
      request.response.statusCode = 429;
      request.response.write('Too many failed attempts. Try again later.');
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/' && request.method == 'GET') {
      _serveUploadPage(request);
    } else if (path == '/upload' && request.method == 'POST') {
      await _handleUpload(request, clientIp);
    } else if (path == '/status' && request.method == 'GET') {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ready',
          'name': 'Sendate',
          'authRequired': password != null && password!.isNotEmpty,
        }));
      await request.response.close();
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found');
      await request.response.close();
    }
  }

  /// Check if a hostname is a local/private IP
  bool _isLocalOrigin(String host) {
    if (host == 'localhost' || host == '127.0.0.1') return true;
    // Private IPv4 ranges
    if (host.startsWith('192.168.') || host.startsWith('10.') || host.startsWith('172.')) return true;
    // Link-local
    if (host.startsWith('169.254.')) return true;
    return false;
  }

  void _serveUploadPage(HttpRequest request) {
    final hasPassword = password != null && password!.isNotEmpty;
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_getUploadHtml(hasPassword));
    request.response.close();
  }

  Future<void> _handleUpload(HttpRequest request, String clientIp) async {
    // Authentication check
    if (!_isAuthenticated(request)) {
      _recordFailedAttempt(clientIp);
      debugPrint('[BrowserReceiver] Unauthorized upload attempt from $clientIp');
      request.response.statusCode = 401;
      request.response.headers.add('WWW-Authenticate', 'Bearer');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': false,
        'error': 'Unauthorized. Invalid or missing authentication.',
      }));
      await request.response.close();
      return;
    }

    try {
      final contentType = request.headers.contentType;
      if (contentType == null || contentType.mimeType != 'multipart/form-data') {
        request.response.statusCode = 400;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': false, 'error': 'Expected multipart/form-data'}));
        await request.response.close();
        return;
      }

      final boundary = contentType.parameters['boundary'];
      if (boundary == null) {
        request.response.statusCode = 400;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': false, 'error': 'No boundary'}));
        await request.response.close();
        return;
      }

      // Body size limit: 500MB to prevent OOM on large uploads
      const maxBodyBytes = 500 * 1024 * 1024;
      final bodyBytes = <int>[];
      await for (final chunk in request) {
        bodyBytes.addAll(chunk);
        if (bodyBytes.length > maxBodyBytes) {
          request.response.statusCode = 413;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'success': false, 'error': 'Upload too large (max 500MB)'}));
          await request.response.close();
          return;
        }
      }

      final savePath = await _getSaveDir();
      final transformer = MimeMultipartTransformer(boundary);

      // Feed buffered bytes as a single-element stream
      final parts = await transformer.bind(Stream.value(bodyBytes)).toList();

      final savedFiles = <String>[];

      for (final part in parts) {
        final disposition = part.headers['content-disposition'] ?? '';
        final fileNameMatch = RegExp(r'filename="([^"]*)"').firstMatch(disposition);
        if (fileNameMatch == null) continue;

        final rawFileName = fileNameMatch.group(1)!;
        if (rawFileName.isEmpty) continue;

        final fileName = _sanitizeFileName(rawFileName);
        if (fileName == null) {
          debugPrint('[BrowserReceiver] Rejected unsafe filename: $rawFileName');
          continue;
        }

        if (part.data.isEmpty) {
          debugPrint('[BrowserReceiver] Skipped empty file: $fileName');
          continue;
        }

        // Resolve collision: append (1), (2) ... if file already exists
        final resolvedPath = _resolveFilePath(savePath, fileName);
        final file = File(resolvedPath);
        await file.writeAsBytes(part.data);
        final savedName = resolvedPath.split('/').last;
        savedFiles.add(savedName);
        debugPrint('[BrowserReceiver] Saved file: $resolvedPath (${part.data.length} bytes)');
      }

      debugPrint('[BrowserReceiver] Received ${savedFiles.length} file(s) from $clientIp');

      if (savedFiles.isNotEmpty) {
        // Save to transfer history
        await _saveToHistory(savedFiles, clientIp);
        // Show system notification
        _showNotification(savedFiles);
      }

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'files': savedFiles,
          'message': '${savedFiles.length} file(s) received',
        }));
      await request.response.close();
    } catch (e) {
      debugPrint('[BrowserReceiver] Upload error from $clientIp: $e');
      try {
        request.response.statusCode = 500;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': false, 'error': 'Server error'}));
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Resolve a collision-free file path by appending (1), (2) etc.
  String _resolveFilePath(String dir, String fileName) {
    var candidate = '$dir/$fileName';
    if (!File(candidate).existsSync()) return candidate;

    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext  = dot > 0 ? fileName.substring(dot) : '';
    var counter = 1;
    while (File(candidate).existsSync()) {
      candidate = '$dir/$base ($counter)$ext';
      counter++;
    }
    return candidate;
  }

  Future<void> _saveToHistory(List<String> fileNames, String senderIp) async {
    try {
      final box = Hive.box(AppConstants.historyBox);
      final ts = DateTime.now();
      for (final name in fileNames) {
        box.put('browser_${ts.millisecondsSinceEpoch}_$name', {
          'id': 'browser_${ts.millisecondsSinceEpoch}',
          'type': 'receive',
          'fileName': name,
          'deviceName': 'Browser ($senderIp)',
          'direction': 'receive',
          'status': 'completed',
          'timestamp': ts.toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('[BrowserReceiver] Failed to save history: $e');
    }
  }

  void _showNotification(List<String> fileNames) {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final title = fileNames.length == 1
          ? 'File received: ${fileNames.first}'
          : '${fileNames.length} files received via Browser';
      const androidDetails = AndroidNotificationDetails(
        'browser_receiver',
        'Browser Receiver',
        channelDescription: 'Notifications for files received via the browser upload page',
        importance: Importance.high,
        priority: Priority.high,
      );
      const darwinDetails = DarwinNotificationDetails();
      plugin.show(
        DateTime.now().millisecondsSinceEpoch & 0xFFFF,
        'Sendate',
        title,
        const NotificationDetails(android: androidDetails, macOS: darwinDetails),
      );
    } catch (e) {
      debugPrint('[BrowserReceiver] Notification error: $e');
    }
  }

  Future<String> _getSaveDir() async {
    try {
      // 1. Check user-configured save location first
      final settingsBox = Hive.box(AppConstants.settingsBox);
      final saveLoc = settingsBox.get('save_location', defaultValue: '') as String;
      if (saveLoc.isNotEmpty && saveLoc.startsWith('/')) {
        final d = Directory(saveLoc);
        if (await d.exists()) return d.path;
      }
    } catch (e) {
      debugPrint('[BrowserReceiver] Error reading save_location setting: $e');
    }

    // 2. Platform default Downloads folder
    try {
      if (Platform.isAndroid) {
        // Primary external storage Downloads
        for (final p in [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Downloads',
        ]) {
          final d = Directory(p);
          if (await d.exists()) return d.path;
        }
      } else if (Platform.isMacOS || Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          final d = Directory('$home/Downloads');
          if (await d.exists()) return d.path;
          // Create it if missing
          await d.create(recursive: true);
          return d.path;
        }
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          final d = Directory('$userProfile\\Downloads');
          if (await d.exists()) return d.path;
          await d.create(recursive: true);
          return d.path;
        }
      }
    } catch (e) {
      debugPrint('[BrowserReceiver] Error resolving Downloads dir: $e');
    }

    // 3. Last resort: app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    final sendate = Directory('${appDir.path}/Sendate/Downloads');
    await sendate.create(recursive: true);
    debugPrint('[BrowserReceiver] Using fallback save dir: ${sendate.path}');
    return sendate.path;
  }

  String _getUploadHtml(bool authRequired) => '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Sendate - File Transfer</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0f0f23;color:#e2e8f0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.container{max-width:480px;width:100%;background:#1a1b3e;border-radius:24px;padding:40px;border:1px solid #2d2e5e}
h1{font-size:24px;font-weight:700;margin-bottom:8px;color:#fff}
.subtitle{color:#94a3b8;font-size:14px;margin-bottom:32px}
.drop-zone{border:2px dashed #4f46e5;border-radius:16px;padding:48px 24px;text-align:center;cursor:pointer;transition:all .2s;margin-bottom:24px}
.drop-zone:hover,.drop-zone.active{border-color:#818cf8;background:rgba(99,102,241,.08)}
.drop-zone svg{width:48px;height:48px;margin-bottom:16px;color:#6366f1}
.drop-zone p{color:#94a3b8;font-size:14px}
input[type=file]{display:none}
.password-field{width:100%;padding:12px 16px;border:1px solid #2d2e5e;border-radius:12px;font-size:14px;background:#0f0f23;color:#e2e8f0;margin-bottom:16px;outline:none}
.password-field:focus{border-color:#6366f1}
.btn{display:block;width:100%;padding:14px;border:none;border-radius:12px;font-size:16px;font-weight:600;cursor:pointer;background:#6366f1;color:#fff;transition:all .2s}
.btn:hover{background:#4f46e5}
.btn:disabled{opacity:.5;cursor:not-allowed}
.status{margin-top:16px;text-align:center;font-size:14px;color:#22c55e;display:none}
.file-list{margin-bottom:16px;font-size:13px;color:#cbd5e1}
.file-item{padding:8px 12px;background:#2d2e5e;border-radius:8px;margin-bottom:6px}
.progress{height:4px;background:#2d2e5e;border-radius:2px;margin-top:16px;overflow:hidden;display:none}
.progress-bar{height:100%;background:#6366f1;border-radius:2px;width:0%;transition:width .3s}
</style>
</head>
<body>
<div class="container">
<h1>Sendate</h1>
<p class="subtitle">Drop files here to send to this device</p>
${authRequired ? '<input type="password" class="password-field" id="passwordField" placeholder="Enter password to upload">' : ''}
<div class="drop-zone" id="dropZone" onclick="fileInput.click()">
<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5"/></svg>
<p>Click or drag files here</p>
</div>
<input type="file" id="fileInput" multiple>
<div class="file-list" id="fileList"></div>
<button class="btn" id="sendBtn" disabled onclick="uploadFiles()">Send Files</button>
<div class="progress" id="progress"><div class="progress-bar" id="progressBar"></div></div>
<div class="status" id="status"></div>
</div>
<script>
const dropZone=document.getElementById('dropZone'),fileInput=document.getElementById('fileInput'),fileList=document.getElementById('fileList'),sendBtn=document.getElementById('sendBtn'),status=document.getElementById('status'),progress=document.getElementById('progress'),progressBar=document.getElementById('progressBar');
const passwordField=document.getElementById('passwordField');
let selectedFiles=[];
dropZone.addEventListener('dragover',e=>{e.preventDefault();dropZone.classList.add('active')});
dropZone.addEventListener('dragleave',()=>dropZone.classList.remove('active'));
dropZone.addEventListener('drop',e=>{e.preventDefault();dropZone.classList.remove('active');handleFiles(e.dataTransfer.files)});
fileInput.addEventListener('change',e=>handleFiles(e.target.files));
function handleFiles(files){selectedFiles=[...files];fileList.innerHTML=selectedFiles.map(f=>'<div class="file-item">'+f.name+' ('+formatSize(f.size)+')</div>').join('');sendBtn.disabled=selectedFiles.length===0}
function formatSize(b){if(b<1024)return b+' B';if(b<1048576)return(b/1024).toFixed(1)+' KB';return(b/1048576).toFixed(1)+' MB'}
async function uploadFiles(){if(!selectedFiles.length)return;sendBtn.disabled=true;progress.style.display='block';
const fd=new FormData();selectedFiles.forEach(f=>fd.append('files',f,f.name));
try{const xhr=new XMLHttpRequest();xhr.open('POST','/upload');
if(passwordField){xhr.setRequestHeader('X-Auth-Token',passwordField.value)}
xhr.upload.onprogress=e=>{if(e.lengthComputable)progressBar.style.width=(e.loaded/e.total*100)+'%'};
xhr.onload=()=>{if(xhr.status===200){status.textContent='Files sent successfully!';status.style.display='block';status.style.color='#22c55e';selectedFiles=[];fileList.innerHTML=''}else if(xhr.status===401){status.textContent='Authentication failed. Check password.';status.style.display='block';status.style.color='#ef4444'}else if(xhr.status===429){status.textContent='Too many failed attempts. Wait and try again.';status.style.display='block';status.style.color='#ef4444'}else{status.textContent='Error: '+xhr.responseText;status.style.display='block';status.style.color='#ef4444'}sendBtn.disabled=false};
xhr.onerror=()=>{status.textContent='Network error';status.style.display='block';status.style.color='#ef4444';sendBtn.disabled=false};
xhr.send(fd)}catch(e){status.textContent='Error: '+e;status.style.display='block';status.style.color='#ef4444';sendBtn.disabled=false}}
</script>
</body>
</html>
''';

  Future<void> dispose() async => await stop();
}

/// Minimal multipart parser
class MimeMultipartTransformer {
  final String boundary;
  MimeMultipartTransformer(this.boundary);

  Stream<MimeMultipart> bind(Stream<List<int>> stream) async* {
    final bytes = <int>[];
    await for (final chunk in stream) { bytes.addAll(chunk); }

    final boundaryBytes = utf8.encode('--$boundary');
    var i = _indexOf(bytes, boundaryBytes, 0);
    if (i < 0) return;

    while (true) {
      i += boundaryBytes.length;
      if (i + 2 <= bytes.length && bytes[i] == 45 && bytes[i + 1] == 45) break;
      if (i < bytes.length && bytes[i] == 13) i++;
      if (i < bytes.length && bytes[i] == 10) i++;

      final headersEnd = _indexOf(bytes, utf8.encode('\r\n\r\n'), i);
      if (headersEnd < 0) break;

      final headersStr = utf8.decode(bytes.sublist(i, headersEnd));
      final headers = <String, String>{};
      for (final line in headersStr.split('\r\n')) {
        final colon = line.indexOf(':');
        if (colon > 0) {
          headers[line.substring(0, colon).trim().toLowerCase()] =
              line.substring(colon + 1).trim();
        }
      }

      final dataStart = headersEnd + 4;
      final nextBoundary = _indexOf(bytes, boundaryBytes, dataStart);
      if (nextBoundary < 0) break;

      var dataEnd = nextBoundary - 2;
      if (dataEnd < dataStart) dataEnd = dataStart;

      final data = bytes.sublist(dataStart, dataEnd);
      yield MimeMultipart(headers, data);
      i = nextBoundary;
    }
  }

  int _indexOf(List<int> haystack, List<int> needle, int start) {
    for (var i = start; i <= haystack.length - needle.length; i++) {
      var found = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) { found = false; break; }
      }
      if (found) return i;
    }
    return -1;
  }
}

class MimeMultipart {
  final Map<String, String> headers;
  final List<int> data;
  MimeMultipart(this.headers, this.data);
}

class _RateLimit {
  final DateTime firstAttempt;
  int attempts;
  _RateLimit({required this.firstAttempt, required this.attempts});
}
