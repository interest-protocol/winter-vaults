module winter_vaults::winter_blue_vaults;

use bluefin_spot::{config::GlobalConfig, pool::{Pool, get_liquidity_by_amount}, position::Position};
use integer_mate::i32::{Self, I32};
use interest_access_control::access_control::AdminWitness;
use std::type_name::{Self, TypeName};
use sui::{
    balance::{Self, Balance},
    clock::Clock,
    coin::Coin,
    dynamic_field as df,
    dynamic_object_field as dof
};
use winter_vaults::winter_vault::WINTER_VAULT;

// === Constants ===

const PRECISION: u256 = 1_000_000_000_000_000_000;

// === Struct ===

public struct PositionKey() has copy, drop, store;

public struct FeeBalanceKey<phantom CoinType>() has copy, drop, store;

public struct RewardKey<phantom CoinType>() has copy, drop, store;

public struct RebalanceReceipt {
    vault: address,
    amount_x: u64,
    amount_y: u64,
}

public struct Account has key, store {
    id: UID,
    vault: address,
    liquidity: u128,
    fees_x_debt: u256,
    fees_y_debt: u256,
}

public struct WinterBlueVault has key {
    id: UID,
    pool: address,
    x: TypeName,
    y: TypeName,
    tick_spacing: u32,
    current_tick_index: I32,
    liquidity: u128,
    fees_x_per_liquidity: u256,
    fees_y_per_liquidity: u256,
    reward_infos_length: u64,
}

// === Public Mutative Functions ===

public fun new_account(self: &WinterBlueVault, ctx: &mut TxContext): Account {
    Account {
        id: object::new(ctx),
        vault: self.id.to_address(),
        liquidity: 0,
        fees_x_debt: 0,
        fees_y_debt: 0,
    }
}

// === View Functions ===

public fun is_within_range<X, Y>(self: &WinterBlueVault, pool: &Pool<X, Y>): bool {
    self.assert_pool(pool);

    self.current_tick_index.eq(pool.current_tick_index())
}

public fun balances<X, Y>(self: &WinterBlueVault): (u64, u64) {
    (self.balance<X>().value(), self.balance<Y>().value())
}

public fun rebalance_amounts(receipt: &RebalanceReceipt): (u64, u64) {
    (receipt.amount_x, receipt.amount_y)
}

// === Admin Functions ===

public fun new_vault<X, Y>(
    config: &GlobalConfig,
    pool: &mut Pool<X, Y>,
    _: AdminWitness<WINTER_VAULT>,
    ctx: &mut TxContext,
): WinterBlueVault {
    let current_tick_index = pool.current_tick_index();

    let tick_spacing = pool.get_tick_spacing();

    let (lower_tick_bits, upper_tick_bits) = get_tick_range(current_tick_index, tick_spacing);

    let position = config.open_position(
        pool,
        lower_tick_bits.as_u32(),
        upper_tick_bits.as_u32(),
        ctx,
    );

    let mut vault = WinterBlueVault {
        id: object::new(ctx),
        x: type_name::get<X>(),
        y: type_name::get<Y>(),
        pool: pool.address(),
        tick_spacing,
        current_tick_index,
        reward_infos_length: pool.reward_infos_length(),
        liquidity: 0,
        fees_x_per_liquidity: 0,
        fees_y_per_liquidity: 0,
    };

    dof::add(&mut vault.id, PositionKey(), position);
    df::add(&mut vault.id, FeeBalanceKey<X>(), balance::zero<X>());
    df::add(&mut vault.id, FeeBalanceKey<Y>(), balance::zero<Y>());

    vault
}

public fun share(self: WinterBlueVault) {
    transfer::share_object(self);
}

public fun start_rebalancing<X, Y>(
    self: &mut WinterBlueVault,
    clock: &Clock,
    config: &GlobalConfig,
    pool: &mut Pool<X, Y>,
    _: AdminWitness<WINTER_VAULT>,
    ctx: &mut TxContext,
): (RebalanceReceipt, Coin<X>, Coin<Y>) {
    self.assert_pool(pool);
    self.assert_is_out_of_range(pool);

    let mut position = self.remove_position();

    let (fees_x, fees_y, balance_x, balance_y) = clock.collect_fee(config, pool, &mut position);

    self.balance_mut<X>().join(balance_x);
    self.balance_mut<Y>().join(balance_y);

    self.fees_x_per_liquidity =
        self.fees_x_per_liquidity + (fees_x as u256 * PRECISION / (self.liquidity as u256));
    self.fees_y_per_liquidity =
        self.fees_y_per_liquidity + (fees_y as u256 * PRECISION / (self.liquidity as u256));

    let position_liquidity = position.liquidity();

    let (amount_x, _, balance_x, balance_y) = config.remove_liquidity(
        pool,
        &mut position,
        position_liquidity,
        clock,
    );

    clock.close_position(config, pool, position);

    let pool_current_tick_index = pool.current_tick_index();

    let (lower_tick_bits, upper_tick_bits) = get_tick_range(
        pool_current_tick_index,
        self.tick_spacing,
    );

    let (_, amount_x, amount_y) = get_liquidity_by_amount(
        lower_tick_bits,
        upper_tick_bits,
        pool_current_tick_index,
        pool.current_sqrt_price(),
        amount_x,
        true,
    );

    (
        RebalanceReceipt {
            vault: self.id.to_address(),
            amount_x,
            amount_y,
        },
        balance_x.into_coin(ctx),
        balance_y.into_coin(ctx),
    )
}

// === Private Functions ===

fun pool_address<X, Y>(pool: &Pool<X, Y>): address {
    object::id_address(pool)
}

fun get_tick_range(current_tick_index: I32, tick_spacing: u32): (I32, I32) {
    let tick_spacing_i32 = i32::from(tick_spacing);
    let lower_tick_bits = current_tick_index.sub(tick_spacing_i32);
    let upper_tick_bits = current_tick_index.add(tick_spacing_i32);

    (lower_tick_bits, upper_tick_bits)
}

fun position(self: &WinterBlueVault): &Position {
    dof::borrow(&self.id, PositionKey())
}

fun balance<CoinType>(self: &WinterBlueVault): &Balance<CoinType> {
    df::borrow(&self.id, FeeBalanceKey<CoinType>())
}

fun position_mut(self: &mut WinterBlueVault): &mut Position {
    dof::borrow_mut(&mut self.id, PositionKey())
}

fun balance_mut<CoinType>(self: &mut WinterBlueVault): &mut Balance<CoinType> {
    df::borrow_mut(&mut self.id, FeeBalanceKey<CoinType>())
}

fun remove_position(self: &mut WinterBlueVault): Position {
    dof::remove(&mut self.id, PositionKey())
}

// === Assertions ===

fun assert_pool<X, Y>(self: &WinterBlueVault, pool: &Pool<X, Y>) {
    assert!(self.pool == pool.address());
}

fun assert_is_out_of_range<X, Y>(self: &WinterBlueVault, pool: &Pool<X, Y>) {
    assert!(!self.is_within_range(pool));
}

// === Aliases ===

use fun pool_address as Pool.address;
use fun bluefin_spot::pool::collect_fee as Clock.collect_fee;
use fun bluefin_spot::pool::close_position_v2 as Clock.close_position;
use fun bluefin_spot::pool::open_position as GlobalConfig.open_position;
use fun bluefin_spot::pool::remove_liquidity as GlobalConfig.remove_liquidity;
