import 'package:flutter/material.dart';

class BookingStatusChip extends StatelessWidget {
  const BookingStatusChip({
    super.key,
    required this.status,
  });

  final String status;

  static Color _colorForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'preparing':
        return Colors.indigo;
      case 'starting':
        return Colors.cyan;
      case 'on_going':
      case 'ongoing':
        return Colors.teal;
      case 'waiting_for_remaining_payment':
        return Colors.amber[800]!;
      case 'waiting_for_seeker_confirmation':
        return Colors.purple;
      case 'waiting_for_provider_confirmation':
        return Colors.deepPurple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String _labelForStatus(String status) {
    return status
        .toLowerCase()
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty
            ? ''
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForStatus(status);
    final label = _labelForStatus(status);

    return Chip(
      label: Text(
        label,
        style: TextStyle(
          color: color.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      backgroundColor: color.shade50,
      side: BorderSide(color: color.shade200, width: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

extension on Color {
  /// Approximates MaterialColor shade access on arbitrary Colors.
  /// For MaterialColor instances this resolves the actual swatch shade;
  /// for plain Colors it lightens/darkens via HSL.
  Color get shade50 => _adjustLightness(0.96);
  Color get shade200 => _adjustLightness(0.80);
  Color get shade800 => _adjustLightness(0.28);

  Color _adjustLightness(double lightness) {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();
  }
}
