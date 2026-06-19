import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Real AES-256-GCM encryption for file transfer.
class EncryptionService {
  final _aesGcm = AesGcm.with256bits();

  /// Generate a new random 256-bit session key
  Future<Uint8List> generateSessionKey() async {
    final secretKey = await _aesGcm.newSecretKey();
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Generate a device fingerprint from a key/identifier
  String generateFingerprint(String deviceId) {
    // SHA-256 of device ID, take first 12 hex chars formatted as pairs
    final bytes = utf8.encode(deviceId);
    var hash = 0x811c9dc5; // FNV-1a
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

  /// Encrypt data using AES-256-GCM
  Future<EncryptedPayload> encrypt(Uint8List data, Uint8List key) async {
    final secretKey = SecretKey(key);
    final nonce = _generateNonce();

    final secretBox = await _aesGcm.encrypt(
      data,
      secretKey: secretKey,
      nonce: nonce,
    );

    return EncryptedPayload(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce: Uint8List.fromList(nonce),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  /// Decrypt data using AES-256-GCM
  Future<Uint8List> decrypt(EncryptedPayload payload, Uint8List key) async {
    final secretKey = SecretKey(key);

    final secretBox = SecretBox(
      payload.ciphertext,
      nonce: payload.nonce,
      mac: Mac(payload.mac),
    );

    final decrypted = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
  }

  /// Encrypt a chunk of file data (for streaming encryption)
  Future<Uint8List> encryptChunk(Uint8List chunk, Uint8List key) async {
    final payload = await encrypt(chunk, key);
    // Pack as: [4 bytes nonce length][nonce][4 bytes mac length][mac][ciphertext]
    final buffer = BytesBuilder();
    buffer.add(_intToBytes(payload.nonce.length));
    buffer.add(payload.nonce);
    buffer.add(_intToBytes(payload.mac.length));
    buffer.add(payload.mac);
    buffer.add(payload.ciphertext);
    return buffer.toBytes();
  }

  /// Decrypt a packed encrypted chunk
  Future<Uint8List> decryptChunk(Uint8List packed, Uint8List key) async {
    var offset = 0;

    final nonceLen = _bytesToInt(packed.sublist(offset, offset + 4));
    offset += 4;
    final nonce = packed.sublist(offset, offset + nonceLen);
    offset += nonceLen;

    final macLen = _bytesToInt(packed.sublist(offset, offset + 4));
    offset += 4;
    final mac = packed.sublist(offset, offset + macLen);
    offset += macLen;

    final ciphertext = packed.sublist(offset);

    final payload = EncryptedPayload(
      ciphertext: Uint8List.fromList(ciphertext),
      nonce: Uint8List.fromList(nonce),
      mac: Uint8List.fromList(mac),
    );

    return decrypt(payload, key);
  }

  List<int> _generateNonce() {
    final random = Random.secure();
    return List<int>.generate(12, (_) => random.nextInt(256));
  }

  Uint8List _intToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.big);
  }

  int _bytesToInt(List<int> bytes) {
    return Uint8List.fromList(bytes).buffer.asByteData().getInt32(0, Endian.big);
  }
}

class EncryptedPayload {
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List mac;

  EncryptedPayload({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });
}
