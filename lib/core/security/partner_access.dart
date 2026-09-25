import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

bool hasVerifiedPartnerClaim(Map<String, dynamic>? claims) =>
    claims?['role'] == 'verified_partner';

Future<bool> currentUserHasVerifiedPartnerClaim({FirebaseAuth? auth}) async {
  try {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult();
    return hasVerifiedPartnerClaim(token.claims);
  } catch (_) {
    return false;
  }
}

class PartnerAccessGate extends StatefulWidget {
  final Widget child;
  final Future<bool> Function()? authorize;

  const PartnerAccessGate({super.key, required this.child, this.authorize});

  @override
  State<PartnerAccessGate> createState() => _PartnerAccessGateState();
}

class _PartnerAccessGateState extends State<PartnerAccessGate> {
  late final Future<bool> _allowed =
      (widget.authorize ?? currentUserHasVerifiedPartnerClaim)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _allowed,
      builder: (context, snapshot) =>
          snapshot.data == true ? widget.child : const SizedBox.shrink(),
    );
  }
}
