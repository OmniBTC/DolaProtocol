module dola_protocol::boost {
    use std::vector;

    use sui::balance;
    use sui::balance::Balance;
    use sui::clock::Clock;
    use sui::coin;
    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::object;
    use sui::object::{ID, UID};
    use sui::table;
    use sui::table::Table;
    use sui::transfer;
    use sui::tx_context::TxContext;

    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::lending_codec;
    use dola_protocol::lending_core_storage as storage;
    use dola_protocol::lending_core_storage::Storage;
    use dola_protocol::ray_math;
    use std::ascii::String;
    use sui::event;
    use std::type_name;
    use sui::tx_context;

    friend dola_protocol::lending_logic;
    friend dola_protocol::lending_portal_v2;

    #[test_only]
    friend dola_protocol::logic_tests;

    /// Errors

    const EINVALID_TIME: u64 = 0;

    const ENOT_ONWER: u64 = 1;

    const EINVALID_ACTION: u64 = 2;

    const EINVALID_POOL: u64 = 3;

    const ENOT_ASSOCIATE_POOL: u64 = 4;

    const ENOT_REWARD_POOL: u64 = 5;

    struct UserRewardInfo has store, drop {
        // Reward index when `acc_user_index` was last updated
        last_update_reward_index: u256,
        // The unclaimed reward balance
        balance: u256
    }

    struct RewardPoolInfo has key, store {
        id: UID,
        // Escrow fund object [PoolRewardBalance]
        escrow_fund: ID,
        // Start time
        start_time: u256,
        // End time
        end_time: u256,
        // Pool reward index [math::ray]
        reward_index: u256,
        // Pool reward action [supply|borrow]
        reward_action: u8,
        // Total reward
        total_reward: u64,
        // The pool id that needs to be rewarded
        dola_pool_id: u16,
        // Last update time
        last_update_time: u256,
        // Number of rewards per second [math::ray]
        reward_per_second: u256,
        // User reward record
        user_reward: Table<u64, UserRewardInfo>,
    }

    struct RewardPool<phantom X> has key {
        id: UID,
        // Associate pool reward [PoolReward]
        associate_pool: ID,
        // Escrow fund
        balance: Balance<X>
    }

    /// Event

    struct UpdatePoolRewardEvent has drop, copy {
        dola_pool_id: u16,
        old_timestamp: u256,
        new_timestamp: u256,
        old_reward_index: u256,
        new_reward_index: u256
    }

    struct UpdateUserRewardEvent has drop, copy {
        dola_pool_id: u16,
        dola_user_id: u64,
        old_balance: u256,
        new_balance: u256,
        old_reward_index: u256,
        new_reward_index: u256
    }

    struct ClaimRewardEvent has drop, copy {
        token: String,
        dola_pool_id: u16,
        dola_user_id: u64,
        reward_action: u8,
        amount: u64,
        sender: address
    }

    fun get_total_scaled_balance(
        storage: &Storage,
        dola_pool_id: u16,
        reward_action: u8,
    ): u256 {
        let total_scaled_balance;
        if (reward_action == lending_codec::get_supply_type()) {
            total_scaled_balance = storage::get_otoken_scaled_total_supply_v2(storage, dola_pool_id);
        }else if (reward_action == lending_codec::get_borrow_type()) {
            total_scaled_balance = storage::get_dtoken_scaled_total_supply_v2(storage, dola_pool_id);
        }else {
            abort EINVALID_ACTION
        };
        total_scaled_balance
    }

    fun get_user_scaled_balance(
        storage: &Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        reward_action: u8
    ): u256 {
        let user_scaled_balance;
        if (reward_action == lending_codec::get_supply_type()) {
            user_scaled_balance = storage::get_user_scaled_otoken_v2(storage, dola_user_id, dola_pool_id);
        }else if (reward_action == lending_codec::get_borrow_type()) {
            user_scaled_balance = storage::get_user_scaled_dtoken_v2(storage, dola_user_id, dola_pool_id);
        }else {
            abort EINVALID_ACTION
        };
        user_scaled_balance
    }

    fun update_pool_reward(
        reward_pool: &mut RewardPoolInfo,
        total_scaled_balance: u256,
        clock: &Clock,
    ) {
        let current_timestamp = ray_math::max(storage::get_timestamp(clock), reward_pool.start_time);
        let current_timestamp = ray_math::min(current_timestamp, reward_pool.end_time);

        let old_timestamp = reward_pool.last_update_time;
        let old_reward_index = reward_pool.reward_index;
        if (total_scaled_balance == 0) {
            reward_pool.reward_index = 0;
        } else {
            reward_pool.reward_index = reward_pool.reward_index + reward_pool.reward_per_second * (current_timestamp - reward_pool.last_update_time) / total_scaled_balance
        };

        reward_pool.last_update_time = current_timestamp;

        event::emit(
            UpdatePoolRewardEvent {
                dola_pool_id: reward_pool.dola_pool_id,
                old_timestamp,
                new_timestamp: reward_pool.last_update_time,
                old_reward_index,
                new_reward_index: reward_pool.reward_index
            }
        );
    }

    fun update_user_reward(
        reward_pool: &mut RewardPoolInfo,
        user_scaled_balance: u256,
        dola_user_id: u64,
    ) {
        if (!table::contains(&reward_pool.user_reward, dola_user_id)) {
            table::add(&mut reward_pool.user_reward, dola_user_id, UserRewardInfo {
                last_update_reward_index: 0,
                balance: 0
            })
        };
        let user_reward = table::borrow_mut(&mut reward_pool.user_reward, dola_user_id);
        let delta_index = reward_pool.reward_index - user_reward.last_update_reward_index;
        let old_balance = user_reward.balance;
        let old_reward_index = user_reward.last_update_reward_index;
        user_reward.balance = user_reward.balance + ray_math::ray_mul(delta_index, user_scaled_balance);
        user_reward.last_update_reward_index = reward_pool.reward_index;

        event::emit(
            UpdateUserRewardEvent {
                dola_pool_id: reward_pool.dola_pool_id,
                dola_user_id,
                old_balance,
                new_balance: user_reward.balance,
                old_reward_index,
                new_reward_index: user_reward.last_update_reward_index
            }
        );
    }

    fun create_reward_pool_inner<X>(
        start_time: u256,
        end_time: u256,
        reward: Coin<X>,
        dola_pool_id: u16,
        reward_action: u8,
        ctx: &mut TxContext
    ): RewardPoolInfo {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(
            reward_action == lending_codec::get_borrow_type() || reward_action == lending_codec::get_supply_type(),
            EINVALID_ACTION
        );
        let total_reward = coin::value(&reward);
        let reward_per_second = ray_math::ray_div((total_reward as u256), end_time - start_time);
        let pool_reward_uid = object::new(ctx);
        let associate_pool = object::uid_to_inner(&pool_reward_uid);
        let pool_reward_balance_uid = object::new(ctx);
        let escrow_fund = object::uid_to_inner(&pool_reward_balance_uid);
        transfer::share_object(RewardPool<X> {
            id: pool_reward_balance_uid,
            associate_pool,
            balance: coin::into_balance(reward)
        });
        RewardPoolInfo {
            id: pool_reward_uid,
            escrow_fund,
            start_time,
            end_time,
            last_update_time: start_time,
            total_reward,
            reward_index: 0,
            reward_per_second,
            user_reward: table::new(ctx),
            dola_pool_id,
            reward_action
        }
    }

    public(friend) fun claim_reward<X>(
        reward_pool: &mut RewardPoolInfo,
        reward_pool_balance: &mut RewardPool<X>,
        dola_user_id: u64,
        ctx: &mut TxContext
    ): Coin<X> {
        assert!(reward_pool.escrow_fund == object::id(reward_pool_balance), ENOT_ASSOCIATE_POOL);
        assert!(reward_pool_balance.associate_pool == object::id(reward_pool), ENOT_ASSOCIATE_POOL);
        let user_reward = table::borrow_mut(&mut reward_pool.user_reward, dola_user_id);
        let actual_user_reward = ray_math::min(
            user_reward.balance,
            (balance::value(&reward_pool_balance.balance) as u256)
        );
        let old_balance = user_reward.balance;
        user_reward.balance = user_reward.balance - actual_user_reward;

        event::emit(
            UpdateUserRewardEvent {
                dola_pool_id: reward_pool.dola_pool_id,
                dola_user_id,
                old_balance,
                new_balance: user_reward.balance,
                old_reward_index: user_reward.last_update_reward_index,
                new_reward_index: user_reward.last_update_reward_index
            }
        );

        coin::from_balance(balance::split(&mut reward_pool_balance.balance, (actual_user_reward as u64)), ctx)
    }

    public(friend) fun destory_reward_pool<X>(
        reward_pool: RewardPoolInfo,
        reward_pool_balance: &mut RewardPool<X>,
        ctx: &mut TxContext
    ): Coin<X> {
        assert!(reward_pool.escrow_fund == object::id(reward_pool_balance), ENOT_ASSOCIATE_POOL);
        assert!(reward_pool_balance.associate_pool == object::id(&reward_pool), ENOT_ASSOCIATE_POOL);
        let RewardPoolInfo {
            id,
            escrow_fund: _,
            start_time: _,
            end_time: _,
            reward_index: _,
            reward_action: _,
            total_reward: _,
            dola_pool_id: _,
            last_update_time: _,
            reward_per_second: _,
            user_reward,
        } = reward_pool;
        object::delete(id);
        table::drop(user_reward);
        coin::from_balance(balance::withdraw_all(&mut reward_pool_balance.balance), ctx)
    }

    public fun create_reward_pool<X>(
        _: &GovernanceCap,
        storage: &mut Storage,
        start_time: u256,
        end_time: u256,
        reward: Coin<X>,
        dola_pool_id: u16,
        reward_action: u8,
        ctx: &mut TxContext
    ) {
        let reward_pool = create_reward_pool_inner(
            start_time,
            end_time,
            reward,
            dola_pool_id,
            reward_action,
            ctx
        );
        let storage_id = storage::get_storage_id(storage);
        if (!dynamic_field::exists_(storage_id, dola_pool_id)) {
            dynamic_field::add(storage_id, dola_pool_id, vector::empty<RewardPoolInfo>());
        };
        let reward_pools = dynamic_field::borrow_mut<u16, vector<RewardPoolInfo>>(storage_id, dola_pool_id);
        vector::push_back(reward_pools, reward_pool);
    }

    public fun remove_reward_pool<X>(
        _: &GovernanceCap,
        storage: &mut Storage,
        reward_pool_balance: &mut RewardPool<X>,
        dola_pool_id: u16,
        ctx: &mut TxContext
    ): Coin<X> {
        let storage_id = storage::get_storage_id(storage);
        assert!(dynamic_field::exists_(storage_id, dola_pool_id), ENOT_REWARD_POOL);
        let reward_pool = &reward_pool_balance.associate_pool;
        let reward_pools = dynamic_field::borrow_mut<u16, vector<RewardPoolInfo>>(storage_id, dola_pool_id);

        let i = 0;
        let remain_balance: Coin<X> = coin::zero(ctx);
        let flag = false;
        while (i < vector::length(reward_pools)) {
            if (reward_pool == &object::id(vector::borrow(reward_pools, i))) {
                flag = true;
                let reward_pool = vector::remove(reward_pools, i);
                coin::join(&mut remain_balance, destory_reward_pool(reward_pool, reward_pool_balance, ctx));
                break
            };
            i = i + 1;
        };
        assert!(flag, ENOT_REWARD_POOL);
        remain_balance
    }

    public(friend) fun boost_pool(
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
        let total_scaled_balance = get_total_scaled_balance(storage, dola_pool_id, reward_action);
        let user_scaled_balance = get_user_scaled_balance(storage, dola_pool_id, dola_user_id, reward_action);
        let storage_id = storage::get_storage_id(storage);
        if (dynamic_field::exists_(storage_id, dola_pool_id)) {
            let reward_pools = dynamic_field::borrow_mut<u16, vector<RewardPoolInfo>>(storage_id, dola_pool_id);
            let i = 0;
            while (i < vector::length(reward_pools)) {
                let reward_pool = vector::borrow_mut(reward_pools, i);
                assert!(dola_pool_id == reward_pool.dola_pool_id, EINVALID_POOL);
                if (reward_action == reward_pool.reward_action) {
                    update_pool_reward(reward_pool, total_scaled_balance, clock);
                    update_user_reward(reward_pool, user_scaled_balance, dola_user_id);
                };
                i = i + 1;
            }
        }
    }

    public(friend) fun claim<X>(
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        reward_action: u8,
        reward_pool_balance: &mut RewardPool<X>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<X> {
        let total_scaled_balance = get_total_scaled_balance(
            storage,
            dola_pool_id,
            reward_action
        );
        let user_scaled_balance = get_user_scaled_balance(
            storage,
            dola_pool_id,
            dola_user_id,
            reward_action
        );

        let storage_id = storage::get_storage_id(storage);
        let reward = coin::zero<X>(ctx);
        if (dynamic_field::exists_(storage_id, dola_pool_id)) {
            let reward_pools = dynamic_field::borrow_mut<u16, vector<RewardPoolInfo>>(storage_id, dola_pool_id);
            let i = 0;
            while (i < vector::length(reward_pools)) {
                let reward_pool = vector::borrow_mut(reward_pools, i);
                if (reward_pool.escrow_fund == object::id(reward_pool_balance)) {
                    update_pool_reward(reward_pool, total_scaled_balance, clock);
                    update_user_reward(reward_pool, user_scaled_balance, dola_user_id);
                    coin::join(&mut reward, claim_reward(reward_pool, reward_pool_balance, dola_user_id, ctx));
                };
                i = i + 1;
            }
        };

        event::emit(
            ClaimRewardEvent {
                token: type_name::into_string(type_name::get<X>()),
                dola_pool_id,
                dola_user_id,
                reward_action,
                amount: coin::value(&reward),
                sender: tx_context::sender(ctx)
            }
        );
        reward
    }
}
