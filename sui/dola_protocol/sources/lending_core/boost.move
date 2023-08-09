module dola_protocol::boost {
    use sui::balance::Balance;
    use sui::object::{UID, ID};
    use sui::table::Table;
    use sui::coin::Coin;
    use sui::tx_context::TxContext;
    use sui::coin;
    use sui::transfer;
    use sui::object;
    use sui::table;
    use sui::tx_context;
    use sui::balance;
    use sui::clock::Clock;
    use dola_protocol::lending_core_storage::Storage;
    use dola_protocol::lending_core_storage;
    use dola_protocol::ray_math;
    use dola_protocol::lending_codec;
    use dola_protocol::genesis::GovernanceGenesis;
    use dola_protocol::genesis;
    use dola_protocol::user_manager;
    use dola_protocol::user_manager::UserManagerInfo;
    use dola_protocol::dola_address;

    friend dola_protocol::lending_logic;

    /// Errors

    const EINVALID_TIME: u64 = 0;

    const ENOT_ONWER: u64 = 1;

    const EINVALID_ACTION: u64 = 2;

    const EINVALID_POOL: u64 = 3;

    const ENOT_ASSOCIATE_POOL: u64 = 4;

    struct UserReward has store, drop {
        // Reward index when `acc_user_index` was last updated
        last_update_reward_index: u256,
        // The unclaimed reward balance
        balance: u256
    }

    struct PoolReward has key, store {
        id: UID,
        associate_pool_reward_balance: ID,
        owner: address,
        start_time: u256,
        end_time: u256,
        // [math::ray]
        reward_index: u256,
        reward_action: u8,
        initial_balance: u64,
        dola_pool_id: u16,
        last_update_time: u256,
        // [math::ray]
        reward_per_second: u256,
        user_reward: Table<u64, UserReward>,
    }

    struct PoolRewardBalance<phantom X> has key {
        id: UID,
        associate_pool_reward: ID,
        balance: Balance<X>
    }

    fun update_pool_reward(
        reward_pool: &mut PoolReward,
        storage: &mut Storage,
        dola_pool_id: u16,
        reward_action: u8,
        clock: &Clock,
    ) {
        let current_timestamp = ray_math::min(lending_core_storage::get_timestamp(clock), reward_pool.end_time);

        let total_scaled_balance;
        if (reward_action == lending_codec::get_supply_type()) {
            total_scaled_balance = lending_core_storage::get_otoken_scaled_total_supply(storage, dola_pool_id);
        }else if (reward_action == lending_codec::get_borrow_type()) {
            total_scaled_balance = lending_core_storage::get_dtoken_scaled_total_supply(storage, dola_pool_id);
        }else {
            abort EINVALID_ACTION
        };

        if (total_scaled_balance == 0) {
            reward_pool.reward_index = 0;
        }else {
            reward_pool.reward_index = reward_pool.reward_index + reward_pool.reward_per_second * (current_timestamp - reward_pool.last_update_time) / total_scaled_balance
        };

        reward_pool.last_update_time = current_timestamp;
    }

    fun update_user_reward(
        reward_pool: &mut PoolReward,
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        reward_action: u8,
    ) {
        let user_scaled_balance;
        if (reward_action == lending_codec::get_supply_type()) {
            user_scaled_balance = lending_core_storage::get_user_scaled_otoken(storage, dola_user_id, dola_pool_id);
        }else if (reward_action == lending_codec::get_borrow_type()) {
            user_scaled_balance = lending_core_storage::get_user_scaled_dtoken(storage, dola_user_id, dola_pool_id);
        }else {
            abort EINVALID_ACTION
        };
        if (!table::contains(&reward_pool.user_reward, dola_user_id)) {
            table::add(&mut reward_pool.user_reward, dola_user_id, UserReward {
                last_update_reward_index: 0,
                balance: 0
            })
        };
        let user_reward = table::borrow_mut(&mut reward_pool.user_reward, dola_user_id);
        let delta_index = reward_pool.reward_index - user_reward.last_update_reward_index;
        user_reward.balance = user_reward.balance + ray_math::ray_mul(delta_index, user_scaled_balance);
        user_reward.last_update_reward_index = reward_pool.reward_index;
    }

    public(friend) fun create_reward_pool<X>(
        start_time: u256,
        end_time: u256,
        reward: Coin<X>,
        dola_pool_id: u16,
        reward_action: u8,
        ctx: &mut TxContext
    ): PoolReward {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(reward_action < 2, EINVALID_ACTION);
        let initial_balance = coin::value(&reward);
        let reward_per_second = ray_math::ray_div((initial_balance as u256), end_time - start_time);
        let pool_reward_uid = object::new(ctx);
        let associate_pool_reward = object::uid_to_inner(&pool_reward_uid);
        let pool_reward_balance_uid = object::new(ctx);
        let associate_pool_reward_balance = object::uid_to_inner(&pool_reward_balance_uid);
        transfer::share_object(PoolRewardBalance<X> {
            id: pool_reward_balance_uid,
            associate_pool_reward,
            balance: coin::into_balance(reward)
        });
        PoolReward {
            id: pool_reward_uid,
            associate_pool_reward_balance,
            start_time,
            end_time,
            last_update_time: start_time,
            initial_balance,
            reward_index: 0,
            reward_per_second,
            user_reward: table::new(ctx),
            dola_pool_id,
            reward_action,
            owner: tx_context::sender(ctx)
        }
    }

    public(friend) fun boost(
        reward_pool: &mut PoolReward,
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        lending_action: u8,
        clock: &Clock
    ) {
        let reward_action = lending_action;
        if (reward_action == lending_codec::get_withdraw_type()) {
            reward_action = lending_codec::get_supply_type()
        }else if (reward_action == lending_codec::get_repay_type())(
            reward_action = lending_codec::get_borrow_type()
        );
        assert!(dola_pool_id == reward_pool.dola_pool_id, EINVALID_POOL);
        if (reward_action == reward_pool.reward_action) {
            update_pool_reward(reward_pool, storage, dola_pool_id, reward_action, clock);
            update_user_reward(reward_pool, storage, dola_pool_id, dola_user_id, reward_action);
        }
    }

    public(friend) fun claim_reward<X>(
        reward_pool: &mut PoolReward,
        reward_pool_balance: &mut PoolRewardBalance<X>,
        dola_user_id: u64,
        ctx: &mut TxContext
    ): Coin<X> {
        assert!(reward_pool.associate_pool_reward_balance == object::id(reward_pool_balance), ENOT_ASSOCIATE_POOL);
        assert!(reward_pool_balance.associate_pool_reward == object::id(reward_pool), ENOT_ASSOCIATE_POOL);
        let user_reward = table::borrow_mut(&mut reward_pool.user_reward, dola_user_id);
        let actual_user_reward = (ray_math::min(
            user_reward.balance,
            (balance::value(&reward_pool_balance.balance) as u256)
        ) as u64);
        coin::from_balance(balance::split(&mut reward_pool_balance.balance, actual_user_reward), ctx)
    }

    public(friend) fun destory_reward_pool<X>(
        reward_pool: PoolReward,
        reward_pool_balance: &mut PoolRewardBalance<X>,
        ctx: &mut TxContext
    ): Coin<X> {
        assert!(reward_pool.associate_pool_reward_balance == object::id(reward_pool_balance), ENOT_ASSOCIATE_POOL);
        assert!(reward_pool_balance.associate_pool_reward == object::id(&reward_pool), ENOT_ASSOCIATE_POOL);
        let PoolReward {
            id,
            associate_pool_reward_balance: _,
            owner: _,
            start_time: _,
            end_time: _,
            reward_index: _,
            reward_action: _,
            initial_balance: _,
            dola_pool_id: _,
            last_update_time: _,
            reward_per_second: _,
            user_reward,
        } = reward_pool;
        object::delete(id);
        table::drop(user_reward);
        coin::from_balance(balance::withdraw_all(&mut reward_pool_balance.balance), ctx)
    }

    entry fun claim<X>(
        genesis: &GovernanceGenesis,
        user_manager_info: &UserManagerInfo,
        reward_pool: &mut PoolReward,
        reward_pool_balance: &mut PoolRewardBalance<X>,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);
        let reward = claim_reward(reward_pool, reward_pool_balance, dola_user_id, ctx);
        transfer::public_transfer(reward, tx_context::sender(ctx));
    }
}
