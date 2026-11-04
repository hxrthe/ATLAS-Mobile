import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';

class MyIssueReportsScreen extends StatefulWidget {
  const MyIssueReportsScreen({super.key});

  @override
  State<MyIssueReportsScreen> createState() => _MyIssueReportsScreenState();
}

class _MyIssueReportsScreenState extends State<MyIssueReportsScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final response = await ApiClient().dio.get('auth/support-reports/');
      final raw = response.data is Map ? response.data['reports'] : null;
      final rows = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            rows.add(Map<String, dynamic>.from(item));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _reports = rows;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _reports.isEmpty) {
          _error = friendlyError(
            e,
            fallback: 'Could not load your reports. Check your internet and try again.',
          );
        }
      });
    }
  }

  String _statusLabel(Map<String, dynamic> row) {
    if (row['is_resolved'] == true) return 'Resolved';
    if (row['status'] == 'with_superadmin') return 'With ATLAS team';
    return 'With campus admin';
  }

  Color _statusColor(Map<String, dynamic> row, AtlasColors colors) {
    if (row['is_resolved'] == true) return colors.correct;
    return colors.primary;
  }

  String _when(dynamic value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return '';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    return Scaffold(
      backgroundColor: colors.scaffold,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My issue reports',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: colors.primary,
        onRefresh: () => _load(),
        child: _loading && _reports.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error.isNotEmpty && _reports.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(_error, style: TextStyle(color: colors.primary)),
                    ],
                  )
                : _reports.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            'You have not sent any issue reports yet.',
                            style: TextStyle(color: colors.textSecondary, height: 1.45),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final row = _reports[index];
                          final resolved = row['is_resolved'] == true;
                          final statusColor = _statusColor(row, colors);
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _statusLabel(row),
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _when(row['created_at']),
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  (row['message'] ?? '').toString(),
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    height: 1.45,
                                  ),
                                ),
                                if (resolved && row['resolved_at'] != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Resolved ${_when(row['resolved_at'])}',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
