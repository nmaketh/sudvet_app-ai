import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../data/case_repository.dart';

class CaseChatPage extends StatefulWidget {
  const CaseChatPage({
    super.key,
    required this.caseId,
    required this.caseRepository,
    required this.initialUserRole,
  });

  final String caseId;
  final CaseRepository caseRepository;
  final String initialUserRole;

  @override
  State<CaseChatPage> createState() => _CaseChatPageState();
}

class _CaseChatPageState extends State<CaseChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _initialLoading = true;
  bool _sending = false;
  String _userRole = 'chw';
  String _workflowStatus = 'unknown';
  int? _assignedVetId;
  String? _errorMessage;
  List<Map<String, dynamic>> _messages = const [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _userRole = widget.initialUserRole;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(initial: true));
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final timeline = await widget.caseRepository.getCaseTimeline(widget.caseId);
      if (!mounted) return;
      final raw = timeline['messages'];
      final parsed = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
          : const <Map<String, dynamic>>[];
      final prevCount = _messages.length;
      final assignedVetIdRaw = timeline['assignedVetId'];
      final assignedVetId = assignedVetIdRaw is int
          ? assignedVetIdRaw
          : int.tryParse(assignedVetIdRaw?.toString() ?? '');
      setState(() {
        _workflowStatus = timeline['workflowStatus']?.toString() ?? 'unknown';
        _assignedVetId = assignedVetId;
        _messages = parsed;
        _errorMessage = null;
        if (initial) _initialLoading = false;
      });
      if (initial || parsed.length > prevCount) {
        _scrollToBottom(animate: !initial);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (initial) _initialLoading = false;
        _errorMessage = 'Failed to load messages.';
      });
    }
  }

  /// CAHW cannot chat until a vet is assigned/claimed on this case.
  bool get _cahwChatLocked =>
      _userRole.toLowerCase() == 'cahw' && _assignedVetId == null;

  Future<void> _send() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty || _sending || _cahwChatLocked) return;
    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      await widget.caseRepository.addCaseMessage(
        caseId: widget.caseId,
        senderRole: _userRole,
        message: msg,
      );
      _messageController.clear();
      await _load();
      _scrollToBottom(animate: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Formatting helpers ────────────────────────────────────────────────────

  String _formatTime(Object? value) {
    final s = value?.toString() ?? '';
    final dt = s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  String _formatDateLabel(Object? value) {
    final s = value?.toString() ?? '';
    final dt = s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMMM d, y').format(dt);
  }

  bool _isSameDay(Object? a, Object? b) {
    final da = _parseLocalDate(a);
    final db = _parseLocalDate(b);
    if (da == null || db == null) return false;
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  DateTime? _parseLocalDate(Object? value) {
    final s = value?.toString() ?? '';
    return s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'vet':
        return 'Vet';
      case 'chw':
      case 'cahw':
        return 'CAHW';
      case 'admin':
        return 'Admin';
      default:
        if (role.isEmpty) return '?';
        return role[0].toUpperCase() + role.substring(1);
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return 'Open';
      case 'in_treatment':
      case 'in-treatment':
        return 'In Treatment';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      case 'unknown':
        return 'Unknown';
      default:
        if (status.isEmpty) return 'Unknown';
        return status[0].toUpperCase() + status.substring(1);
    }
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status.toLowerCase()) {
      case 'open':
        return cs.primary;
      case 'in_treatment':
      case 'in-treatment':
        return Colors.orange.shade600;
      case 'resolved':
        return Colors.teal;
      case 'closed':
        return cs.outline;
      default:
        return cs.outline;
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _dateSeparator(String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.outline,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final role = (item['senderRole'] ?? '').toString();
    final msg = (item['message'] ?? '').toString();
    String nr(String r) {
      final l = r.toLowerCase();
      return l == 'chw' ? 'cahw' : l;
    }

    // Primary: compare by sender email (most reliable — not affected by role format).
    // Fallback: role string comparison.
    final senderEmail = (item['senderEmail'] ?? '').toString().toLowerCase().trim();
    bool mine;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final currentEmail = authState.user.email.toLowerCase().trim();
      if (senderEmail.isNotEmpty && currentEmail.isNotEmpty) {
        mine = senderEmail == currentEmail;
      } else {
        mine = nr(role) == nr(authState.user.role.toLowerCase());
      }
    } else {
      mine = nr(role) == nr(_userRole);
    }
    final ts = _formatTime(item['createdAt']);
    final label = _roleLabel(role);

    final bgColor = mine ? cs.primaryContainer : cs.surfaceContainerHighest;
    final textColor = mine ? cs.onPrimaryContainer : cs.onSurface;
    final labelColor = mine ? cs.primary : cs.outline;
    final avatarBg = mine ? cs.primary : cs.secondaryContainer;
    final avatarFg = mine ? cs.onPrimary : cs.onSecondaryContainer;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine ? 18 : 4),
      bottomRight: Radius.circular(mine ? 4 : 18),
    );

    final avatar = CircleAvatar(
      radius: 15,
      backgroundColor: avatarBg,
      child: Text(
        label.isEmpty ? '?' : label[0].toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: avatarFg),
      ),
    );

    // Use Align + ConstrainedBox so the bubble stays on its side and doesn't
    // expand to fill the full row width.
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[avatar, const SizedBox(width: 8)],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: bgColor, borderRadius: radius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(msg, style: TextStyle(fontSize: 14, height: 1.4, color: textColor)),
                  const SizedBox(height: 5),
                  Text(
                    ts,
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mine) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: cs.outline),
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline, fontSize: 14),
              ),
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: () => _load(initial: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 56,
              color: cs.primary.withValues(alpha: 0.22),
            ),
            const SizedBox(height: 18),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a conversation with your vet\nto discuss this case.',
              style: TextStyle(fontSize: 13, color: cs.outline, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _messagesPanel(ColorScheme cs) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return _emptyState(cs);
    }

    final items = <Widget>[];
    for (var i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final prevTs = i > 0 ? _messages[i - 1]['createdAt'] : null;
      if (!_isSameDay(prevTs, msg['createdAt'])) {
        items.add(_dateSeparator(_formatDateLabel(msg['createdAt'])));
      }
      items.add(_bubble(msg));
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      children: [
        for (var i = 0; i < items.length; i++) ...[
          items[i],
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _inputBar(ColorScheme cs) {
    // CAHW cannot send messages until a vet is assigned to this case.
    if (_cahwChatLocked) {
      return Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: cs.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Chat is available once a vet has been assigned to this case.',
                style: TextStyle(fontSize: 13, color: cs.outline, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
                filled: true,
                fillColor: cs.surfaceContainerLowest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _sending
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: 46,
                    height: 46,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
                      ),
                    ),
                  )
                : Material(
                    key: const ValueKey('send'),
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(23),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(23),
                      onTap: _send,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(Icons.send_rounded, color: cs.onPrimary, size: 20),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusLabel = _statusLabel(_workflowStatus);
    final statusColor = _statusColor(_workflowStatus, cs);
    final shortId = widget.caseId.length > 8
        ? '…${widget.caseId.substring(widget.caseId.length - 8)}'
        : widget.caseId;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Case Chat', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 1),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$statusLabel · $shortId',
                    style: TextStyle(fontSize: 12, color: cs.outline, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _load(initial: true),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _messagesPanel(cs)),
            if (_errorMessage != null && _messages.isNotEmpty)
              Container(
                width: double.infinity,
                color: cs.errorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
            _inputBar(cs),
          ],
        ),
      ),
    );
  }
}
