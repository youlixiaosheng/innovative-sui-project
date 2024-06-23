module farm::farm {

    use std::ascii::{String, string};
    use std::debug;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::package;
    use sui::random::{Random, new_generator};
    use sui::vec_map;
    use sui::vec_map::VecMap;

    // ===> ErrorCodes <===
    const E_INVALID_AMOUNT: u64 = 1;
    const E_PAUSED: u64 = 2;
    const E_GAME_DOES_NOT_EXIST: u64 = 3;
    const E_STOLEN: u64 = 4;
    const E_NOT_EXISTED_AVAILABLE_FARMER: u64 = 5;
    const E_NOT_INVOLVED_IN_PLANTING: u64 = 6;
    const E_REPEATED_HARVEST: u64 = 7;

    // ===> special_event Constants <===
    const NO_SPECIAL_EVENT: u64 = 1;
    const DOUBLE_ANTI_STEAL: u64 = 3;
    const DOUBLE_STEAL_SUCCESS: u64 = 4;
    const STEAL_FAIL: u64 = 5;

    // ===> Events <===
    public struct EventSteal has copy, drop {
        sender: address,
        target: address,
        epoch: u64,
        success: bool,
        reward: u64,
    }

    public struct EventHarvest has copy, drop {
        sender: address,
        epoch: u64,
        reward: u64
    }

    public struct EventPlanting has copy, drop {
        sender: address,
        epoch: u64,
        investment_value: u64,
        balance: u64
    }

    // ===> Structures <===
    public struct FARM has drop {}

    public struct AdminCap has key {
        id: UID,
    }

    /// Singleton shared object to record the game state of each epoch.
    public struct Director has key, store {
        id: UID,
        paused: bool, // Master switch
        epoch_games: VecMap<u64, FarmGame>, // Table with keys as epochs
    }

    public struct Crop has store, copy {
        name: String, // Name
        epoch: u64, // Planting epoch
        mature_epoch: u64, // Maturity epoch
        investment: u64,
        harvestable: bool, // Whether it is harvestable
        harvested: bool, // Whether it has been harvested
        stolen: bool, // Whether it has been stolen
        token_reward: u64, // Token reward after harvesting
    }

    public struct FarmUser has store {
        address: address,
        steal: bool,
        investment: u64,
        rewards: u64, // Rewards generated when others are caught stealing
        special_event: u64,
        crop: Crop,
    }

    public struct FarmGame has store {
        epoch: u64,
        balance_pool: u64,
        investments: Balance<SUI>,
        farm_users: VecMap<address, FarmUser>,
    }

    // ===> Functions <===

    /// Initialize the farming game with an initial FARM object and context.
    public entry fun init(otw: FARM, ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx);

        transfer::share_object(
            Director {
                id: object::new(ctx),
                paused: false,
                epoch_games: vec_map::empty<u64, FarmGame>(),
            }
        );

        transfer::transfer(AdminCap{
            id: object::new(ctx)
        }, tx_context::sender(ctx));
    }

    /// Get or create the FarmGame for the current epoch.
    fun get_or_create_epoch_game(
        director: &mut Director,
        ctx: &mut TxContext,
    ): &mut FarmGame {
        let epoch = tx_context::epoch(ctx);
        if (!vec_map::contains(&director.epoch_games, &epoch)) {
            let balance_pool = 0;
            let epoch_game = FarmGame {
                epoch,
                balance_pool,
                investments: coin::into_balance(coin::zero<SUI>(ctx)),
                farm_users: vec_map::empty<address, FarmUser>(),
            };
            vec_map::insert(&mut director.epoch_games, epoch, epoch_game);
        };
        let farm_game = vec_map::get_mut(&mut director.epoch_games, &epoch);
        farm_game
    }

    /// Create a crop for the given epoch, investment value, and special event.
    fun create_crop(epoch: u64, investment_value: u64, special_event:u64) : (Crop, u64) {
        let name = string(b"Sui");
        let mature_epoch = epoch + 1;
        let investment = 0;
        let harvestable = false;
        let harvested = false;
        let stolen = false;
        let token_reward = investment_value;
        let crop = Crop {
            name,
            epoch,
            mature_epoch,
            investment,
            harvestable,
            harvested,
            stolen,
            token_reward,
        };
        (crop, token_reward)
    }

    /// Create a farmer for the given epoch, address, investment value, and special event.
    fun create_farmer(epoch: u64, address: address, investment_value: u64, special_event: u64) : FarmUser {
        let investment = investment_value;
        let (crop, token_reward) = create_crop(epoch, investment_value, special_event);

        let steal = false;
        FarmUser {
            address,
            steal,
            investment,
            rewards: token_reward,
            special_event,
            crop,
        }
    }

    /// Get the FarmGame by epoch.
    fun get_game_by_epoch(director: &mut Director, epoch: u64) : &mut FarmGame {
        assert!(vec_map::contains(&director.epoch_games, &epoch), E_GAME_DOES_NOT_EXIST);
        let epoch_game = vec_map::get_mut(&director.epoch_games, &epoch);
        epoch_game
    }

    /// Get the FarmUser by epoch and sender address.
    fun get_farmer_by_epoch(director: &mut Director, epoch: u64, sender: address) : &mut FarmUser {
        let epoch_game = get_game_by_epoch(director, epoch);
        assert!(vec_map::contains(&epoch_game.farm_users, &sender), E_NOT_INVOLVED_IN_PLANTING);
        epoch_game.farm_users.get_mut(&sender)
    }

    /// Perform planting action with given director, investment, random generator, and context.
    #[allow(lint(public_random))]
    public entry fun planting(
        director: &mut Director,
        investment: &mut Coin<SUI>,
        rnd: &Random,
        ctx: &mut TxContext)
    {
        debug::print(&string(b"=====================planting start====================="));
        let sender = tx_context::sender(ctx);
        let epoch = tx_context::epoch(ctx);
        let investment_value = coin::value(investment);
        let paid = coin::split(investment, investment_value, ctx);
        // Minimum investment is 1 SUI
        assert!(investment_value >= 1_000, E_INVALID_AMOUNT);
        // Check if the master switch is on
        assert!(director.paused == false, E_PAUSED);
        // Get or create the current epoch game
        let gen = &mut new_generator(rnd, ctx);
        let special_event = gen.generate_u64_in_range(NO_SPECIAL_EVENT, STEAL_FAIL);
        let farm_user = create_farmer(epoch, sender, investment_value, special_event);
        let farm_game = get_or_create_epoch_game(director, ctx);
        farm_game.investments.join(coin::into_balance(paid));
        farm_game.balance_pool = farm_game.balance_pool + investment_value;
        let farm_users = &mut farm_game.farm_users;
        // Check if the user already exists
        assert!(vec_map::contains(farm_users, &sender) == false, E_REPEATED_HARVEST);

        vec_map::insert(farm_users, sender, farm_user);
        debug::print(&vec_map::size(&director.epoch_games));
        event::emit(EventPlanting{
            epoch,
            sender,
            investment_value,
            balance: investment_value
        });
        debug::print(&sender);
        debug::print(director);
        debug::print(&string(b"=====================planting end====================="));
    }

    /// Perform stealing action with given director, random generator, and context.
    #[allow(lint(public_random))]
    public entry fun steal(director: &mut Director, rnd: &Random, ctx: &mut TxContext) {
        debug::print(&string(b"=====================steal start====================="));
        // Check if the master switch is on
        assert!(director.paused == false, E_PAUSED);
        let epoch = tx_context::epoch(ctx);
        let sender = tx_context::sender(ctx);

        // Get the current epoch game
        assert!(vec_map::contains(&director.epoch_games, &epoch), E_GAME_DOES_NOT_EXIST);
        let farm_game = vec_map::get_mut(&mut director.epoch_games, &epoch);
        let size = farm_game.farm_users.size();

        assert!(vec_map::contains(&farm_game.farm_users, &sender), E_NOT_INVOLVED_IN_PLANTING);
        let mut final_rewards = {
            let farmer = farm_game.farm_users.get(&sender);
            
            if (!
            farmer.crop.harvestable {
                debug::print(&string(b"Steal failed: crop is already harvestable"));
                farmer.crop.token_reward
            } else {
                let mut steal_flag = false;
                let mut final_reward = 0;
                let gen = &mut new_generator(rnd, ctx);
                
                for user in vec_map::values(&farm_game.farm_users) {
                    if (user.address != sender && user.steal == false) {
                        let random_value = gen.generate_u64_in_range(0, 100);
                        if (random_value > 50) {
                            steal_flag = true;
                            user.steal = true;
                            user.crop.stolen = true;
                            final_reward = user.crop.token_reward;
                            break;
                        }
                    }
                }
                
                // If no stealable target is found, fail the transaction
                assert!(steal_flag == true, E_NOT_EXISTED_AVAILABLE_FARMER);
                
                final_reward
            }
        };

        farm_game.balance_pool = farm_game.balance_pool - final_rewards;
        let farmer = farm_game.farm_users.get_mut(&sender);
        farmer.rewards = farmer.rewards + final_rewards;

        event::emit(EventSteal {
            sender,
            target: farmer.address,
            epoch,
            success: steal_flag,
            reward: final_rewards,
        });

        debug::print(&string(b"=====================steal end====================="));
    }

    /// Perform harvesting action with given director and context.
    public entry fun harvest(director: &mut Director, ctx: &mut TxContext) {
        debug::print(&string(b"=====================harvest start====================="));
        // Check if the master switch is on
        assert!(director.paused == false, E_PAUSED);
        let epoch = tx_context::epoch(ctx);
        let sender = tx_context::sender(ctx);

        // Get the current epoch game
        let farm_game = get_game_by_epoch(director, epoch);
        
        // Get the current farmer
        let farmer = get_farmer_by_epoch(director, epoch, sender);
        
        // Ensure the crop is harvestable and not already harvested
        assert!(farmer.crop.harvestable == true, E_REPEATED_HARVEST);
        
        let final_reward = farmer.crop.token_reward;
        
        // Update farmer's rewards
        farmer.rewards = farmer.rewards + final_reward;
        farmer.crop.harvested = true;
        
        event::emit(EventHarvest {
            sender,
            epoch,
            reward: final_reward,
        });
        
        debug::print(&string(b"=====================harvest end====================="));
    }

    /// Pauses the game, requires AdminCap
    public entry fun pause(director: &mut Director, admin: AdminCap, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == admin.id, E_PAUSED);
        director.paused = true;
    }

    /// Resumes the game, requires AdminCap
    public entry fun resume(director: &mut Director, admin: AdminCap, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == admin.id, E_PAUSED);
        director.paused = false;
    }

    /// Transfer the AdminCap to another address
    public entry fun transfer_admin_cap(admin: AdminCap, new_admin: address, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == admin.id, E_PAUSED);
        transfer::transfer(admin, new_admin);
    }

    /// Emits debug information to log
    #[inline(never)]
    fun emit_debug_info(director: &Director, ctx: &TxContext) {
        debug::print(&director.paused);
        debug::print(&tx_context::epoch(ctx));
    }
}
