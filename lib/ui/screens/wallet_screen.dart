import 'package:flutter/material.dart';

import '../../domain/coupon.dart';
import '../../domain/credit_rules.dart';
import '../../domain/focus_clock.dart';
import '../../domain/session_mode.dart';
import '../../domain/session_record.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import '../widgets/focus_card.dart';
import '../widgets/glass_card.dart';

/// The balance, what it buys, and what earned it.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    final coupons = wallet.activeCoupons;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus card'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reset progress',
            onPressed: () => _confirmReset(context, wallet),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.8, -0.9),
            radius: 1.5,
            colors: [Color(0xFF3A1230), FocusPalette.ink],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: FocusCard(credits: wallet.balance),
              ),
            ),
            const SizedBox(height: 20),
            GlassCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Stat(label: 'STREAK', value: '${wallet.streakDays}d'),
                  _Stat(label: 'SESSIONS', value: '${wallet.sessionsCompleted}'),
                  _Stat(label: 'FOCUSED', value: formatSpan(wallet.lifetimeFocus)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('SPEND CREDITS', style: kEyebrow),
            const SizedBox(height: 11),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final amount in CreditRules.redemptionOptions)
                  _RedeemChip(
                    amount: amount,
                    affordable: wallet.canAfford(amount),
                    onTap: () => _redeem(context, wallet, amount),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'One credit is one minute. FocusAR cannot switch off the rest of '
              'your phone, so a coupon is a budget you hold yourself — it '
              'lapses after ${Coupon.validity.inHours} hours.',
              style: const TextStyle(color: Colors.white38, fontSize: 12.5, height: 1.45),
            ),
            if (coupons.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('READY TO USE', style: kEyebrow),
              const SizedBox(height: 11),
              for (final coupon in coupons)
                _CouponTile(
                  coupon: coupon,
                  onSpend: () => wallet.spend(coupon),
                ),
            ],
            const SizedBox(height: 24),
            const Text('RECENT SESSIONS', style: kEyebrow),
            const SizedBox(height: 11),
            if (wallet.history.isEmpty)
              const Text(
                'Nothing here yet. Your finished sessions will show up as you '
                'bank them.',
                style: TextStyle(color: Colors.white38, fontSize: 13.5, height: 1.45),
              )
            else
              for (final record in wallet.history) _HistoryTile(record: record),
          ],
        ),
      ),
    );
  }

  Future<void> _redeem(
    BuildContext context,
    WalletController wallet,
    Duration amount,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final coupon = await wallet.redeem(amount);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          coupon == null
              ? 'Not enough credits yet. ${CreditRules.formatCredits(CreditRules.costOf(amount) - wallet.balance)} to go.'
              : '${formatSpan(amount)} unlocked. Spend it before it lapses.',
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WalletController wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text(
          'This clears your balance, your streak, and every saved session. '
          'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await wallet.reset();
  }
}

class _RedeemChip extends StatelessWidget {
  const _RedeemChip({
    required this.amount,
    required this.affordable,
    required this.onTap,
  });

  final Duration amount;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: affordable ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: affordable
              ? FocusPalette.card.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: affordable
                ? FocusPalette.card.withValues(alpha: 0.55)
                : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatSpan(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: affordable ? Colors.white : Colors.white38,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${CreditRules.formatCredits(CreditRules.costOf(amount))} credits',
              style: TextStyle(
                fontSize: 11.5,
                color: affordable ? Colors.white70 : Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  const _CouponTile({required this.coupon, required this.onSpend});

  final Coupon coupon;
  final VoidCallback onSpend;

  @override
  Widget build(BuildContext context) {
    final left = coupon.remainingValidity(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FocusPalette.card.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_activity_rounded, color: FocusPalette.card),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatSpan(coupon.amount)} of screen time',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lapses in ${formatSpan(left)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onSpend, child: const Text('Mark used')),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Icon(
            record.clean ? Icons.verified_rounded : Icons.history_rounded,
            size: 19,
            color: record.clean ? FocusPalette.done : Colors.white38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatSpan(record.focused)} · ${record.mode.label}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  record.interruptions == 0
                      ? 'No pick-ups'
                      : '${record.interruptions} pick-up'
                          '${record.interruptions == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '+${record.creditsEarned.toStringAsFixed(1)}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: FocusPalette.card,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, style: kEyebrow.copyWith(fontSize: 10)),
      ],
    );
  }
}
