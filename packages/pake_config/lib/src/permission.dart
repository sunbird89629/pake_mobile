/// 系统权限。必须在构建期声明——这是平台约束，不是设计选择。
enum PakePermission {
  camera,
  microphone,
  location;

  static PakePermission? byName(String name) {
    for (final p in PakePermission.values) {
      if (p.name == name) return p;
    }
    return null;
  }

  String get androidPermission => switch (this) {
        PakePermission.camera => 'android.permission.CAMERA',
        PakePermission.microphone => 'android.permission.RECORD_AUDIO',
        PakePermission.location => 'android.permission.ACCESS_FINE_LOCATION',
      };

  String get iosUsageKey => switch (this) {
        PakePermission.camera => 'NSCameraUsageDescription',
        PakePermission.microphone => 'NSMicrophoneUsageDescription',
        PakePermission.location => 'NSLocationWhenInUseUsageDescription',
      };

  String get iosUsageDescription => switch (this) {
        PakePermission.camera => 'This app uses the camera on the loaded page.',
        PakePermission.microphone =>
          'This app uses the microphone on the loaded page.',
        PakePermission.location =>
          'This app uses your location on the loaded page.',
      };
}
