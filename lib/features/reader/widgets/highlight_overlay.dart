import 'package:flutter/material.dart';

import '../models/annotation_model.dart';

/// Paints highlight annotations on top of a PDF page.
class HighlightOverlay extends StatelessWidget {
  final List<AnnotationModel> annotations;
  final Size pageSize;
  final bool visible;

  /// Set when the parent viewer applies an inverting color filter (dark PDF
  /// mode): colors are pre-inverted here so they display true after the
  /// outer inversion.
  final bool invertColors;

  final void Function(AnnotationModel)? onAnnotationTap;

  const HighlightOverlay({
    super.key,
    required this.annotations,
    required this.pageSize,
    this.visible = true,
    this.invertColors = false,
    this.onAnnotationTap,
  });

  Color _displayColor(Color color) {
    if (!invertColors) return color;
    final argb = color.toARGB32();
    return Color.fromARGB(
      (argb >> 24) & 0xFF,
      255 - ((argb >> 16) & 0xFF),
      255 - ((argb >> 8) & 0xFF),
      255 - (argb & 0xFF),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!visible || annotations.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / pageSize.width;
        final scaleY = constraints.maxHeight / pageSize.height;

        return Stack(
          children: annotations.map((annotation) {
            if (annotation.type == AnnotationType.highlight &&
                annotation.width != null &&
                annotation.height != null) {
              return Positioned(
                left: annotation.x * scaleX,
                top: annotation.y * scaleY,
                width: annotation.width! * scaleX,
                height: annotation.height! * scaleY,
                child: GestureDetector(
                  onTap: () => onAnnotationTap?.call(annotation),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _displayColor(annotation.color)
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }

            if (annotation.type == AnnotationType.note) {
              return Positioned(
                left: annotation.x * scaleX - 12,
                top: annotation.y * scaleY - 12,
                child: GestureDetector(
                  onTap: () => onAnnotationTap?.call(annotation),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _displayColor(annotation.color),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.note, size: 14, color: Colors.black87),
                  ),
                ),
              );
            }

            return const SizedBox.shrink();
          }).toList(),
        );
      },
    );
  }
}
