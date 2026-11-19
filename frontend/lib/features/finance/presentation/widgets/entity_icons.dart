import 'package:flutter/material.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';

const categoryIcons = [
  Icons.restaurant_outlined,
  Icons.water_drop_outlined,
  Icons.home_outlined,
  Icons.checkroom_outlined,
  Icons.directions_car_outlined,
  Icons.medical_services_outlined,
  Icons.child_care_outlined,
  Icons.account_balance_wallet_outlined,
  Icons.card_giftcard_outlined,
  Icons.trending_up,
  Icons.savings_outlined,
  Icons.business_center_outlined,
  Icons.volunteer_activism_outlined,
  Icons.category_outlined,
  Icons.local_cafe_outlined,
  Icons.shopping_cart_outlined,
  Icons.school_outlined,
  Icons.sports_esports_outlined,
  Icons.flight_outlined,
  Icons.pets_outlined,
  Icons.phone_iphone_outlined,
  Icons.receipt_long_outlined,
  Icons.fitness_center_outlined,
  Icons.attach_money,
];

extension CategoryIcon on MoneyCategory {
  IconData get icon => categoryIcons[symbol.clamp(0, categoryIcons.length - 1)];
}

const walletIcons = [
  Icons.account_balance_wallet_outlined,
  Icons.payments_outlined,
  Icons.credit_card,
  Icons.account_balance_outlined,
  Icons.savings_outlined,
  Icons.diamond_outlined,
  Icons.flight_outlined,
  Icons.home_outlined,
  Icons.directions_car_outlined,
  Icons.school_outlined,
  Icons.medical_services_outlined,
  Icons.card_giftcard_outlined,
];

extension WalletIcon on MoneyWallet {
  IconData get icon => switch (symbol) {
        final int i when i >= 0 && i < walletIcons.length => walletIcons[i],
        _ => savings ? Icons.savings_outlined : Icons.account_balance_wallet_outlined,
      };
}
