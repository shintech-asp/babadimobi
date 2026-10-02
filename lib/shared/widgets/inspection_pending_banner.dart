import 'package:flutter/material.dart';

/// Shown while an inspection-required booking is still waiting for the
/// technician's on-site visit (status 'accepted', inspection_agreed_at not
/// yet set) — mirrors seeker/my-requests.php's "Waiting for on-site
/// inspection" strip, so neither side is left wondering why there's no
/// payment prompt / verification code yet. Shared by the seeker's and the
/// provider's own booking-detail screens.
class InspectionPendingBanner extends StatelessWidget {
  const InspectionPendingBanner({
    super.key,
    required this.inspectionDate,
    this.forProvider = false,
  });

  final String inspectionDate;
  // Slightly different copy depending on who's reading it — the seeker is
  // told what will happen to them; the provider/technician is reminded what
  // they still owe (a report) before the booking can move on.
  final bool forProvider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFEFF6FF), Color(0xFFF8FBFF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.search_rounded, color: Color(0xFF1D4ED8), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Waiting for on-site inspection',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  forProvider
                      ? 'Visit the client on $inspectionDate, then submit an '
                          'inspection report with a final price before this booking '
                          'can move to Preparing.'
                      : 'A technician will visit on $inspectionDate to inspect and '
                          'set the final price. No payment or verification code yet '
                          '— those unlock once you agree to the inspection report.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E40AF), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
