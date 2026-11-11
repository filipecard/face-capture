import 'package:flutter/services.dart';

int deviceOrientationDegrees(DeviceOrientation o) {
  switch (o) {
    case DeviceOrientation.portraitUp:
      return 0;
    case DeviceOrientation.landscapeLeft:
      return 90;
    case DeviceOrientation.portraitDown:
      return 180;
    case DeviceOrientation.landscapeRight:
      return 270;
  }
}

int frameRotationDegrees({
  required bool isAndroid,
  required bool isFrontCamera,
  required int sensorOrientation,
  required int deviceRotation,
}) {
  if (!isAndroid) return sensorOrientation % 360;
  if (isFrontCamera) {
    return (sensorOrientation + deviceRotation) % 360;
  }
  return (sensorOrientation - deviceRotation + 360) % 360;
}
