module winter_vaults::winter_vault;

use interest_access_control::access_control;

// === Structs ===

public struct WINTER_VAULT() has drop;

// === Initialization ===

fun init(otw: WINTER_VAULT, ctx: &mut TxContext) {
    let acl = access_control::default(&otw, ctx);

    transfer::public_share_object(acl);
}
