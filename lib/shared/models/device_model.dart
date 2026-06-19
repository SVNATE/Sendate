enum DeviceType { phone, tablet, laptop, desktop, tv, unknown }

enum TrustLevel { trusted, known, unknown, blocked }

enum ConnectionType { wifi, hotspot, wifiDirect, bluetooth, manual }

class DeviceModel {
  final String id;
  final String name;
  final String? avatar;
  final DeviceType deviceType;
  final String fingerprint;
  final TrustLevel trustLevel;
  final ConnectionType? connectionType;
  final String? ipAddress;
  final int? port;
  final String? osVersion;
  final String? appVersion;
  final double? batteryLevel;
  final bool? isCharging;
  final double? storageAvailable;
  final DateTime? lastSeen;

  const DeviceModel({
    required this.id,
    required this.name,
    this.avatar,
    required this.deviceType,
    required this.fingerprint,
    this.trustLevel = TrustLevel.unknown,
    this.connectionType,
    this.ipAddress,
    this.port,
    this.osVersion,
    this.appVersion,
    this.batteryLevel,
    this.isCharging,
    this.storageAvailable,
    this.lastSeen,
  });

  DeviceModel copyWith({
    String? id,
    String? name,
    String? avatar,
    DeviceType? deviceType,
    String? fingerprint,
    TrustLevel? trustLevel,
    ConnectionType? connectionType,
    String? ipAddress,
    int? port,
    String? osVersion,
    String? appVersion,
    double? batteryLevel,
    bool? isCharging,
    double? storageAvailable,
    DateTime? lastSeen,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      deviceType: deviceType ?? this.deviceType,
      fingerprint: fingerprint ?? this.fingerprint,
      trustLevel: trustLevel ?? this.trustLevel,
      connectionType: connectionType ?? this.connectionType,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      osVersion: osVersion ?? this.osVersion,
      appVersion: appVersion ?? this.appVersion,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      storageAvailable: storageAvailable ?? this.storageAvailable,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
