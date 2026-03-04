import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/base_url_resolver.dart';
import '../../../widgets/status_chip.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../bloc/case_bloc.dart';
import '../bloc/case_event.dart';
import '../bloc/case_state.dart';
import '../data/case_repository.dart';
import '../model/case_record.dart';

enum _CaseDetailSection { overview, evidence, notes, workflow }

class _AssignableVet {
  const _AssignableVet({
    required this.id,
    required this.name,
    required this.email,
    required this.activeCaseload,
    this.location,
  });

  final int id;
  final String name;
  final String email;
  final int activeCaseload;
  final String? location;

  String get label {
    final normalizedLocation = (location ?? '').trim();
    if (normalizedLocation.isNotEmpty) {
      return '$email · $normalizedLocation · $activeCaseload active';
    }
    return '$email · $activeCaseload active';
  }

  static _AssignableVet? fromMap(Map<String, dynamic> raw) {
    final idRaw = raw['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
    final name = (raw['name'] ?? '').toString().trim();
    final email = (raw['email'] ?? '').toString().trim().toLowerCase();
    final caseloadRaw = raw['active_caseload'] ?? raw['activeCaseload'] ?? 0;
    final activeCaseload = caseloadRaw is int
        ? caseloadRaw
        : int.tryParse(caseloadRaw?.toString() ?? '') ?? 0;
    final location = (raw['location'] ?? '').toString().trim();
    if (id == null || id <= 0 || name.isEmpty || email.isEmpty) {
      return null;
    }
    return _AssignableVet(
      id: id,
      name: name,
      email: email,
      activeCaseload: activeCaseload,
      location: location.isEmpty ? null : location,
    );
  }
}

class CaseDetailPage extends StatefulWidget {
  const CaseDetailPage({super.key, required this.caseId});

  final String caseId;

  @override
  State<CaseDetailPage> createState() => _CaseDetailPageState();
}

class _CaseDetailPageState extends State<CaseDetailPage> {
  final _notesController = TextEditingController();
  final _assessmentController = TextEditingController(text: 'suspected');
  final _planController = TextEditingController(text: 'monitor');
  final _prescriptionController = TextEditingController();
  final _followUpDateController = TextEditingController();
  String? _boundCaseId;
  bool _isTimelineLoading = false;
  bool _isActionLoading = false;
  String _workflowStatus = 'unknown';
  String _triageStatus = 'open';
  String _userRole = 'chw';
  List<Map<String, dynamic>> _timelineMessages = const [];
  List<Map<String, dynamic>> _timelineReviews = const [];
  List<Map<String, dynamic>> _timelineReceipts = const [];
  Map<String, dynamic> _workflowParticipants = const {};
  int _chatUnreadCount = 0;
  String? _lastChatAlertSignature;
  DateTime? _lastChatAlertAt;
  bool _workflowLoadedOnce = false;
  bool _chatSheetOpen = false;
  _CaseDetailSection _detailSection = _CaseDetailSection.overview;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CaseBloc>().add(CaseOpenedById(widget.caseId));
      _loadWorkflow(widget.caseId);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _loadWorkflow(widget.caseId);
      }
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _assessmentController.dispose();
    _planController.dispose();
    _prescriptionController.dispose();
    _followUpDateController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  String _chatLastSeenKey(String role, String caseId) => 'chat_last_seen_${role}_$caseId';

  String _normalizeRole(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'chw' || normalized == 'cahw') {
      return 'cahw';
    }
    return normalized;
  }

  String _resolveCurrentUserRole({String? fallback}) {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final serverRole = _normalizeRole(authState.user.role);
      if (serverRole.isNotEmpty) {
        return serverRole;
      }
    }
    final normalizedFallback = _normalizeRole(fallback ?? '');
    return normalizedFallback.isEmpty ? 'cahw' : normalizedFallback;
  }

  Map<String, String?> _currentActorIdentity() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      return {
        'id': authState.user.id,
        'name': authState.user.name.trim().isEmpty ? null : authState.user.name.trim(),
        'email': authState.user.email.trim().isEmpty ? null : authState.user.email.trim().toLowerCase(),
      };
    }
    return const {'id': null, 'name': null, 'email': null};
  }

  String _participantLabel(Map<String, dynamic>? participant, {required String empty}) {
    final p = participant ?? const <String, dynamic>{};
    final name = (p['name'] ?? '').toString().trim();
    final email = (p['email'] ?? '').toString().trim();
    if (name.isNotEmpty && email.isNotEmpty) return '$name ($email)';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return empty;
  }

  Map<String, dynamic> _assignedVetParticipant() {
    final raw = _workflowParticipants['assignedVet'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _requestedVetParticipant() {
    final raw = _workflowParticipants['requestedVet'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  bool _hasAssignedVet() {
    final vet = _assignedVetParticipant();
    return ['id', 'name', 'email'].any((k) => (vet[k] ?? '').toString().trim().isNotEmpty);
  }

  bool _currentVetOwnsCase() {
    if (_userRole != 'vet') return false;
    final actor = _currentActorIdentity();
    final vet = _assignedVetParticipant();
    final actorId = (actor['id'] ?? '').toString().trim();
    final actorName = (actor['name'] ?? '').toString().trim().toLowerCase();
    final actorEmail = (actor['email'] ?? '').toString().trim().toLowerCase();
    final vetId = (vet['id'] ?? '').toString().trim();
    final vetName = (vet['name'] ?? '').toString().trim().toLowerCase();
    final vetEmail = (vet['email'] ?? '').toString().trim().toLowerCase();
    if (actorId.isNotEmpty && vetId.isNotEmpty && actorId == vetId) return true;
    if (actorEmail.isNotEmpty && vetEmail.isNotEmpty && actorEmail == vetEmail) return true;
    if (actorName.isNotEmpty && vetName.isNotEmpty && actorName == vetName) return true;
    return false;
  }

  bool _currentVetIsRequested() {
    if (_userRole != 'vet') return false;
    final actor = _currentActorIdentity();
    final requestedVet = _requestedVetParticipant();
    final actorId = (actor['id'] ?? '').toString().trim();
    final actorName = (actor['name'] ?? '').toString().trim().toLowerCase();
    final actorEmail = (actor['email'] ?? '').toString().trim().toLowerCase();
    final requestedId = (requestedVet['id'] ?? '').toString().trim();
    final requestedName = (requestedVet['name'] ?? '').toString().trim().toLowerCase();
    final requestedEmail = (requestedVet['email'] ?? '').toString().trim().toLowerCase();
    if (actorId.isNotEmpty && requestedId.isNotEmpty && actorId == requestedId) return true;
    if (actorEmail.isNotEmpty && requestedEmail.isNotEmpty && actorEmail == requestedEmail) return true;
    if (actorName.isNotEmpty && requestedName.isNotEmpty && actorName == requestedName) return true;
    return false;
  }

  bool _canCurrentVetClaim() {
    if (_userRole != 'vet') return false;
    if (_hasAssignedVet()) return false;
    if (_triageStatus == 'escalated') return true;
    return _currentVetIsRequested();
  }

  bool _isHumanChatMessage(Map<String, dynamic> msg, String role) {
    final sender = _normalizeRole((msg['senderRole'] ?? '').toString());
    final currentRole = _normalizeRole(role);
    if (sender.isEmpty) return false;
    if (sender == currentRole) return false;
    if (sender == 'system' || sender == 'receipt') return false;
    final body = (msg['message'] ?? '').toString().trim();
    return body.isNotEmpty;
  }

  Future<int> _computeUnreadCount(String caseId, String role, List<Map<String, dynamic>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(_chatLastSeenKey(role, caseId));
    int count = 0;
    for (final msg in messages) {
      if (!_isHumanChatMessage(msg, role)) continue;
      final ts = msg['createdAt']?.toString() ?? '';
      if (ts.isEmpty) continue;
      if (lastSeen == null || ts.compareTo(lastSeen) > 0) {
        count += 1;
      }
    }
    return count;
  }

  Future<void> _markChatSeen(String caseId, String role, List<Map<String, dynamic>> messages) async {
    final latest = messages.reversed.firstWhere(
      (m) => _isHumanChatMessage(m, role),
      orElse: () => <String, dynamic>{},
    );
    final ts = latest['createdAt']?.toString().trim() ?? '';
    if (ts.isEmpty) {
      if (mounted && _chatUnreadCount != 0) {
        setState(() => _chatUnreadCount = 0);
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatLastSeenKey(role, caseId), ts);
    if (mounted && _chatUnreadCount != 0) {
      setState(() => _chatUnreadCount = 0);
    }
  }

  Future<void> _loadWorkflow(String caseId) async {
    if (_isTimelineLoading) {
      return;
    }
    setState(() => _isTimelineLoading = true);
    try {
      final caseRepository = context.read<CaseRepository>();
      final timeline = await caseRepository.getCaseTimeline(caseId);
      if (!mounted) {
        return;
      }
      final resolvedRole = _resolveCurrentUserRole(fallback: _userRole);
      final msgs = timeline['messages'];
      final revs = timeline['reviews'];
      final recs = timeline['receipts'];
      final parsedMsgs = msgs is List
          ? msgs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
          : const <Map<String, dynamic>>[];
      final parsedRevs = revs is List
          ? revs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
          : const <Map<String, dynamic>>[];
      final parsedRecs = recs is List
          ? recs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
          : const <Map<String, dynamic>>[];
      final participantsRaw = timeline['participants'];
      final participants = participantsRaw is Map
          ? Map<String, dynamic>.from(participantsRaw)
          : const <String, dynamic>{};
      final prevUnreadCount = _chatUnreadCount;
      final isFirstWorkflowLoad = !_workflowLoadedOnce;
      final unreadCount = await _computeUnreadCount(caseId, resolvedRole, parsedMsgs);
      final latestUnread = parsedMsgs.reversed.firstWhere(
        (m) => _isHumanChatMessage(m, resolvedRole),
        orElse: () => <String, dynamic>{},
      );
      final latestSig = latestUnread.isEmpty
          ? null
          : '${latestUnread['id'] ?? ''}|${latestUnread['createdAt'] ?? ''}|${latestUnread['senderRole'] ?? ''}';
      final now = DateTime.now();
      final alertCooldownPassed =
          _lastChatAlertAt == null || now.difference(_lastChatAlertAt!) >= const Duration(seconds: 10);
      final shouldAlert =
          !_chatSheetOpen &&
          !isFirstWorkflowLoad &&
          unreadCount > prevUnreadCount &&
          unreadCount > 0 &&
          latestSig != null &&
          latestSig != _lastChatAlertSignature &&
          alertCooldownPassed;
      setState(() {
        _userRole = resolvedRole;
        _workflowStatus = timeline['workflowStatus']?.toString() ?? 'unknown';
        _triageStatus = timeline['triageStatus']?.toString() ?? 'open';
        _timelineMessages = parsedMsgs;
        _timelineReviews = parsedRevs;
        _timelineReceipts = parsedRecs;
        _workflowParticipants = participants;
        _chatUnreadCount = unreadCount;
        _workflowLoadedOnce = true;
        if (latestSig != null) {
          _lastChatAlertSignature = latestSig;
        }
        if (shouldAlert) {
          _lastChatAlertAt = now;
        }
      });
      if (shouldAlert && mounted) {
        final senderLabel = (latestUnread['senderName'] ?? latestUnread['senderRole'] ?? 'New message')
            .toString()
            .trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              unreadCount == 1
                  ? 'New message from $senderLabel'
                  : '$unreadCount unread messages in case chat',
            ),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openChatInline(caseId),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // Keep the rest of page usable.
    } finally {
      if (mounted) {
        setState(() => _isTimelineLoading = false);
      }
    }
  }

  Future<void> _submitVetReview(String caseId) async {
    final assessment = _assessmentController.text.trim();
    final plan = _planController.text.trim();
    final prescription = _prescriptionController.text.trim();
    final followUpDate = _followUpDateController.text.trim();
    if (assessment.isEmpty || plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assessment and plan are required.')),
      );
      return;
    }
    if (plan.toLowerCase() == 'treatment' && prescription.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prescription is required for treatment plan.')),
      );
      return;
    }
    if (followUpDate.isNotEmpty && DateTime.tryParse(followUpDate) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up date must be YYYY-MM-DD.')),
      );
      return;
    }
    setState(() => _isActionLoading = true);
    try {
      await context.read<CaseRepository>().submitVetReview(
        caseId: caseId,
        senderId: _currentActorIdentity()['id'],
        senderName: _currentActorIdentity()['name'],
        senderEmail: _currentActorIdentity()['email'],
        assessment: assessment,
        plan: plan,
        prescription: prescription,
        followUpDate: followUpDate,
        message: 'Vet advice updated.',
      );
      await _loadWorkflow(caseId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vet review submitted.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  Future<List<_AssignableVet>> _fetchAssignableVets() async {
    final rows = await context.read<CaseRepository>().getAssignableVets();
    final vets = rows
        .map(_AssignableVet.fromMap)
        .whereType<_AssignableVet>()
        .toList(growable: false);
    vets.sort((a, b) {
      final byLoad = a.activeCaseload.compareTo(b.activeCaseload);
      if (byLoad != 0) return byLoad;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return vets;
  }

  Future<_AssignableVet?> _pickVetDialog(List<_AssignableVet> vets) async {
    final searchController = TextEditingController();
    var filtered = List<_AssignableVet>.from(vets);
    try {
      return await showDialog<_AssignableVet>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            void applyFilter(String query) {
              final q = query.trim().toLowerCase();
              setModalState(() {
                if (q.isEmpty) {
                  filtered = List<_AssignableVet>.from(vets);
                } else {
                  filtered = vets.where((v) {
                    return v.name.toLowerCase().contains(q) ||
                        v.email.toLowerCase().contains(q) ||
                        (v.location ?? '').toLowerCase().contains(q);
                  }).toList(growable: false);
                }
              });
            }

            return AlertDialog(
              title: const Text('Request Specific Vet'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      onChanged: applyFilter,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search by name, email, or location',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 320,
                      child: filtered.isEmpty
                          ? const Center(child: Text('No vets match your search.'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final vet = filtered[index];
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                  title: Text(vet.name),
                                  subtitle: Text(vet.label),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () => Navigator.of(context).pop(vet),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _allowAnyVetAssignment(String caseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow Vet Assignment'),
        content: const Text('This will send the case to the shared vet queue so any available vet can claim it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.groups_outlined, size: 16),
            label: const Text('Allow Assignment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isActionLoading = true);
    try {
      await context.read<CaseRepository>().escalateCase(
            caseId,
            allowAssignment: true,
            requestNote: 'CAHW allowed assignment to available vet',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Case is now in the shared vet queue.')),
        );
      }
      await _loadWorkflow(caseId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _requestSpecificVet(String caseId) async {
    setState(() => _isActionLoading = true);
    List<_AssignableVet> vets = const [];
    try {
      vets = await _fetchAssignableVets();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      if (mounted) setState(() => _isActionLoading = false);
      return;
    }
    if (!mounted) return;
    setState(() => _isActionLoading = false);

    if (vets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No vets are available for assignment right now.')),
      );
      return;
    }

    final selectedVet = await _pickVetDialog(vets);
    if (!mounted || selectedVet == null) return;

    setState(() => _isActionLoading = true);
    try {
      await context.read<CaseRepository>().escalateCase(
            caseId,
            allowAssignment: false,
            requestedVetId: selectedVet.id,
            vetEmail: selectedVet.email,
            requestNote: 'CAHW requested specific vet: ${selectedVet.email}',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request sent to ${selectedVet.name}.')),
        );
      }
      await _loadWorkflow(caseId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _claimCase(String caseId) async {
    if (!_canCurrentVetClaim()) return;
    final caseRepository = context.read<CaseRepository>();
    final caseBloc = context.read<CaseBloc>();
    setState(() => _isActionLoading = true);
    try {
      await caseRepository.claimCase(
        caseId: caseId,
        note: 'Vet accepted case from queue',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Case accepted. You are now assigned.')),
      );
      caseBloc.add(CaseOpenedById(caseId));
      await _loadWorkflow(caseId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _openChatInline(String caseId) async {
    if (_userRole == 'vet' && !_currentVetOwnsCase()) {
      final hasAssignedVet = _hasAssignedVet();
      final vetLabel = _participantLabel(_assignedVetParticipant(), empty: 'another assigned vet');
      final message = hasAssignedVet
          ? 'Chat is restricted to the assigned vet ($vetLabel). Transfer is required before continuing this case.'
          : 'Accept this case first before opening chat.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
      return;
    }
    final messageController = TextEditingController();
    final scrollController = ScrollController();
    bool sending = false;
    bool loading = false;
    String? error;
    List<Map<String, dynamic>> messages = List<Map<String, dynamic>>.from(_timelineMessages);

    String fmtTs(String raw) {
      final dt = DateTime.tryParse(raw)?.toLocal();
      return dt == null ? raw : DateFormat('MMM d, h:mm a').format(dt);
    }

    Future<void> refreshChat(StateSetter setModalState) async {
      if (loading) return;
      setModalState(() {
        loading = true;
        error = null;
      });
      try {
        await _loadWorkflow(caseId);
        messages = List<Map<String, dynamic>>.from(_timelineMessages);
      } catch (e) {
        error = 'Failed to refresh chat.';
      } finally {
        if (mounted) {
          setModalState(() => loading = false);
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      });
    }

    _chatSheetOpen = true;
    await _markChatSeen(caseId, _userRole, _timelineMessages);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollController.hasClients && scrollController.position.maxScrollExtent > 0) {
                scrollController.jumpTo(scrollController.position.maxScrollExtent);
              }
            });
            return FractionallySizedBox(
              heightFactor: 0.96,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Material(
                  color: const Color(0xFFF3F4F6),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Case Chat', style: TextStyle(fontWeight: FontWeight.w700)),
                                    Text('Status: $_workflowStatus', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => refreshChat(setModalState),
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                        ),
                        if (error != null)
                          Container(
                            width: double.infinity,
                            color: Colors.red.shade50,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Text(error!, style: TextStyle(color: Colors.red.shade700)),
                          ),
                        Expanded(
                          child: loading && messages.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : messages.isEmpty
                                  ? const Center(child: Text('No messages yet.'))
                                  : ListView.separated(
                                      controller: scrollController,
                                      padding: const EdgeInsets.all(12),
                                      itemCount: messages.length,
                                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final m = messages[index];
                                        final role = (m['senderRole'] ?? 'unknown').toString().trim();
                                        final senderName = (m['senderName'] ?? '').toString().trim();
                                        final body = (m['message'] ?? '').toString();
                                        final ts = fmtTs((m['createdAt'] ?? '').toString());
                                        final senderEmail = (m['senderEmail'] ?? '').toString().toLowerCase().trim();
                                        final myIdentity = _currentActorIdentity();
                                        final myEmail = (myIdentity['email'] ?? '').toString().toLowerCase().trim();
                                        final mine = (senderEmail.isNotEmpty && myEmail.isNotEmpty && senderEmail == myEmail)
                                            || _normalizeRole(role) == _normalizeRole(_userRole);
                                        final label = senderName.isNotEmpty
                                            ? '$senderName (${role.toUpperCase()})'
                                            : role.toUpperCase();
                                        return Align(
                                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context).size.width * 0.72,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: mine ? const Color(0xFFDCF8E7) : Colors.white,
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: const Color(0xFFE5E7EB)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4B5563))),
                                                  const SizedBox(height: 4),
                                                  Text(body),
                                                  const SizedBox(height: 6),
                                                  Text(ts, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: messageController,
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    hintText: 'Type a message...',
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 132,
                                height: 48,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(132, 48),
                                    maximumSize: const Size(132, 48),
                                  ),
                                  onPressed: sending
                                      ? null
                                      : () async {
                                          final textMsg = messageController.text.trim();
                                          if (textMsg.isEmpty) return;
                                          setModalState(() => sending = true);
                                          try {
                                            await context.read<CaseRepository>().addCaseMessage(
                                              caseId: caseId,
                                              senderRole: _normalizeRole(_userRole),
                                              senderId: _currentActorIdentity()['id'],
                                              senderName: _currentActorIdentity()['name'],
                                              senderEmail: _currentActorIdentity()['email'],
                                              message: textMsg,
                                            );
                                            messageController.clear();
                                            await refreshChat(setModalState);
                                          } on ApiException catch (e) {
                                            setModalState(() => error = e.message);
                                          } finally {
                                            if (mounted) setModalState(() => sending = false);
                                          }
                                        },
                                  icon: const Icon(Icons.send_rounded),
                                  label: Text(sending ? 'Sending' : 'Send'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    _chatSheetOpen = false;
    messageController.dispose();
    scrollController.dispose();
    if (mounted) {
      await _markChatSeen(caseId, _userRole, _timelineMessages);
      await _loadWorkflow(caseId);
    }
  }

  Future<void> _transferCaseToVet(String caseId) async {
    if (!_currentVetOwnsCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the assigned vet can transfer this case.')),
      );
      return;
    }
    final currentVet = _assignedVetParticipant();
    final newVetEmailController = TextEditingController();
    final newVetNameController = TextEditingController();
    final reasonController = TextEditingController();
    final messageController = TextEditingController(
      text: 'Transferring case to another vet for continued handling.',
    );
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transfer Case to Another Vet'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Current assigned vet: ${_participantLabel(currentVet, empty: 'Unassigned')}',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newVetNameController,
                  decoration: const InputDecoration(labelText: 'New vet name (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newVetEmailController,
                  decoration: const InputDecoration(labelText: 'New vet email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Transfer reason'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Message to new vet (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Transfer')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final newVetEmail = newVetEmailController.text.trim();
      if (newVetEmail.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New vet email is required for transfer.')),
        );
        return;
      }
      setState(() => _isActionLoading = true);
      await context.read<CaseRepository>().transferCaseToVet(
        caseId: caseId,
        senderId: _currentActorIdentity()['id'],
        senderName: _currentActorIdentity()['name'],
        senderEmail: _currentActorIdentity()['email'],
        newVetEmail: newVetEmail,
        newVetName: newVetNameController.text.trim(),
        reason: reasonController.text.trim(),
        message: messageController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Case transferred to another vet.')),
        );
      }
      await _loadWorkflow(caseId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      newVetEmailController.dispose();
      newVetNameController.dispose();
      reasonController.dispose();
      messageController.dispose();
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  Future<void> _closeCase(String caseId) async {
    final outcome = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Close Case'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'recovered'),
            child: const Text('Recovered'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'improved'),
            child: const Text('Improved'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'worsened'),
            child: const Text('Worsened'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'deceased'),
            child: const Text('Deceased'),
          ),
        ],
      ),
    );
    if (!mounted || outcome == null) {
      return;
    }
    final caseBloc = context.read<CaseBloc>();
    setState(() => _isActionLoading = true);
    try {
      await context.read<CaseRepository>().closeCase(
        caseId: caseId,
        outcome: outcome,
        senderRole: _normalizeRole(_userRole),
        senderId: _currentActorIdentity()['id'],
        senderName: _currentActorIdentity()['name'],
        senderEmail: _currentActorIdentity()['email'],
        notes: _notesController.text.trim(),
      );
      await _loadWorkflow(caseId);
      caseBloc.add(CaseOpenedById(caseId));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  Future<void> _pickFollowUpDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 3)),
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      _followUpDateController.text = picked.toIso8601String().split('T').first;
      setState(() {});
    }
  }

  List<String> _caseImagePaths(CaseRecord item) {
    final seen = <String>{};
    final out = <String>[];
    if (item.imagePath != null && item.imagePath!.trim().isNotEmpty) {
      final p = item.imagePath!.trim();
      if (seen.add(p)) out.add(p);
    }
    for (final p in item.attachments) {
      final s = p.trim();
      if (s.isEmpty) {
        continue;
      }
      if (seen.add(s)) {
        out.add(s);
      }
    }
    return out;
  }

  Future<void> _confirmDelete(String caseId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete case?'),
          content: const Text(
            'This removes the case from local history. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) {
      return;
    }

    context.read<CaseBloc>().add(CaseDeleted(caseId));
    context.go('/app/history');
  }

  String _sectionLabel(_CaseDetailSection section) {
    switch (section) {
      case _CaseDetailSection.overview:
        return 'Overview';
      case _CaseDetailSection.evidence:
        return 'Evidence';
      case _CaseDetailSection.notes:
        return 'Notes';
      case _CaseDetailSection.workflow:
        return 'Workflow';
    }
  }

  IconData _sectionIcon(_CaseDetailSection section) {
    switch (section) {
      case _CaseDetailSection.overview:
        return Icons.dashboard_outlined;
      case _CaseDetailSection.evidence:
        return Icons.fact_check_outlined;
      case _CaseDetailSection.notes:
        return Icons.note_alt_outlined;
      case _CaseDetailSection.workflow:
        return Icons.account_tree_outlined;
    }
  }

  Widget _buildSectionSwitcher(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sections',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _CaseDetailSection.values.map((section) {
                final selected = _detailSection == section;
                return ChoiceChip(
                  selected: selected,
                  label: Text(_sectionLabel(section)),
                  avatar: Icon(
                    _sectionIcon(section),
                    size: 16,
                    color: selected ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                  ),
                  onSelected: (_) => setState(() => _detailSection = section),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context, CaseRecord item) {
    final prediction = item.prediction ?? 'Pending prediction';
    final confidence = item.confidence;
    final method = item.method ?? 'n/a';
    final evidenceQuality = item.predictionJson?['evidence_quality']?.toString();
    final activeSymptoms = item.symptoms.values.where((v) => v).length;
    final imageCount = _caseImagePaths(item).length;
    final topRecommendations = item.recommendations.take(3).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Case Overview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Prediction: $prediction')),
                Chip(label: Text('Urgency: ${item.urgency}')),
                Chip(label: Text('Follow-up: ${item.followUpStatus.label}')),
                if (confidence != null) Chip(label: Text('Confidence: ${(confidence * 100).round()}%')),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Method: $method'),
                  if (evidenceQuality != null && evidenceQuality.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Evidence quality: $evidenceQuality'),
                  ],
                  const SizedBox(height: 4),
                  Text('Active symptoms: $activeSymptoms / ${item.symptoms.length}'),
                  const SizedBox(height: 4),
                  Text('Images attached: $imageCount'),
                  const SizedBox(height: 4),
                  Text('CHW / User: ${item.chwOwnerLabel}'),
                  const SizedBox(height: 4),
                  Text('Assigned Vet: ${item.assignedVetLabel}'),
                ],
              ),
            ),
            if (topRecommendations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Top Recommendations',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              ...topRecommendations.map(
                (rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('- $rec'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _detailSection = _CaseDetailSection.evidence),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Open Evidence'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _detailSection = _CaseDetailSection.workflow),
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Open Workflow'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CaseBloc, CaseState>(
      listenWhen: (previous, current) =>
          previous.infoMessage != current.infoMessage ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);
        if (state.infoMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.infoMessage!)));
          context.read<CaseBloc>().add(const CaseFeedbackCleared());
        } else if (state.errorMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<CaseBloc>().add(const CaseFeedbackCleared());
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Case Details')),
        body: BlocBuilder<CaseBloc, CaseState>(
          builder: (context, state) {
            final item = state.selectedCase;
            if (item == null || item.id != widget.caseId) {
              if (!state.isLoading) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.find_in_page_outlined, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'This case is no longer available.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => context.go('/app/history'),
                          child: const Text('Go to History'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }

            if (_boundCaseId != item.id) {
              _boundCaseId = item.id;
              _notesController.text = item.notes ?? '';
              WidgetsBinding.instance.addPostFrameCallback((_) => _loadWorkflow(item.id));
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.animalLabel} - ${item.id}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            StatusChip(status: item.status),
                            const SizedBox(width: 10),
                            Text(DateFormat('MMM d, h:mm a').format(item.createdAt)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<FollowUpStatus>(
                          key: ValueKey('${item.id}-${item.followUpStatus.name}'),
                          initialValue: item.followUpStatus,
                          decoration: const InputDecoration(
                            labelText: 'Follow-up status',
                            prefixIcon: Icon(Icons.health_and_safety_outlined),
                          ),
                          items: FollowUpStatus.values
                              .map(
                                (status) => DropdownMenuItem(
                                  value: status,
                                  child: Text(status.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            context.read<CaseBloc>().add(
                              CaseFollowUpStatusChanged(
                                caseId: item.id,
                                followUpStatus: value,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionSwitcher(context),
                const SizedBox(height: 12),
                if (_detailSection == _CaseDetailSection.overview) ...[
                  _buildOverviewCard(context, item),
                  const SizedBox(height: 12),
                ],
                if (_detailSection == _CaseDetailSection.evidence) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Symptoms',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...item.symptoms.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${entry.key.replaceAll('_', ' ')}: ${entry.value ? 'Yes' : 'No'}',
                            ),
                          );
                        }),
                        if (item.temperature != null)
                          Text('Temperature: ${item.temperature!.toStringAsFixed(1)} deg C'),
                        if (item.severity != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Severity: ${(item.severity! * 100).round()}%'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ],
                if (_detailSection == _CaseDetailSection.notes) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Image',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_caseImagePaths(item).isEmpty)
                          const Text('No image attached')
                        else
                          SizedBox(
                            height: 140,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _caseImagePaths(item).length,
                              separatorBuilder: (_, index) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final path = _caseImagePaths(item)[index];
                                return SizedBox(
                                  width: 160,
                                  child: _CaseImageTile(path: path),
                                );
                              },
                            ),
                          ),
                        if (_caseImagePaths(item).length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('${_caseImagePaths(item).length} images attached'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ],
                if (_detailSection == _CaseDetailSection.workflow) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Field notes',
                            prefixIcon: Icon(Icons.note_alt_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: () => context.read<CaseBloc>().add(
                              CaseNotesSaved(
                                caseId: item.id,
                                notes: _notesController.text,
                              ),
                            ),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save Notes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHW-Vet Workflow',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('Role: ${_userRole.toUpperCase()}')),
                            Chip(label: Text('Status: $_workflowStatus')),
                            if (_isTimelineLoading) const Chip(label: Text('Loading timeline...')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final participants = _workflowParticipants;
                            final chw = participants['chwOwner'] is Map
                                ? Map<String, dynamic>.from(participants['chwOwner'] as Map)
                                : <String, dynamic>{};
                            final vet = participants['assignedVet'] is Map
                                ? Map<String, dynamic>.from(participants['assignedVet'] as Map)
                                : <String, dynamic>{};
                            final requestedVet = participants['requestedVet'] is Map
                                ? Map<String, dynamic>.from(participants['requestedVet'] as Map)
                                : <String, dynamic>{};
                            final chwLabel = _participantLabel(chw, empty: 'Unknown CHW');
                            final vetLabel = _participantLabel(vet, empty: 'Unassigned vet');
                            final requestedVetLabel = _participantLabel(requestedVet, empty: 'Not requested');
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Participants',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('CHW / User: $chwLabel'),
                                  const SizedBox(height: 4),
                                  Text('Assigned Vet: $vetLabel'),
                                  const SizedBox(height: 4),
                                  Text('Requested Vet: $requestedVetLabel'),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Standard workflow: one case should have one assigned vet. Use transfer to reassign when needed.',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        if (_userRole == 'vet') ...[
                          if (_hasAssignedVet() && !_currentVetOwnsCase()) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFED7AA)),
                              ),
                              child: Text(
                                'This case is assigned to ${_participantLabel(_assignedVetParticipant(), empty: 'another vet')}. '
                                'You can view the case, but only the assigned vet can chat, review, transfer, or close it.',
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else if (_canCurrentVetClaim()) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF2FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Text(
                                'This case is available for you to accept. Claim it before adding review notes or closing it.',
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _isActionLoading ? null : () => _claimCase(item.id),
                              icon: const Icon(Icons.assignment_ind_outlined),
                              label: const Text('Accept Case'),
                            ),
                            const SizedBox(height: 8),
                          ],
                          TextField(
                            controller: _assessmentController,
                            decoration: const InputDecoration(labelText: 'Assessment (suspected/confirmed/ruled_out)'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _planController,
                            decoration: const InputDecoration(labelText: 'Plan (monitor/isolate/lab_test/treatment)'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _prescriptionController,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(labelText: 'Prescription (drug, dose, route, frequency, duration)'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _followUpDateController,
                            readOnly: true,
                            onTap: _pickFollowUpDate,
                            decoration: const InputDecoration(
                              labelText: 'Follow-up date (YYYY-MM-DD)',
                              suffixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: (_isActionLoading || !_currentVetOwnsCase())
                                ? null
                                : () => _submitVetReview(item.id),
                            icon: const Icon(Icons.medical_services_outlined),
                            label: const Text('Submit Vet Review'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: (_isActionLoading || !_currentVetOwnsCase())
                                ? null
                                : () => _transferCaseToVet(item.id),
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: const Text('Transfer to Another Vet'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: (_isActionLoading || !_currentVetOwnsCase())
                                ? null
                                : () => _closeCase(item.id),
                            icon: const Icon(Icons.task_alt_rounded),
                            label: const Text('Close Case'),
                          ),
                        ] else ...[
                          _TriageStatusBanner(
                            triageStatus: _triageStatus,
                            assignedVetLabel: item.assignedVetLabel,
                            requestedVetLabel: _participantLabel(
                              _requestedVetParticipant(),
                              empty: '',
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _isActionLoading
                                ? null
                                : () => _allowAnyVetAssignment(item.id),
                            icon: const Icon(Icons.groups_outlined),
                            label: const Text('Allow Assignment (Any Vet)'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _isActionLoading ? null : () => _requestSpecificVet(item.id),
                            icon: const Icon(Icons.person_search_outlined),
                            label: const Text('Request Specific Vet'),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Choose a vet by name, email, or location.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                          if (_isActionLoading) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(minHeight: 2),
                          ],
                          if (_triageStatus == 'needs_review' &&
                              item.assignedVetLabel.trim().toLowerCase() == 'unassigned') ...[
                            const SizedBox(height: 8),
                            const Text(
                              'This case is saved but hidden from the shared dashboard queue until you allow assignment or request a specific vet.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (_userRole == 'vet' && !_currentVetOwnsCase())
                                    ? null
                                    : () => _openChatInline(item.id),
                                icon: const Icon(Icons.forum_outlined),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Open Chat'),
                                    if (_chatUnreadCount > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade600,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _chatUnreadCount > 99 ? '99+' : '$_chatUnreadCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ] else if (_timelineMessages.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '(${_timelineMessages.length})',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_timelineReviews.isNotEmpty) ...[
                          Text(
                            'Latest Vet Advice',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final latest = _timelineReviews.last;
                              final created = latest['createdAt']?.toString() ?? '';
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Assessment: ${latest['assessment'] ?? '-'}\n'
                                  'Plan: ${latest['plan'] ?? '-'}\n'
                                  'Prescription: ${latest['prescription'] ?? '-'}\n'
                                  'Follow-up: ${latest['followUpDate'] ?? '-'}\n'
                                  'At: $created',
                                  style: const TextStyle(height: 1.6),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (_timelineReceipts.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Referral & Audit Receipts',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ..._timelineReceipts.reversed.take(8).map((r) {
                            final eventType = (r['eventType'] ?? '').toString();
                            final role = (r['recipientRole'] ?? '').toString();
                            final email = (r['recipientEmail'] ?? '').toString();
                            final delivery = (r['deliveryStatus'] ?? '').toString();
                            final ts = (r['createdAt'] ?? '').toString();
                            final target = email.isEmpty ? role : '$role ($email)';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('[$delivery] $eventType -> $target\n$ts'),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Case Actions',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Quick actions for syncing, reviewing results, sharing, and cleanup.',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 12),
                if (item.status == CaseStatus.pending)
                  FilledButton.icon(
                    onPressed: state.isSyncing
                        ? null
                        : () => context.read<CaseBloc>().add(
                            CaseSyncByIdRequested(item.id),
                          ),
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(state.isSyncing ? 'Syncing...' : 'Sync Now'),
                  ),
                if (item.status == CaseStatus.pending) const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.push('/app/result/${item.id}'),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('View Result'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _confirmDelete(item.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete Case'),
                ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Case status banner (shown to CAHW) ───────────────────────────────────────

class _TriageStatusBanner extends StatelessWidget {
  const _TriageStatusBanner({
    required this.triageStatus,
    required this.assignedVetLabel,
    this.requestedVetLabel = '',
  });

  final String triageStatus;
  final String assignedVetLabel;
  final String requestedVetLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final normalizedAssigned = assignedVetLabel.trim();
    final hasAssignedVet = normalizedAssigned.isNotEmpty && normalizedAssigned.toLowerCase() != 'unassigned';
    final requestedVet = requestedVetLabel.trim();
    final hasRequestedVet = requestedVet.isNotEmpty;
    final vetName = hasAssignedVet ? normalizedAssigned : 'a vet';

    final (icon, label, bgColor, fgColor) = switch (triageStatus) {
      'new' || 'escalated' => (
          Icons.hourglass_top_rounded,
          'Your case is in the vet queue — a vet will pick it up shortly.',
          isDark ? const Color(0xFF2E2200) : const Color(0xFFFFF8E1),
          const Color(0xFFB8860B),
        ),
      'assigned' => (
          Icons.verified_user_rounded,
          'Being reviewed by $vetName. Chat below for updates.',
          isDark ? const Color(0xFF0D2E1A) : const Color(0xFFE8F5EE),
          const Color(0xFF2E7D4F),
        ),
      'needs_review' when hasAssignedVet => (
          Icons.verified_user_rounded,
          'Being reviewed by $vetName. Chat below for updates.',
          isDark ? const Color(0xFF0D2E1A) : const Color(0xFFE8F5EE),
          const Color(0xFF2E7D4F),
        ),
      'needs_review' when hasRequestedVet => (
          Icons.person_search_rounded,
          'Requested for $requestedVet. Waiting for vet acceptance.',
          isDark ? const Color(0xFF1D263A) : const Color(0xFFEAF2FF),
          const Color(0xFF3156A3),
        ),
      'needs_review' => (
          Icons.pause_circle_outline_rounded,
          'Case saved. Allow assignment or request a specific vet to make it visible on the dashboard.',
          isDark ? const Color(0xFF2E2200) : const Color(0xFFFFF8E1),
          const Color(0xFFB8860B),
        ),
      _ => (
          Icons.check_circle_outline_rounded,
          'Case submitted successfully.',
          isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F0F0),
          const Color(0xFF666666),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fgColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fgColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fgColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Case image tile ───────────────────────────────────────────────────────────

/// Displays a single case image from a local file path or a server URL.
class _CaseImageTile extends StatelessWidget {
  const _CaseImageTile({required this.path});

  final String path;

  static Widget _placeholder(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );

  static Widget _broken(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 28)),
      );

  @override
  Widget build(BuildContext context) {
    // Absolute network URL or blob URL (Flutter web image_picker returns blob: URLs)
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          path,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, prog) =>
              prog == null ? child : _placeholder(context),
          errorBuilder: (_, _, _) => _broken(context),
        ),
      );
    }

    // Server-relative path (e.g. /uploads/abc.jpg) — prepend resolved base URL
    if (path.startsWith('/')) {
      return FutureBuilder<String>(
        future: BaseUrlResolver.resolve(),
        builder: (context, snap) {
          if (!snap.hasData) return _placeholder(context);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              '${snap.data}$path',
              fit: BoxFit.cover,
              loadingBuilder: (_, child, prog) =>
                  prog == null ? child : _placeholder(context),
              errorBuilder: (_, _, _) => _broken(context),
            ),
          );
        },
      );
    }

    // Local file path (native platforms)
    return FutureBuilder<Uint8List>(
      future: XFile(path).readAsBytes(),
      builder: (context, snap) {
        if (snap.hasError ||
            (snap.connectionState == ConnectionState.done && !snap.hasData)) {
          return _broken(context);
        }
        if (!snap.hasData) return _placeholder(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _broken(context),
          ),
        );
      },
    );
  }
}
