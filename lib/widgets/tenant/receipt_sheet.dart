import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/bill_model.dart';
import '../../utils/constants.dart';

/// A real-paper style payment receipt.
///
/// The receipt "prints" out of the top of the screen (height + slide animation),
/// has torn zig-zag edges, dashed separators and a stamp showing the status.
/// Open it with [ReceiptSheet.show].
class ReceiptSheet {
  static Future<void> show(
    BuildContext context, {
    required PaymentRecord payment,
    required Future<void> Function() onDownload,
    bool Function()? isDownloading,
    String? tenantName,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Receipt',
      barrierColor: Colors.black.withOpacity(0.78),
      transitionDuration: const Duration(milliseconds: 750),
      pageBuilder: (ctx, a, b) => _ReceiptPage(
        payment: payment,
        onDownload: onDownload,
        tenantName: tenantName,
      ),
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: const Interval(0, 0.35)),
          child: AnimatedBuilder(
            animation: curved,
            // The paper is "printed" downward: it reveals from the top while sliding into place.
            builder: (_, __) => ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 0.15 + 0.85 * curved.value,
                child: Transform.translate(
                  offset: Offset(0, -40 * (1 - curved.value)),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReceiptPage extends StatefulWidget {
  final PaymentRecord payment;
  final Future<void> Function() onDownload;
  final String? tenantName;

  const _ReceiptPage({required this.payment, required this.onDownload, this.tenantName});

  @override
  State<_ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<_ReceiptPage> with SingleTickerProviderStateMixin {
  late final AnimationController _stamp;
  bool _downloading = false;

  static const Color _paper = Color(0xFFFBF9F4);
  static const Color _ink = Color(0xFF1B1B1B);
  static const Color _muted = Color(0xFF7A7A72);

  @override
  void initState() {
    super.initState();
    _stamp = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        _stamp.forward();
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void dispose() {
    _stamp.dispose();
    super.dispose();
  }

  PaymentRecord get p => widget.payment;

  bool get _isPaid => const ['verified', 'success', 'paid'].contains(p.status.toLowerCase());
  bool get _isRejected => p.status.toLowerCase() == 'rejected';

  String get _statusLabel {
    if (_isPaid) return 'PAID';
    if (_isRejected) return 'REJECTED';
    return 'PENDING';
  }

  Color get _statusColor => _isPaid ? const Color(0xFF3F8F2B) : (_isRejected ? const Color(0xFFC62828) : const Color(0xFFE08A00));

  String get _method {
    switch ((p.type ?? p.paymentMethod).toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'proof':
        return 'UPI / Bank transfer';
      case 'online':
        return 'Online payment';
      default:
        final m = p.paymentMethod.trim();
        return m.isEmpty ? 'Payment' : '${m[0].toUpperCase()}${m.substring(1)}';
    }
  }

  String get _receiptNo {
    final d = p.createdAt;
    return 'LK-${d.year}${d.month.toString().padLeft(2, '0')}-${p.id}';
  }

  /// "Today, 3:42 PM" / "Yesterday, 9:05 AM" / "15 Nov 2026, 3:42 PM"
  String get _friendlyWhen {
    final d = p.createdAt.toLocal();
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final time = DateFormat('h:mm a').format(d);
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    return '${DateFormat('d MMM yyyy').format(d)}, $time';
  }

  String _money(double v) => '₹${NumberFormat('#,##,##0.00', 'en_IN').format(v < 0 ? 0 : v)}';

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownload();
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 380, maxHeight: maxH * 0.94),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 14))],
                      ),
                      child: ClipPath(
                        clipper: _TornEdgeClipper(),
                        child: Container(
                          color: _paper,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
                            child: _paperContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withOpacity(0.25)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      if (_isPaid) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _downloading ? null : _download,
                            icon: _downloading
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : const Icon(Icons.download_rounded, color: Colors.black, size: 20),
                            label: Text(_downloading ? 'Preparing…' : 'Download PDF',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kLivinkeyGreen,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paperContent() {
    final mono = const TextStyle(fontFamily: 'monospace', color: _ink, fontSize: 13, height: 1.35);
    return DefaultTextStyle(
      style: mono,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Image.asset('assets/images/receipt_logo.jpg', height: 46, fit: BoxFit.contain)),
          const SizedBox(height: 10),
          const Center(
            child: Text('PAYMENT RECEIPT', style: TextStyle(fontFamily: 'monospace', fontSize: 12, letterSpacing: 3, color: _muted, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),
          const _Dashed(),
          const SizedBox(height: 14),
          _row('Receipt no.', _receiptNo),
          _row('Date', _friendlyWhen),
          if ((widget.tenantName ?? '').trim().isNotEmpty) _row('Received from', widget.tenantName!.trim()),
          _row('Paid via', _method),
          if (p.isPartial) _row('Type', 'Part payment'),
          const SizedBox(height: 14),
          const _Dashed(),
          const SizedBox(height: 18),
          Stack(
            alignment: Alignment.center,
            children: [
              Column(
                children: [
                  const Text('AMOUNT', style: TextStyle(fontFamily: 'monospace', fontSize: 11, letterSpacing: 3, color: _muted)),
                  const SizedBox(height: 4),
                  Text(_money(p.amount),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 32, fontWeight: FontWeight.w800, color: _ink)),
                ],
              ),
              Positioned(
                right: 0,
                top: -4,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 2.2, end: 1).animate(CurvedAnimation(parent: _stamp, curve: Curves.bounceOut)),
                  child: FadeTransition(
                    opacity: _stamp,
                    child: Transform.rotate(
                      angle: -0.28,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: _statusColor, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_statusLabel,
                            style: TextStyle(fontFamily: 'monospace', color: _statusColor, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _Dashed(),
          const SizedBox(height: 14),
          if (p.dueBeforePayment != null) _row('Due before', _money(p.dueBeforePayment!)),
          _row('Amount paid', _money(p.amount)),
          if (p.dueAfterPayment != null) _row('Balance left', _money(p.dueAfterPayment!), bold: true),
          if (_isRejected && (p.adminNotes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withOpacity(0.07),
                border: Border.all(color: const Color(0xFFC62828).withOpacity(0.25)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Reason: ${p.adminNotes!.trim()}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFC62828))),
            ),
          ],
          if (!_isPaid && !_isRejected) ...[
            const SizedBox(height: 12),
            const Text('Awaiting verification by the property team. You will be notified once it is confirmed.',
                textAlign: TextAlign.center, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: _muted)),
          ],
          const SizedBox(height: 18),
          const _Dashed(),
          const SizedBox(height: 16),
          const _Barcode(),
          const SizedBox(height: 8),
          Center(child: Text(_receiptNo, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: _muted, letterSpacing: 2))),
          const SizedBox(height: 14),
          const Center(
            child: Text('Thank you!', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 14)),
          ),
          const SizedBox(height: 2),
          const Center(
            child: Text('This is a system-generated receipt.', style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: _muted)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'monospace', color: _muted, fontSize: 12.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: _ink, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 7).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(n, (_) => Container(width: 4, height: 1.4, color: const Color(0xFFBDBAAE))),
      );
    });
  }
}

class _Barcode extends StatelessWidget {
  const _Barcode();
  @override
  Widget build(BuildContext context) {
    const widths = [2.0, 1.0, 3.0, 1.0, 1.0, 2.0, 3.0, 1.0, 2.0, 1.0, 1.0, 3.0, 2.0, 1.0, 2.0, 3.0, 1.0, 1.0, 2.0, 1.0, 3.0, 2.0, 1.0, 1.0, 2.0, 3.0, 1.0, 2.0];
    return SizedBox(
      height: 38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widths.length; i++)
            Container(width: widths[i], margin: const EdgeInsets.only(right: 2), color: i.isEven ? const Color(0xFF1B1B1B) : Colors.transparent),
        ],
      ),
    );
  }
}

/// Zig-zag (torn paper) top and bottom edges.
class _TornEdgeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const tooth = 9.0;
    const depth = 6.0;
    final path = Path()..moveTo(0, depth);
    var x = 0.0;
    var up = false;
    while (x < size.width) {
      x = (x + tooth).clamp(0, size.width).toDouble();
      path.lineTo(x, up ? depth : 0);
      up = !up;
    }
    path.lineTo(size.width, size.height - depth);
    x = size.width;
    up = false;
    while (x > 0) {
      x = (x - tooth).clamp(0, size.width).toDouble();
      path.lineTo(x, up ? size.height - depth : size.height);
      up = !up;
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
