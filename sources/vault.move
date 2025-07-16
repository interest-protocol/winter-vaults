module winter_vaults::winter_blue_vaults;

use bluefin_spot::{config::GlobalConfig, pool::Pool};
use integer_mate::i32::{Self, I32};
use interest_access_control::access_control::AdminWitness;
use std::type_name::{Self, TypeName};
use sui::dynamic_object_field as dof;
use winter_vaults::winter_vault::WINTER_VAULT;

// === Struct ===

public struct PositionKey() has copy, drop, store;

public struct RewardKey() has copy, drop, store;

public struct Account has key, store {
    id: UID,
    liquidity: u128,
}

public struct WinterBlueVault has key {
    id: UID,
    x: TypeName,
    y: TypeName,
    pool: address,
    tick_spacing: u32,
    total_liquidity: u128,
    current_tick_index: I32,
    reward_infos_length: u64,
}

// === Public Mutative Functions ===

public fun new_account(ctx: &mut TxContext): Account {
    Account {
        id: object::new(ctx),
        liquidity: 0,
    }
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
        pool: object::id_address(pool),
        tick_spacing,
        current_tick_index,
        reward_infos_length: pool.reward_infos_length(),
        total_liquidity: 0,
    };

    dof::add(&mut vault.id, PositionKey(), position);

    vault
}

public fun share(self: WinterBlueVault) {
    transfer::share_object(self);
}

// === Private Functions ===

fun get_tick_range(current_tick_index: I32, tick_spacing: u32): (I32, I32) {
    let tick_spacing_i32 = i32::from(tick_spacing);
    let lower_tick_bits = current_tick_index.sub(tick_spacing_i32);
    let upper_tick_bits = current_tick_index.add(tick_spacing_i32);

    (lower_tick_bits, upper_tick_bits)
}

// === Aliases ===

use fun bluefin_spot::pool::open_position as GlobalConfig.open_position;
