import 'package:flutter/material.dart';

/// Circular profile photo from the signed-in email/Google account.
/// Falls back to initials when no photo URL is available.
class UserAvatar extends StatefulWidget {
  final String? photoUrl;
  final String name;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  const UserAvatar({
    super.key,
    this.photoUrl,
    required this.name,
    this.radius = 24,
    this.backgroundColor = const Color(0x1A8B1515),
    this.foregroundColor = const Color(0xFF8B1515),
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _loadFailed = false;

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _loadFailed = false;
    }
  }

  String get _initials {
    final parts = widget.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'F';
    String initial(String value) => value.substring(0, 1).toUpperCase();
    if (parts.length == 1) return initial(parts.first);
    return '${initial(parts.first)}${initial(parts.last)}';
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.photoUrl?.trim() ?? '';
    final hasPhoto = url.isNotEmpty && !_loadFailed;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      backgroundImage: hasPhoto ? NetworkImage(url) : null,
      onBackgroundImageError: hasPhoto
          ? (_, _) {
              if (mounted) setState(() => _loadFailed = true);
            }
          : null,
      child: hasPhoto
          ? null
          : Text(
              _initials,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: widget.radius * 0.7,
                color: widget.foregroundColor,
              ),
            ),
    );
  }
}
