import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

bool hasVerifiedAdminClaim(Map<String, dynamic>? claims) {
  if (claims?['admin'] != true) return false;
  return const {
    'standard',
    'verified_partner',
    'professional',
    'enterprise',
  }.contains(claims?['role']);
}

Future<bool> currentUserHasAdminClaim({FirebaseAuth? auth}) async {
  try {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult();
    return hasVerifiedAdminClaim(token.claims);
  } catch (_) {
    return false;
  }
}

class AdminAccessGate extends StatelessWidget {
  final Widget child;
  final Future<bool> Function()? hasAccess;

  const AdminAccessGate({super.key, required this.child, this.hasAccess});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: (hasAccess ?? currentUserHasAdminClaim)(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data != true) {
          return const Center(
            child: Text(
              'ADMIN ACCESS DENIED',
              style: TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}
