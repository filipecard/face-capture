import 'dart:ui';

import '../core/face_observation.dart';
import '../diagnostics/detection_thresholds.dart';

enum PoseTarget { frontal, right, left, up, down }

enum PositionIssue {
  noFace,
  multipleFaces,
  tooDark,
  tooBright,
  tooFar,
  tooClose,
  moveLeft,
  moveRight,
  moveUp,
  moveDown,
  headTilted,
  notLookingAtCamera,
  missingAngles,
  turnRight,
  turnLeft,
  turnedTooFar,
  lookUp,
  lookDown,
}

enum PositionStatus { noFace, adjusting, ok }

class ValidationResult {
  const ValidationResult({
    required this.status,
    required this.issues,
    this.face,
    this.faceWidthRatio,
    this.centerOffset,
    this.oval,
  });

  final PositionStatus status;

  final List<PositionIssue> issues;

  final FaceObservation? face;

  final double? faceWidthRatio;

  final Offset? centerOffset;

  final Rect? oval;

  bool get isOk => status == PositionStatus.ok;
  bool get isCentered =>
      face != null &&
      !issues.any(
        (i) =>
            i == PositionIssue.moveLeft ||
            i == PositionIssue.moveRight ||
            i == PositionIssue.moveUp ||
            i == PositionIssue.moveDown,
      );

  String get message =>
      issues.isEmpty ? 'Mantenha essa posição.' : messageFor(issues.first);
}

String messageFor(PositionIssue issue) {
  switch (issue) {
    case PositionIssue.noFace:
      return 'Posicione seu rosto dentro da moldura.';
    case PositionIssue.multipleFaces:
      return 'Apenas uma pessoa deve aparecer na imagem.';
    case PositionIssue.tooDark:
      return 'Ambiente muito escuro. Procure mais iluminação.';
    case PositionIssue.tooBright:
      return 'Imagem muito clara. Evite luz forte direta.';
    case PositionIssue.tooFar:
      return 'Aproxime um pouco o celular.';
    case PositionIssue.tooClose:
      return 'Afaste um pouco o celular.';
    case PositionIssue.moveLeft:
      return 'Mova o rosto para a esquerda.';
    case PositionIssue.moveRight:
      return 'Mova o rosto para a direita.';
    case PositionIssue.moveUp:
    case PositionIssue.moveDown:
      return 'Posicione seu rosto dentro da moldura.';
    case PositionIssue.headTilted:
      return 'Mantenha a cabeça reta.';
    case PositionIssue.notLookingAtCamera:
      return 'Olhe diretamente para a câmera.';
    case PositionIssue.missingAngles:
      return 'Não foi possível medir a posição da cabeça.';
    case PositionIssue.turnRight:
      return 'Vire lentamente a cabeça para a direita.';
    case PositionIssue.turnLeft:
      return 'Vire lentamente a cabeça para a esquerda.';
    case PositionIssue.turnedTooFar:
      return 'Volte um pouco a cabeça.';
    case PositionIssue.lookUp:
      return 'Levante levemente o queixo.';
    case PositionIssue.lookDown:
      return 'Abaixe levemente o queixo.';
  }
}

class FacePositionValidator {
  const FacePositionValidator();

  static Rect ovalFor(Size imageSize, DetectionThresholds t) {
    final w = imageSize.width * t.ovalWidthFraction;
    final h = w * t.ovalAspect;
    return Rect.fromCenter(
      center: Offset(
        imageSize.width * t.ovalCenterX,
        imageSize.height * t.ovalCenterY,
      ),
      width: w,
      height: h,
    );
  }

  static double faceWidthRatio(Rect box, Size imageSize) =>
      imageSize.width <= 0 ? 0 : box.width / imageSize.width;

  static Offset centerOffset(Rect box, Size imageSize, DetectionThresholds t) {
    final c = box.center;
    return Offset(
      c.dx / imageSize.width - t.ovalCenterX,
      c.dy / imageSize.height - t.ovalCenterY,
    );
  }

  ValidationResult validate(
    FrameAnalysis frame,
    DetectionThresholds t, {
    PoseTarget target = PoseTarget.frontal,
  }) {
    final oval = ovalFor(frame.imageSize, t);

    if (frame.faces.isEmpty) {
      return ValidationResult(
        status: PositionStatus.noFace,
        issues: const [PositionIssue.noFace],
        oval: oval,
      );
    }
    if (frame.faces.length > 1) {
      return ValidationResult(
        status: PositionStatus.adjusting,
        issues: const [PositionIssue.multipleFaces],
        oval: oval,
      );
    }

    final face = frame.faces.single;
    final issues = <PositionIssue>[];

    final luma = frame.meanLuma;
    if (luma != null) {
      if (luma < t.minLuma) issues.add(PositionIssue.tooDark);
      if (luma > t.maxLuma) issues.add(PositionIssue.tooBright);
    }

    final ratio = faceWidthRatio(face.box, frame.imageSize);

    final minRatio = target == PoseTarget.frontal
        ? t.minFaceWidthRatio
        : t.minFaceWidthRatio * 0.8;
    if (ratio < minRatio) issues.add(PositionIssue.tooFar);
    if (ratio > t.maxFaceWidthRatio) issues.add(PositionIssue.tooClose);

    final off = centerOffset(face.box, frame.imageSize, t);

    if (off.dx > t.centerToleranceX) issues.add(PositionIssue.moveLeft);
    if (off.dx < -t.centerToleranceX) issues.add(PositionIssue.moveRight);
    if (off.dy > t.centerToleranceY) issues.add(PositionIssue.moveUp);
    if (off.dy < -t.centerToleranceY) issues.add(PositionIssue.moveDown);

    final x = face.eulerX, y = face.eulerY, z = face.eulerZ;
    if (x == null || y == null || z == null) {
      issues.add(PositionIssue.missingAngles);
    } else {
      if (z.abs() > t.frontalMaxZ) issues.add(PositionIssue.headTilted);
      issues.addAll(_poseIssues(target, x, y, t));
    }

    return ValidationResult(
      status: issues.isEmpty ? PositionStatus.ok : PositionStatus.adjusting,
      issues: issues,
      face: face,
      faceWidthRatio: ratio,
      centerOffset: off,
      oval: oval,
    );
  }

  List<PositionIssue> _poseIssues(
    PoseTarget target,
    double x,
    double y,
    DetectionThresholds t,
  ) {
    final userRightYaw = y * t.yawSignForUserRight;
    final upPitch = x * t.pitchSignForUp;

    switch (target) {
      case PoseTarget.frontal:
        if (x.abs() > t.frontalMaxX || y.abs() > t.frontalMaxY) {
          return const [PositionIssue.notLookingAtCamera];
        }
        return const [];
      case PoseTarget.right:
      case PoseTarget.left:
        final signed = target == PoseTarget.right
            ? userRightYaw
            : -userRightYaw;
        final issues = <PositionIssue>[];
        if (signed < t.sideMinY) {
          issues.add(
            target == PoseTarget.right
                ? PositionIssue.turnRight
                : PositionIssue.turnLeft,
          );
        } else if (signed > t.sideMaxY) {
          issues.add(PositionIssue.turnedTooFar);
        }
        if (x.abs() > t.frontalMaxX) {
          issues.add(PositionIssue.notLookingAtCamera);
        }
        return issues;
      case PoseTarget.up:
      case PoseTarget.down:
        final signed = target == PoseTarget.up ? upPitch : -upPitch;
        final issues = <PositionIssue>[];
        if (signed < t.pitchMin) {
          issues.add(
            target == PoseTarget.up
                ? PositionIssue.lookUp
                : PositionIssue.lookDown,
          );
        } else if (signed > t.pitchMax) {
          issues.add(PositionIssue.turnedTooFar);
        }
        if (y.abs() > t.frontalMaxY) {
          issues.add(PositionIssue.notLookingAtCamera);
        }
        return issues;
    }
  }
}
