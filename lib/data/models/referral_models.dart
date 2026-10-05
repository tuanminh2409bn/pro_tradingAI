import 'package:equatable/equatable.dart';

class ReferralStats extends Equatable {
  final double totalEarnings;
  final int f1Count;
  final int f2Count;
  final String referralLink;
  final String referralCode;
  final String currency;
  final int? registeredInviteCount;
  final bool isAvailable;

  const ReferralStats({
    required this.totalEarnings,
    required this.f1Count,
    required this.f2Count,
    required this.referralLink,
    this.referralCode = '',
    this.currency = 'USD',
    this.registeredInviteCount,
    this.isAvailable = true,
  });

  const ReferralStats.unavailable()
    : totalEarnings = 0,
      f1Count = 0,
      f2Count = 0,
      referralLink = '',
      referralCode = '',
      currency = '',
      registeredInviteCount = null,
      isAvailable = false;

  factory ReferralStats.fromJson(Map<String, dynamic> data) {
    final earnings = data['totalEarnings'];
    final f1 = data['f1Count'];
    final f2 = data['f2Count'];
    final currency = data['currency'];
    final verified =
        data['ledgerStatus'] == 'VERIFIED' &&
        earnings is num &&
        earnings.isFinite &&
        earnings >= 0 &&
        f1 is int &&
        f1 >= 0 &&
        f2 is int &&
        f2 >= 0 &&
        currency is String &&
        RegExp(r'^[A-Z]{3}$').hasMatch(currency);
    return ReferralStats(
      totalEarnings: verified ? earnings.toDouble() : 0,
      f1Count: verified ? f1 : 0,
      f2Count: verified ? f2 : 0,
      currency: verified ? currency : '',
      referralCode: data['referralCode'] is String
          ? data['referralCode'] as String
          : '',
      referralLink: data['referralLink'] is String
          ? data['referralLink'] as String
          : '',
      isAvailable: verified,
      registeredInviteCount:
          data['registeredInviteCount'] is int &&
              (data['registeredInviteCount'] as int) >= 0
          ? data['registeredInviteCount'] as int
          : null,
    );
  }

  ReferralIdentity? get identity {
    try {
      return ReferralIdentity.fromServerLink(
        code: referralCode,
        link: referralLink,
      );
    } on ArgumentError {
      return null;
    }
  }

  bool get hasReferralLink => identity != null;

  @override
  List<Object?> get props => [
    totalEarnings,
    f1Count,
    f2Count,
    referralLink,
    referralCode,
    currency,
    registeredInviteCount,
    isAvailable,
  ];
}

class MemberNode extends Equatable {
  final String id;
  final String name;
  final String avatarUrl;
  final double earningsContribution;
  final String level; // 'F1', 'F2'

  const MemberNode({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.earningsContribution,
    required this.level,
  });

  @override
  List<Object?> get props => [id, name, level];
}

class RewardTransaction extends Equatable {
  final String title;
  final DateTime date;
  final double amount;
  final String status; // 'COMPLETED', 'PROCESSED'
  final String type; // 'COMMISSION', 'BONUS', 'WITHDRAWAL'
  final int? amountMinor;

  const RewardTransaction({
    required this.title,
    required this.date,
    required this.amount,
    required this.status,
    required this.type,
    this.amountMinor,
  });

  static RewardTransaction? fromLedger(
    Map<String, dynamic> data,
    DateTime? date,
  ) {
    final minor = data['amountMinor'];
    final kind = data['kind'];
    const kinds = {'CREDIT', 'REVERSAL', 'HOLD', 'RELEASE', 'PAYOUT'};
    if (data['currency'] != 'USD' ||
        date == null ||
        minor is! int ||
        minor <= 0 ||
        minor > 1000000000000 ||
        !kinds.contains(kind)) {
      return null;
    }
    final signed = (kind == 'REVERSAL' || kind == 'HOLD' || kind == 'PAYOUT')
        ? -minor
        : minor;
    return RewardTransaction(
      title: 'referral_ledger_${(kind as String).toLowerCase()}',
      date: date,
      amount: signed / 100,
      amountMinor: signed,
      status: 'referral_ledger_posted',
      type: kind,
    );
  }

  @override
  List<Object?> get props => [title, date, amount, status, type, amountMinor];
}

class ReferralIdentity extends Equatable {
  final String code;
  final Uri uri;

  const ReferralIdentity._({required this.code, required this.uri});

  factory ReferralIdentity.fromServerLink({
    required String code,
    required String link,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(code)) {
      throw ArgumentError('Invalid server-issued referral code');
    }
    final canonical = Uri.https('protrading-ai-2026.web.app', '/', {
      'ref': code,
    });
    if (link != canonical.toString()) {
      throw ArgumentError('Invalid referral origin or payload');
    }
    return ReferralIdentity._(code: code, uri: canonical);
  }

  factory ReferralIdentity.fromServerIssuedCode({
    required Uri baseUri,
    required String code,
  }) {
    final normalizedCode = code.trim();
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        baseUri.userInfo.isNotEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(normalizedCode)) {
      throw ArgumentError('Invalid referral origin or server-issued code');
    }
    final segments = [
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      normalizedCode,
    ];
    return ReferralIdentity._(
      code: normalizedCode,
      uri: baseUri.replace(pathSegments: segments),
    );
  }

  String get qrPayload => uri.toString();

  @override
  List<Object?> get props => [code, uri];
}

enum MarketingAssetType { banner, video }

enum ReferralRegistrationStatus { recorded, restored, notEligible }

enum MarketingKitStatus { readyForRenderer, unavailable }

class MarketingAssetTemplate extends Equatable {
  static const referralCodeToken = '{{REFERRAL_CODE}}';

  final String id;
  final MarketingAssetType type;
  final Uri sourceUri;
  final String licenseReference;
  final bool isApproved;
  final String overlayTemplate;

  const MarketingAssetTemplate({
    required this.id,
    required this.type,
    required this.sourceUri,
    required this.licenseReference,
    required this.isApproved,
    required this.overlayTemplate,
  });

  @override
  List<Object?> get props => [
    id,
    type,
    sourceUri,
    licenseReference,
    isApproved,
    overlayTemplate,
  ];
}

class PersonalizedMarketingAsset extends Equatable {
  final String templateId;
  final MarketingAssetType type;
  final Uri sourceUri;
  final String licenseReference;
  final String referralCode;
  final String overlayText;

  const PersonalizedMarketingAsset({
    required this.templateId,
    required this.type,
    required this.sourceUri,
    required this.licenseReference,
    required this.referralCode,
    required this.overlayText,
  });

  @override
  List<Object?> get props => [
    templateId,
    type,
    sourceUri,
    licenseReference,
    referralCode,
    overlayText,
  ];
}

class MarketingKitPreparation extends Equatable {
  final MarketingKitStatus status;
  final List<PersonalizedMarketingAsset> assets;
  final String? unavailableReason;

  MarketingKitPreparation._({
    required this.status,
    required List<PersonalizedMarketingAsset> assets,
    required this.unavailableReason,
  }) : assets = List<PersonalizedMarketingAsset>.unmodifiable(assets);

  factory MarketingKitPreparation.prepare({
    required ReferralIdentity identity,
    required Iterable<MarketingAssetTemplate> templates,
  }) {
    final approved = templates.where(
      (template) =>
          template.isApproved && template.licenseReference.trim().isNotEmpty,
    );
    final seenIds = <String>{};
    final personalized = <PersonalizedMarketingAsset>[];
    for (final template in approved) {
      final id = template.id.trim();
      if (id.isEmpty ||
          !seenIds.add(id) ||
          template.sourceUri.scheme != 'https' ||
          template.sourceUri.host.isEmpty ||
          !template.overlayTemplate.contains(
            MarketingAssetTemplate.referralCodeToken,
          )) {
        throw const FormatException('Invalid approved marketing asset');
      }
      personalized.add(
        PersonalizedMarketingAsset(
          templateId: id,
          type: template.type,
          sourceUri: template.sourceUri,
          licenseReference: template.licenseReference.trim(),
          referralCode: identity.code,
          overlayText: template.overlayTemplate.replaceAll(
            MarketingAssetTemplate.referralCodeToken,
            identity.code,
          ),
        ),
      );
    }
    if (personalized.isEmpty) {
      return MarketingKitPreparation._(
        status: MarketingKitStatus.unavailable,
        assets: const [],
        unavailableReason: 'no_approved_marketing_assets',
      );
    }
    return MarketingKitPreparation._(
      status: MarketingKitStatus.readyForRenderer,
      assets: personalized,
      unavailableReason: null,
    );
  }

  @override
  List<Object?> get props => [status, assets, unavailableReason];
}

enum LedgerDirection { credit, debit }

enum LedgerEntryState { pending, settled, reversed }

class ReferralLedgerEntry extends Equatable {
  final String id;
  final double amount;
  final String currency;
  final LedgerDirection direction;
  final LedgerEntryState state;

  const ReferralLedgerEntry({
    required this.id,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.state,
  });

  @override
  List<Object?> get props => [id, amount, currency, direction, state];
}

class ReferralLedger extends Equatable {
  final List<ReferralLedgerEntry> entries;
  final String currency;
  final double availableBalance;

  factory ReferralLedger(Iterable<ReferralLedgerEntry> sourceEntries) {
    final entries = sourceEntries.toList(growable: false);
    if (entries.isEmpty) {
      throw ArgumentError('Referral ledger requires authoritative entries');
    }
    final ids = <String>{};
    String? currency;
    var availableBalance = 0.0;
    for (final entry in entries) {
      final id = entry.id.trim();
      final entryCurrency = entry.currency.trim().toUpperCase();
      if (id.isEmpty ||
          !ids.add(id) ||
          !entry.amount.isFinite ||
          entry.amount <= 0 ||
          entryCurrency.isEmpty ||
          (currency != null && currency != entryCurrency)) {
        throw ArgumentError('Invalid or inconsistent referral ledger entry');
      }
      currency ??= entryCurrency;
      if (entry.state == LedgerEntryState.settled) {
        availableBalance += entry.direction == LedgerDirection.credit
            ? entry.amount
            : -entry.amount;
      }
    }
    if (availableBalance < 0) {
      throw const FormatException('Referral ledger has a negative balance');
    }
    return ReferralLedger._(
      entries: entries,
      currency: currency!,
      availableBalance: availableBalance,
    );
  }

  ReferralLedger._({
    required List<ReferralLedgerEntry> entries,
    required this.currency,
    required this.availableBalance,
  }) : entries = List<ReferralLedgerEntry>.unmodifiable(entries);

  @override
  List<Object?> get props => [entries, currency, availableBalance];
}

class WithdrawalPolicy extends Equatable {
  final String currency;
  final double minimumAmount;

  const WithdrawalPolicy({required this.currency, required this.minimumAmount});

  @override
  List<Object?> get props => [currency, minimumAmount];
}

enum WithdrawalStatus { pending, approved, rejected }

enum WithdrawalActorRole { user, superAdmin }

class WithdrawalAuditEntry extends Equatable {
  final WithdrawalStatus from;
  final WithdrawalStatus to;
  final String actorUid;
  final DateTime occurredAt;
  final String? reason;

  const WithdrawalAuditEntry({
    required this.from,
    required this.to,
    required this.actorUid,
    required this.occurredAt,
    required this.reason,
  });

  @override
  List<Object?> get props => [from, to, actorUid, occurredAt, reason];
}

class WithdrawalRequest extends Equatable {
  final String id;
  final String ownerUid;
  final double amount;
  final String currency;
  final DateTime requestedAt;
  final WithdrawalStatus status;
  final int version;
  final List<WithdrawalAuditEntry> auditTrail;

  WithdrawalRequest._({
    required this.id,
    required this.ownerUid,
    required this.amount,
    required this.currency,
    required this.requestedAt,
    required this.status,
    required this.version,
    required List<WithdrawalAuditEntry> auditTrail,
  }) : auditTrail = List<WithdrawalAuditEntry>.unmodifiable(auditTrail);

  factory WithdrawalRequest.create({
    required String id,
    required String ownerUid,
    required double amount,
    required double availableBalance,
    required WithdrawalPolicy policy,
    required DateTime requestedAt,
  }) {
    final currency = policy.currency.trim().toUpperCase();
    if (id.trim().isEmpty ||
        ownerUid.trim().isEmpty ||
        currency.isEmpty ||
        !amount.isFinite ||
        amount <= 0 ||
        !availableBalance.isFinite ||
        availableBalance < 0 ||
        !policy.minimumAmount.isFinite ||
        policy.minimumAmount <= 0 ||
        amount < policy.minimumAmount) {
      throw ArgumentError('Invalid withdrawal request or policy');
    }
    if (amount > availableBalance) {
      throw StateError('Withdrawal exceeds the available balance');
    }
    return WithdrawalRequest._(
      id: id.trim(),
      ownerUid: ownerUid.trim(),
      amount: amount,
      currency: currency,
      requestedAt: requestedAt.toUtc(),
      status: WithdrawalStatus.pending,
      version: 0,
      auditTrail: const [],
    );
  }

  WithdrawalRequest decide({
    required WithdrawalStatus decision,
    required String actorUid,
    required WithdrawalActorRole actorRole,
    required int expectedVersion,
    required DateTime decidedAt,
    String? reason,
  }) {
    if (status != WithdrawalStatus.pending || expectedVersion != version) {
      throw StateError('Withdrawal is stale or already decided');
    }
    if (actorRole != WithdrawalActorRole.superAdmin ||
        actorUid.trim().isEmpty) {
      throw StateError('Only Super Admin can decide a withdrawal');
    }
    if (decision == WithdrawalStatus.pending ||
        decidedAt.toUtc().isBefore(requestedAt) ||
        (decision == WithdrawalStatus.rejected &&
            (reason == null || reason.trim().isEmpty))) {
      throw ArgumentError('Invalid withdrawal decision');
    }
    final audit = WithdrawalAuditEntry(
      from: status,
      to: decision,
      actorUid: actorUid.trim(),
      occurredAt: decidedAt.toUtc(),
      reason: reason?.trim(),
    );
    return WithdrawalRequest._(
      id: id,
      ownerUid: ownerUid,
      amount: amount,
      currency: currency,
      requestedAt: requestedAt,
      status: decision,
      version: version + 1,
      auditTrail: [...auditTrail, audit],
    );
  }

  @override
  List<Object?> get props => [
    id,
    ownerUid,
    amount,
    currency,
    requestedAt,
    status,
    version,
    auditTrail,
  ];
}
