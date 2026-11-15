import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/constants.dart';
import '../../widgets/common/snackbar_helper.dart';

/// Lets a tenant check out of the PG. Checking out ends the stay, frees the bed
/// and signs the tenant out, so it is guarded by:
///  1. an outstanding-dues check (no checkout while money is owed), and
///  2. an explicit confirmation step where the tenant must type CHECKOUT.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _reason = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  double _due = 0;
  int _unpaidBills = 0;
  String? _pg;
  String? _room;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getCheckoutEligibility();
    if (!mounted) return;
    if (res['success'] == true) {
      final d = Map<String, dynamic>.from(res['data'] as Map);
      final due = (d['outstanding_amount'] is num) ? (d['outstanding_amount'] as num).toDouble() : 0.0;
      setState(() {
        _due = due < 0 ? 0 : due;
        _unpaidBills = (d['unpaid_bills'] is num) ? (d['unpaid_bills'] as num).toInt() : 0;
        _pg = d['pg_name']?.toString();
        _room = d['room_number']?.toString();
        _loading = false;
      });
    } else {
      setState(() {
        _error = (res['message'] ?? 'Could not check your account.').toString();
        _loading = false;
      });
    }
  }

  String _money(double v) => '₹${NumberFormat('#,##,##0.00', 'en_IN').format(v)}';

  Future<void> _confirmAndCheckout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ConfirmCheckoutDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    final res = await _api.checkoutSelf(reason: _reason.text);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res['success'] == true) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161616),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Column(
            children: [
              Icon(Icons.check_circle_rounded, color: kLivinkeyGreen, size: 54),
              SizedBox(height: 12),
              Text('Checked out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Text(
            (res['message'] ?? 'You have checked out successfully.').toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.7), height: 1.4),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: kLivinkeyGreen, foregroundColor: Colors.black, elevation: 0),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      await SessionManager().logout();
    } else {
      final due = res['outstanding_amount'];
      if (res['code'] == 'DUES_PENDING' && due is num) {
        setState(() => _due = due.toDouble());
      }
      SnackbarHelper.showError(context, (res['message'] ?? 'Could not complete your checkout.').toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kLivinkeyBlack,
      appBar: AppBar(title: const Text('Check out')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kLivinkeyGreen))
          : _error != null
              ? _errorView()
              : _content(),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white.withOpacity(0.3)),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7))),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _load,
                style: OutlinedButton.styleFrom(foregroundColor: kLivinkeyGreen, side: const BorderSide(color: kLivinkeyGreen)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _content() {
    final blocked = _due > 0.005;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.logout_rounded, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    [if ((_pg ?? '').isNotEmpty) _pg!, if ((_room ?? '').isNotEmpty) 'Room $_room'].join(' · '),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Text('Before you leave', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _point('Checking out ends your stay and frees your bed.'),
              _point('You will be signed out and will no longer be able to use this app.'),
              _point('This cannot be undone from the app. The property team can restore your account if it was a mistake.'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (blocked)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEF5350).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFEF5350)),
                  const SizedBox(width: 10),
                  Text('${_money(_due)} still due',
                      style: const TextStyle(color: Color(0xFFEF5350), fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'You have $_unpaidBills unpaid ${_unpaidBills == 1 ? 'bill' : 'bills'}. Please clear your dues from the Payments tab, then come back to check out.',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), height: 1.4, fontSize: 13),
                ),
              ],
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kLivinkeyGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kLivinkeyGreen.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.verified_rounded, color: kLivinkeyGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text('You have no outstanding dues.', style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: 200,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Reason for leaving (optional)',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
              counterStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLivinkeyGreen)),
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: (blocked || _submitting) ? null : _confirmAndCheckout,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.logout_rounded),
            label: Text(_submitting ? 'Checking out…' : 'Check out', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withOpacity(0.08),
              disabledForegroundColor: Colors.white.withOpacity(0.35),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _point(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: kLivinkeyGreen, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.78), height: 1.4, fontSize: 13.5))),
          ],
        ),
      );
}

class _ConfirmCheckoutDialog extends StatefulWidget {
  const _ConfirmCheckoutDialog();

  @override
  State<_ConfirmCheckoutDialog> createState() => _ConfirmCheckoutDialogState();
}

class _ConfirmCheckoutDialogState extends State<_ConfirmCheckoutDialog> {
  final TextEditingController _c = TextEditingController();
  bool get _ok => _c.text.trim().toUpperCase() == 'CHECKOUT';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161616),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: Colors.white.withOpacity(0.08))),
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange),
        SizedBox(width: 10),
        Expanded(child: Text('Check out for good?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You are about to end your stay. You will be signed out immediately.',
            style: TextStyle(color: Colors.white.withOpacity(0.75), height: 1.4),
          ),
          const SizedBox(height: 14),
          Text('Type CHECKOUT to confirm', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Stay', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: _ok ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE53935),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white.withOpacity(0.08),
            elevation: 0,
          ),
          child: const Text('Check out', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
