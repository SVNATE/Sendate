import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

class SecurityContextData {
  final SecurityContext context;
  final String certificateHash;

  SecurityContextData({
    required this.context,
    required this.certificateHash,
  });
}

/// Provides native TLS Encryption for file transfer using Dart's SecureSocket.
/// This replaces the slow manual cryptography_flutter chunking.
class EncryptionService {
  SecurityContextData? _cachedContext;

  /// Generate a new self-signed X.509 certificate and SecurityContext
  /// This is run in an isolate to avoid blocking the main UI thread during RSA generation.
  Future<SecurityContextData> generateSecurityContext() async {
    if (_cachedContext != null) return _cachedContext!;

    final pemData = await Isolate.run(_generatePems);

    final context = SecurityContext()
      ..usePrivateKeyBytes(utf8.encode(pemData.privateKey))
      ..useCertificateChainBytes(utf8.encode(pemData.certificate));

    _cachedContext = SecurityContextData(
      context: context,
      certificateHash: pemData.hash,
    );

    return _cachedContext!;
  }

  /// Extracts the SHA-256 hash (fingerprint) of the certificate to use as the device ID/auth token
  static String calculateCertificateHash(String certificatePem) {
    final pemContent = certificatePem
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => line.isNotEmpty && !line.startsWith('---'))
        .join();
    final der = base64Decode(pemContent);
    final digest = sha256.convert(der);
    
    // Format as uppercase hex string
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  /// Generate a device fingerprint from a key/identifier (Fallback for discovery compatibility if needed)
  String generateFingerprint(String deviceId) {
    final bytes = utf8.encode(deviceId);
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final hex = hash.toRadixString(16).padLeft(8, '0').toUpperCase();
    final extended = '$hex${(hash >> 4).toRadixString(16).padLeft(4, '0').toUpperCase()}';
    final buffer = StringBuffer();
    for (var i = 0; i < 12 && i < extended.length; i += 2) {
      if (i > 0) buffer.write(':');
      buffer.write(extended.substring(i, i + 2));
    }
    return buffer.toString();
  }
}

class _PemData {
  final String privateKey;
  final String certificate;
  final String hash;

  _PemData(this.privateKey, this.certificate, this.hash);
}

_PemData _generatePems() {
  final keyPair = CryptoUtils.generateRSAKeyPair();
  final privateKey = keyPair.privateKey as RSAPrivateKey;
  final publicKey = keyPair.publicKey as RSAPublicKey;
  final dn = {
    'CN': 'Sendate User',
    'O': 'Sendate',
  };
  final csr = X509Utils.generateRsaCsrPem(dn, privateKey, publicKey);
  final certificate = X509Utils.generateSelfSignedCertificate(privateKey, csr, 365 * 10);
  
  final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey);
  final hash = EncryptionService.calculateCertificateHash(certificate);

  return _PemData(privateKeyPem, certificate, hash);
}
