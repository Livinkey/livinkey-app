import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/common/snackbar_helper.dart';

/// Caches whether the signed-in tenant actually shares a room, so the drawer
/// only shows "Roommate details" to tenants who have roommates.
class RoommateAvailability {
  static bool? _has;
  static DateTime? _at;

  static Future<bool> hasRoommates({bool force = false}) async {
    final fresh = _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 5);
    if (!force && _has != null && fresh) return _has!;
    final res = await ApiService().getRoommates();
    final ok = res['success'] == true && (res['data']?['has_roommates'] == true);
    _has = ok;
    _at = DateTime.now();
    return ok;
  }

  static void reset() {
    _has = null;
    _at = null;
  }
}

class RoommatesScreen extends StatefulWidget {
  const RoommatesScreen({super.key});

  @override
  State<RoommatesScreen> createState() => _RoommatesScreenState();
}

class _RoommatesScreenState extends State<RoommatesScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  String? _room;
  String? _pg;
  List<Map<String, dynamic>> _roommates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getRoommates();
    if (!mounted) return;
    if (res['success'] == true) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      setState(() {
        _room = data['room_number']?.toString();
        _pg = data['pg_name']?.toString();
        _roommates = ((data['roommates'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } else {
      setState(() {
        _error = (res['message'] ?? 'Could not load roommate details.').toString();
        _loading = false;
      });
    }
  }

  String _since(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? '' : DateFormat('d MMM yyyy').format(d);
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    try {
      if (!await launchUrl(uri) && mounted) SnackbarHelper.showError(context, 'Could not open the dialer.');
    } catch (_) {
      if (mounted) SnackbarHelper.showError(context, 'Could not open the dialer.');
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) SnackbarHelper.showSuccess(context, '$what copied');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kLivinkeyBlack,
      appBar: AppBar(title: const Text('Roommate details')),
      body: RefreshIndicator(
        color: kLivinkeyGreen,
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: List.generate(
          2,
          (_) => Container(
            height: 150,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
          ),
        ),
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7))),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(foregroundColor: kLivinkeyGreen, side: const BorderSide(color: kLivinkeyGreen)),
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    }
    if (_roommates.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.people_outline_rounded, size: 52, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('No roommates right now',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('You are the only tenant in your room at the moment.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kLivinkeyGreen.withOpacity(0.18), kLivinkeyGreen.withOpacity(0.05)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kLivinkeyGreen.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.meeting_room_rounded, color: kLivinkeyGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Room ${_room ?? '-'}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    if ((_pg ?? '').isNotEmpty)
                      Text(_pg!, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5)),
                  ],
                ),
              ),
              Text('${_roommates.length} ${_roommates.length == 1 ? 'roommate' : 'roommates'}',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final r in _roommates) _card(r),
        const SizedBox(height: 8),
        Text('Only basic contact details are shared between roommates.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11.5)),
      ],
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final name = (r['full_name'] ?? 'Roommate').toString();
    final phone = (r['phone'] ?? '').toString();
    final email = (r['email'] ?? '').toString();
    final since = _since(r['arrival_date']?.toString());
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: kLivinkeyGreen.withOpacity(0.18),
                child: Text(initial, style: const TextStyle(color: kLivinkeyGreen, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    if (since.isNotEmpty)
                      Text('Staying since $since', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (phone.isNotEmpty || email.isNotEmpty) const SizedBox(height: 14),
          if (phone.isNotEmpty)
            _line(Icons.phone_rounded, phone, onTap: () => _call(phone), onLong: () => _copy(phone, 'Phone number'), action: Icons.call_rounded),
          if (email.isNotEmpty)
            _line(Icons.email_rounded, email, onLong: () => _copy(email, 'Email'), action: Icons.copy_rounded, onTap: () => _copy(email, 'Email')),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text, {VoidCallback? onTap, VoidCallback? onLong, IconData? action}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: onLong,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white.withOpacity(0.45)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14))),
            if (action != null) Icon(action, size: 18, color: kLivinkeyGreen),
          ],
        ),
      ),
    );
  }
}
