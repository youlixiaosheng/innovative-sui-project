#[test_only]
module farm::farm_tests {
    use farm::farm::{Self, Director};
    use sui::coin::{Self};
    use sui::random;
    use sui::random::Random;
    use sui::sui::SUI;
    use sui::test_scenario::ctx;
    use sui::vec_map;

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::test_utils::assert_eq;


    #[test]
    fun test_farm() {
        let admin = @0x0;
        let little_red = @0xa;
        let little_green = @0xb;

        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        random::create_for_testing(ctx(scenario));


        // ====================
        //  init
        // ====================
        {
            farm::test_init(test_scenario::ctx(scenario));
        };


        // ====================
        //  little_red planting
        // ====================
        test_scenario::next_tx(scenario, little_red);
        {
            let mut director = test_scenario::take_shared<Director>(scenario);
            let random = test_scenario::take_shared<Random>(scenario);
            let mut investment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(scenario));
            farm::planting(
                &mut director,
                &mut investment,
                &random,
                test_scenario::ctx(scenario)
            );
            let epoch = tx_context::epoch(test_scenario::ctx(scenario));
            let farm_game = farm::get_epoch_farm_game(&director, &epoch);
            let farm_users = farm::get_epoch_farm_users(farm_game);
            assert_eq(vec_map::size(farm_users), 1);
            let balance = farm::get_epoch_farm_balance(farm_game);
            assert_eq(balance, 1_000_000_000);
            coin::burn_for_testing(investment);
            test_scenario::return_shared(director);
            test_scenario::return_shared(random);
        };

        // ====================
        //  little_green planting
        // ====================
        test_scenario::next_tx(scenario, little_green);
        {
            let mut director = test_scenario::take_shared<Director>(scenario);
            let random = test_scenario::take_shared<Random>(scenario);
            let mut investment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(scenario));
            farm::planting(
                &mut director,
                &mut investment,
                &random,
                test_scenario::ctx(scenario)
            );
            let epoch = tx_context::epoch(test_scenario::ctx(scenario));
            let farm_game = farm::get_epoch_farm_game(&director, &epoch);
            let farm_users = farm::get_epoch_farm_users(farm_game);
            assert_eq(vec_map::size(farm_users), 2);
            let balance = farm::get_epoch_farm_balance(farm_game);
            assert_eq(balance, 2_000_000_000);
            coin::burn_for_testing(investment);
            test_scenario::return_shared(director);
            test_scenario::return_shared(random);
        };

        // steal
        test_scenario::next_tx(scenario, little_red);
        {
            let mut director = test_scenario::take_shared<Director>(scenario);
            let random = test_scenario::take_shared<Random>(scenario);

            // 先获取到当前的奖励
            let epoch = tx_context::epoch(test_scenario::ctx(scenario));
            let farm_game = farm::get_epoch_farm_game(&director, &epoch);
            let farm_users = farm::get_epoch_farm_users(farm_game);
            let farm_user_red = vec_map::get(farm_users, &little_red);
            let farm_user_green = vec_map::get(farm_users, &little_green);
            let red_rewards = farm::get_epoch_farm_user_reward(farm_user_red);
            let green_rewards = farm::get_epoch_farm_user_reward(farm_user_green);
            let special_event = farm::get_special_event(farm_user_green);
            farm::steal(
                &mut director,
                &random,
                test_scenario::ctx(scenario)
            );
            // 如果对方不是 STEAL_FAIL 则余额会变
            if (5 != special_event) {
                let farm_game = farm::get_epoch_farm_game(&director, &epoch);
                let farm_users = farm::get_epoch_farm_users(farm_game);
                let farm_user_red = vec_map::get(farm_users, &little_red);
                let farm_user_green = vec_map::get(farm_users, &little_green);
                assert!(red_rewards != farm::get_epoch_farm_user_reward(farm_user_red), 0);
                assert!(green_rewards != farm::get_epoch_farm_user_reward(farm_user_green), 1);
                assert_eq(red_rewards+green_rewards, farm::get_epoch_farm_user_reward(farm_user_red) + farm::get_epoch_farm_user_reward(farm_user_green));
            };
            test_scenario::return_shared(director);
            test_scenario::return_shared(random);
        };

        // harvest
        test_scenario::next_tx(scenario, little_red);
        {
            let mut director = test_scenario::take_shared<Director>(scenario);
            let epoch = tx_context::epoch(test_scenario::ctx(scenario));
            // 先获取到当前的奖励
            let farm_game = farm::get_epoch_farm_game(&director, &epoch);
            let farm_users = farm::get_epoch_farm_users(farm_game);
            let farm_user_red = vec_map::get(farm_users, &little_red);
            let red_rewards = farm::get_epoch_farm_user_reward(farm_user_red);
            let game_balance = farm::get_epoch_farm_balance(farm_game);
            let ctx = {
                let ctx = test_scenario::ctx(scenario);
                ctx.increment_epoch_number();
                ctx
            };
            farm::harvest(
                &mut director,
                ctx
            );
            let farm_game = farm::get_epoch_farm_game(&director, &epoch);
            assert_eq(game_balance - red_rewards, farm::get_epoch_farm_balance(farm_game));
            test_scenario::return_shared(director);
        };

        test_scenario::next_tx(scenario, little_green);
        {
            let mut director = test_scenario::take_shared<Director>(scenario);
            let epoch = tx_context::epoch(test_scenario::ctx(scenario)) - 1;
            // 先获取到当前的奖励
            let farm_game = farm::get_epoch_farm_game(&director, &epoch);
            let farm_users = farm::get_epoch_farm_users(farm_game);
            let farm_user_green = vec_map::get(farm_users, &little_green);
            let green_rewards = farm::get_epoch_farm_user_reward(farm_user_green);
            let game_balance = farm::get_epoch_farm_balance(farm_game);
            let ctx = {
                let ctx = test_scenario::ctx(scenario);
                // ctx.increment_epoch_number();
                ctx
            };
            farm::harvest(
                &mut director,
                ctx
            );
            let farm_game = farm::get_epoch_farm_game(&director, &epoch);
            assert_eq(game_balance - green_rewards, farm::get_epoch_farm_balance(farm_game));
            test_scenario::return_shared(director);
        };

        test_scenario::end(scenario_val);
    }

}
