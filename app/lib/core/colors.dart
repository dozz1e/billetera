import 'package:flutter/material.dart';

import '../models/transaction.dart';

/// Fixed semantic colors that carry meaning across the app (transaction
/// type, account type, goal state), independent of the Material color
/// scheme generated from theme.dart's seed. Tuned for contrast against the
/// dark scaffold (#121212) and card surface (#1E1E1E).
class AppColors {
  const AppColors._();

  static const ingreso = Color(0xFF4CD97B);
  static const gasto = Color(0xFFFF6B6B);
  static const transferencia = Color(0xFFB388FF);

  static const metaPausado = Color(0xFFFFB74D);
  static const metaAlcanzado = Color(0xFF4CD97B);

  static const cuentaEfectivo = Color(0xFF4CD97B);
  static const cuentaCredito = Color(0xFFB388FF);
  static const cuentaBilleteraDigital = Color(0xFF4DD0E1);

  static const chartPalette = [
    Color(0xFF5B9DF9),
    Color(0xFFFFB74D),
    Color(0xFF4CD97B),
    Color(0xFFFF6B6B),
    Color(0xFFB388FF),
    Color(0xFF4DD0E1),
    Color(0xFFF06292),
    Color(0xFFFFD54F),
  ];
}

class TransactionVisual {
  const TransactionVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}

TransactionVisual transactionVisual(TransactionType tipo) => switch (tipo) {
  TransactionType.ingreso => const TransactionVisual(
    Icons.arrow_downward_rounded,
    AppColors.ingreso,
  ),
  TransactionType.gasto => const TransactionVisual(
    Icons.arrow_upward_rounded,
    AppColors.gasto,
  ),
  TransactionType.transferencia => const TransactionVisual(
    Icons.swap_horiz_rounded,
    AppColors.transferencia,
  ),
};

class AccountVisual {
  const AccountVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// `tipo` is one of 'efectivo' | 'banco' | 'credito' | 'billetera_digital'.
/// `banco` uses [primary] so the most common account type stays tied to the
/// app's brand color rather than a fifth fixed hue.
AccountVisual accountVisual(String tipo, Color primary) => switch (tipo) {
  'efectivo' => const AccountVisual(
    Icons.payments_outlined,
    AppColors.cuentaEfectivo,
  ),
  'credito' => const AccountVisual(
    Icons.credit_card_outlined,
    AppColors.cuentaCredito,
  ),
  'billetera_digital' => const AccountVisual(
    Icons.account_balance_wallet_outlined,
    AppColors.cuentaBilleteraDigital,
  ),
  _ => AccountVisual(Icons.account_balance_outlined, primary),
};

class GoalVisual {
  const GoalVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// `estado` is one of 'activo' | 'pausado' | 'alcanzado'.
GoalVisual goalVisual(String estado, Color primary) => switch (estado) {
  'pausado' => const GoalVisual(
    Icons.pause_circle_outline_rounded,
    AppColors.metaPausado,
  ),
  'alcanzado' => const GoalVisual(
    Icons.emoji_events_rounded,
    AppColors.metaAlcanzado,
  ),
  _ => GoalVisual(Icons.flag_rounded, primary),
};

class DebtVisual {
  const DebtVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// `estado` is one of 'pendiente' | 'pagada'.
DebtVisual debtVisual(String estado) => switch (estado) {
  'pagada' => const DebtVisual(
    Icons.check_circle_outline_rounded,
    AppColors.metaAlcanzado,
  ),
  _ => const DebtVisual(Icons.schedule_rounded, AppColors.metaPausado),
};
