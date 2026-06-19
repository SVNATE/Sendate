import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

/// Local HTTP server that serves an upload page.
/// Any device with a browser can send files to this device.
class BrowserReceiverService {
  HttpServer? _server;
  bool _isRunning = false;
  String? password;

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
      return 'http://localhost:$port';
    } catch (e) {
      _isRunning = false;
      return null;
    }
  }

  /// Stop the server
  Future<void> stop() async {
    _isRunning = false;
    await _server?.close(force: true);
    _server = null;
  }

  void _handleRequest(HttpRequest request) async {
    // CORS headers
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/' && request.method == 'GET') {
      _serveUploadPage(request);
    } else if (path == '/upload' && request.method == 'POST') {
      await _handleUpload(request);
    } else if (path == '/status' && request.method == 'GET') {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ready', 'name': 'Sendate'}));
      await request.response.close();
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found');
      await request.response.close();
    }
  }

  void _serveUploadPage(HttpRequest request) {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_uploadHtml);
    request.response.close();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    try {
      final contentType = request.headers.contentType;
      if (contentType == null || contentType.mimeType != 'multipart/form-data') {
        request.response.statusCode = 400;
        request.response.write('Expected multipart/form-data');
        await request.response.close();
        return;
      }

      final boundary = contentType.parameters['boundary'];
      if (boundary == null) {
        request.response.statusCode = 400;
        request.response.write('No boundary');
        await request.response.close();
        return;
      }

      final savePath = await _getSaveDir();
      final transformer = MimeMultipartTransformer(boundary);
      final parts = await transformer.bind(request).toList();

      final savedFiles = <String>[];

      for (final part in parts) {
        final disposition = part.headers['content-disposition'] ?? '';
        final fileNameMatch = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
        if (fileNameMatch == null) continue;

        final fileName = fileNameMatch.group(1)!;
        final filePath = '$savePath/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(part.data);
        savedFiles.add(fileName);
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
      request.response.statusCode = 500;
      request.response.write('Error: $e');
      await request.response.close();
    }
  }

  Future<String> _getSaveDir() async {
    try {
      final settingsBox = Hive.box(AppConstants.settingsBox);
      final saveLoc = settingsBox.get('save_location', defaultValue: 'Downloads') as String;
      if (saveLoc.startsWith('/') && await Directory(saveLoc).exists()) return saveLoc;
      if (Platform.isAndroid) {
        final dir = Directory('/storage/emulated/0/Download');
        if (await dir.exists()) return dir.path;
      }
    } catch (_) {}
    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  static const _uploadHtml = '''
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
xhr.upload.onprogress=e=>{if(e.lengthComputable)progressBar.style.width=(e.loaded/e.total*100)+'%'};
xhr.onload=()=>{if(xhr.status===200){status.textContent='Files sent successfully!';status.style.display='block';status.style.color='#22c55e';selectedFiles=[];fileList.innerHTML=''}else{status.textContent='Error: '+xhr.responseText;status.style.display='block';status.style.color='#ef4444'}sendBtn.disabled=false};
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
