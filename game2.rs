use anchor_lang::prelude::*;
use anchor_lang::system_program;

declare_id!("4hmtAprg26SJgUKURwVMscyMv9mTtHnbvxaAXy6VJrr8");

#[program]
pub mod my_program {
    use super::*;

    // Initialize a new character NFT
    pub fn create_character(
        ctx: Context<CreateCharacter>,
        character_class: CharacterClass,
        name: String,
    ) -> Result<()> {
        require!(name.len() <= 32, GameError::NameTooLong);

        let character = &mut ctx.accounts.character;
        let clock = Clock::get()?;

        // Initialize all fields explicitly
        character.owner = ctx.accounts.owner.key();
        character.character_class = character_class;
        character.name = name;
        character.level = 1;
        character.xp = 0;
        character.total_wins = 0;
        character.total_losses = 0;
        character.max_combo = 0;
        character.created_at = clock.unix_timestamp;
        character.last_battle = 0;

        // Set base stats based on class
        match character_class {
            CharacterClass::Warrior => {
                character.max_hp = 120;
                character.current_hp = 120;
                character.base_damage_min = 8;
                character.base_damage_max = 15;
                character.crit_chance = 15;
                character.dodge_chance = 0;
            }
            CharacterClass::Assassin => {
                character.max_hp = 90;
                character.current_hp = 90;
                character.base_damage_min = 12;
                character.base_damage_max = 20;
                character.crit_chance = 35;
                character.dodge_chance = 20;
            }
            CharacterClass::Mage => {
                character.max_hp = 80;
                character.current_hp = 80;
                character.base_damage_min = 10;
                character.base_damage_max = 18;
                character.crit_chance = 20;
                character.dodge_chance = 0;
            }
            CharacterClass::Tank => {
                character.max_hp = 150;
                character.current_hp = 150;
                character.base_damage_min = 6;
                character.base_damage_max = 12;
                character.crit_chance = 10;
                character.dodge_chance = 0;
            }
        }

        character.defense = 0;
        character.special_cooldown = 0;
        character.mmr = 100; // Starting MMR

        msg!("Character created: {} ({})", character.name, character_class.to_string());
        Ok(())
    }

    // Create a new battle match
    pub fn create_battle(
        ctx: Context<CreateBattle>,
        match_type: MatchType,
        stake_amount: u64,
    ) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let clock = Clock::get()?;

        // Initialize all battle fields
        battle.player1 = ctx.accounts.player1_character.key();
        battle.player2 = ctx.accounts.player2_character.key();
        battle.match_type = match_type;
        battle.stake_amount = stake_amount;
        battle.created_at = clock.unix_timestamp;
        battle.turn_number = 0;
        battle.current_turn = 1; // Player 1 starts
        battle.is_finished = false;
        battle.winner = None;

        // Initialize player states
        battle.player1_hp = ctx.accounts.player1_character.current_hp;
        battle.player2_hp = ctx.accounts.player2_character.current_hp;
        battle.player1_combo = 0;
        battle.player2_combo = 0;
        battle.player1_stance = BattleStance::Balanced;
        battle.player2_stance = BattleStance::Balanced;
        battle.player1_dot_damage = 0;
        battle.player2_dot_damage = 0;
        battle.player1_dot_turns = 0;
        battle.player2_dot_turns = 0;
        battle.player1_reflection = 0;
        battle.player2_reflection = 0;
        battle.player1_miss_count = 0;
        battle.player2_miss_count = 0;
        battle.last_damage_roll = 0;
        battle.wildcard_active = false;
        battle.wildcard_type = None;

        msg!("Battle created between {} and {}", 
            ctx.accounts.player1_character.name,
            ctx.accounts.player2_character.name
        );
        Ok(())
    }

    // Execute a battle turn
    pub fn execute_turn(
        ctx: Context<ExecuteTurn>,
        stance: BattleStance,
        use_special: bool,
    ) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let attacker_char = &ctx.accounts.attacker_character;
        let defender_char = &ctx.accounts.defender_character;
        let clock = Clock::get()?;

        require!(!battle.is_finished, GameError::BattleAlreadyFinished);

        // Determine which player is attacking
        let is_player1 = battle.player1 == attacker_char.key();
        require!(
            (is_player1 && battle.current_turn == 1) || (!is_player1 && battle.current_turn == 2),
            GameError::NotYourTurn
        );

        // Set stance
        if is_player1 {
            battle.player1_stance = stance;
        } else {
            battle.player2_stance = stance;
        }

        // Apply DOT damage at start of turn
        if is_player1 && battle.player1_dot_turns > 0 {
            battle.player1_hp = battle.player1_hp.saturating_sub(battle.player1_dot_damage);
            battle.player1_dot_turns -= 1;
            msg!("Player 1 takes {} DOT damage", battle.player1_dot_damage);
        } else if !is_player1 && battle.player2_dot_turns > 0 {
            battle.player2_hp = battle.player2_hp.saturating_sub(battle.player2_dot_damage);
            battle.player2_dot_turns -= 1;
            msg!("Player 2 takes {} DOT damage", battle.player2_dot_damage);
        }

        // Check for wildcard event (10% chance)
        let wildcard_roll = generate_random_u8(clock.unix_timestamp, battle.turn_number as u64, 1) % 100;
        if wildcard_roll < 10 && !battle.wildcard_active {
            let wildcard_type_roll = generate_random_u8(clock.unix_timestamp, battle.turn_number as u64, 2) % 8;
            battle.wildcard_type = Some(match wildcard_type_roll {
                0 => WildcardEvent::DoubleOrNothing,
                1 => WildcardEvent::ReverseRoles,
                2 => WildcardEvent::MysteryBox,
                3 => WildcardEvent::DeathRoulette,
                4 => WildcardEvent::ComboBreaker,
                5 => WildcardEvent::TimeWarp,
                6 => WildcardEvent::LuckySeven,
                _ => WildcardEvent::GamblersFallacy,
            });
            battle.wildcard_active = true;
            msg!("Wildcard event triggered: {:?}", battle.wildcard_type);
        }

        // Calculate damage
        let mut damage = calculate_damage(
            attacker_char,
            defender_char,
            battle,
            is_player1,
            use_special,
            clock.unix_timestamp,
        )?;

        // Apply stance modifiers
        let (attacker_stance, defender_stance) = if is_player1 {
            (battle.player1_stance, battle.player2_stance)
        } else {
            (battle.player2_stance, battle.player1_stance)
        };

        damage = apply_stance_modifiers(damage, attacker_stance, defender_stance, is_player1, battle);

        // Apply wildcard effects
        if battle.wildcard_active {
            damage = apply_wildcard_effects(damage, battle, is_player1, clock.unix_timestamp)?;
        }

        // Apply damage
        if is_player1 {
            battle.player2_hp = battle.player2_hp.saturating_sub(damage);
            
            // Apply reflection damage
            if battle.player1_reflection > 0 {
                let reflected = (damage * battle.player1_reflection as u64) / 100;
                battle.player1_hp = battle.player1_hp.saturating_sub(reflected);
                msg!("Player 1 takes {} reflected damage", reflected);
            }
        } else {
            battle.player1_hp = battle.player1_hp.saturating_sub(damage);
            
            // Apply reflection damage
            if battle.player2_reflection > 0 {
                let reflected = (damage * battle.player2_reflection as u64) / 100;
                battle.player2_hp = battle.player2_hp.saturating_sub(reflected);
                msg!("Player 2 takes {} reflected damage", reflected);
            }
        }

        msg!("Damage dealt: {}", damage);

        // Check for battle end
        if battle.player1_hp == 0 || battle.player2_hp == 0 {
            battle.is_finished = true;
            battle.winner = if battle.player1_hp > 0 { Some(1) } else { Some(2) };
            msg!("Battle finished! Winner: Player {}", battle.winner.unwrap());
        }

        // Switch turns
        battle.current_turn = if battle.current_turn == 1 { 2 } else { 1 };
        battle.turn_number += 1;
        battle.wildcard_active = false;

        Ok(())
    }

    // Finalize battle and distribute rewards
    pub fn finalize_battle(ctx: Context<FinalizeBattle>) -> Result<()> {
        let battle = &ctx.accounts.battle;
        let player1_char = &mut ctx.accounts.player1_character;
        let player2_char = &mut ctx.accounts.player2_character;

        require!(battle.is_finished, GameError::BattleNotFinished);
        require!(battle.winner.is_some(), GameError::NoWinner);

        let winner_is_player1 = battle.winner.unwrap() == 1;

        // Calculate XP reward
        let level_diff = (player1_char.level as i32 - player2_char.level as i32).abs() as u64;
        let base_xp = match battle.match_type {
            MatchType::Casual => 50,
            MatchType::Ranked => 100,
            MatchType::Tournament => 200,
            MatchType::Staked => 150,
        };

        let xp_bonus = if level_diff > 5 { 50 } else { level_diff * 10 };
        let total_xp = base_xp + xp_bonus;

        // Update stats based on winner
        if winner_is_player1 {
            // Player 1 wins
            player1_char.xp += total_xp;
            player1_char.total_wins += 1;
            player1_char.current_hp = player1_char.max_hp;

            player2_char.total_losses += 1;
            player2_char.current_hp = player2_char.max_hp;

            // Check for level up
            let required_xp = get_required_xp(player1_char.level);
            if player1_char.xp >= required_xp && player1_char.level < 50 {
                player1_char.level += 1;
                player1_char.xp -= required_xp;
                player1_char.max_hp += 5;
                player1_char.current_hp = player1_char.max_hp;
                player1_char.base_damage_min += 2;
                player1_char.base_damage_max += 2;
                player1_char.crit_chance += 1;
                player1_char.defense += 1;
                msg!("{} leveled up to level {}!", player1_char.name, player1_char.level);
            }

            let winner_mmr_gain = 25 + (level_diff * 5);
            let loser_mmr_loss = 15 + (level_diff * 3);
            player1_char.mmr += winner_mmr_gain;
            player2_char.mmr = player2_char.mmr.saturating_sub(loser_mmr_loss);

            msg!("Battle finalized. {} gained {} XP and {} MMR", 
                player1_char.name, total_xp, winner_mmr_gain);
        } else {
            // Player 2 wins
            player2_char.xp += total_xp;
            player2_char.total_wins += 1;
            player2_char.current_hp = player2_char.max_hp;

            player1_char.total_losses += 1;
            player1_char.current_hp = player1_char.max_hp;

            // Check for level up
            let required_xp = get_required_xp(player2_char.level);
            if player2_char.xp >= required_xp && player2_char.level < 50 {
                player2_char.level += 1;
                player2_char.xp -= required_xp;
                player2_char.max_hp += 5;
                player2_char.current_hp = player2_char.max_hp;
                player2_char.base_damage_min += 2;
                player2_char.base_damage_max += 2;
                player2_char.crit_chance += 1;
                player2_char.defense += 1;
                msg!("{} leveled up to level {}!", player2_char.name, player2_char.level);
            }

            let winner_mmr_gain = 25 + (level_diff * 5);
            let loser_mmr_loss = 15 + (level_diff * 3);
            player2_char.mmr += winner_mmr_gain;
            player1_char.mmr = player1_char.mmr.saturating_sub(loser_mmr_loss);

            msg!("Battle finalized. {} gained {} XP and {} MMR", 
                player2_char.name, total_xp, winner_mmr_gain);
        }

        Ok(())
    }

    // Create a betting pool for a battle
    pub fn create_betting_pool(ctx: Context<CreateBettingPool>) -> Result<()> {
        let pool = &mut ctx.accounts.betting_pool;
        let battle = &ctx.accounts.battle;
        let clock = Clock::get()?;

        require!(!battle.is_finished, GameError::BattleAlreadyFinished);

        // Initialize all pool fields
        pool.battle = battle.key();
        pool.total_pool = 0;
        pool.player1_bets = 0;
        pool.player2_bets = 0;
        pool.house_edge = 5; // 5% house edge
        pool.is_settled = false;
        pool.created_at = clock.unix_timestamp;

        // Calculate initial odds based on character stats
        let player1_char = &ctx.accounts.player1_character;
        let player2_char = &ctx.accounts.player2_character;

        let player1_score = calculate_betting_score(player1_char, battle.player1_hp);
        let player2_score = calculate_betting_score(player2_char, battle.player2_hp);

        pool.player1_odds = (player2_score * 100) / (player1_score + player2_score);
        pool.player2_odds = (player1_score * 100) / (player1_score + player2_score);

        msg!("Betting pool created. Odds - P1: {}%, P2: {}%", 
            pool.player1_odds, pool.player2_odds);

        Ok(())
    }

    // Place a bet on a battle
    pub fn place_bet(
        ctx: Context<PlaceBet>,
        amount: u64,
        bet_on_player: u8,
    ) -> Result<()> {
        require!(bet_on_player == 1 || bet_on_player == 2, GameError::InvalidBetTarget);
        require!(amount > 0, GameError::InvalidBetAmount);

        let battle = &ctx.accounts.battle;

        require!(!battle.is_finished, GameError::BattleAlreadyFinished);
        require!(!ctx.accounts.betting_pool.is_settled, GameError::PoolAlreadySettled);

        // Transfer SOL from bettor to pool
        let cpi_context = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            system_program::Transfer {
                from: ctx.accounts.bettor.to_account_info(),
                to: ctx.accounts.betting_pool.to_account_info(),
            },
        );
        system_program::transfer(cpi_context, amount)?;

        let pool = &mut ctx.accounts.betting_pool;
        let bet = &mut ctx.accounts.bet;

        // Initialize bet record
        bet.bettor = ctx.accounts.bettor.key();
        bet.betting_pool = pool.key();
        bet.amount = amount;
        bet.bet_on_player = bet_on_player;
        bet.is_claimed = false;

        // Update pool totals
        pool.total_pool += amount;
        if bet_on_player == 1 {
            pool.player1_bets += amount;
        } else {
            pool.player2_bets += amount;
        }

        // Recalculate odds based on betting volume
        if pool.player1_bets > 0 && pool.player2_bets > 0 {
            let total = pool.player1_bets + pool.player2_bets;
            pool.player1_odds = (pool.player2_bets * 100) / total;
            pool.player2_odds = (pool.player1_bets * 100) / total;
        }

        msg!("Bet placed: {} SOL on Player {}", amount, bet_on_player);
        Ok(())
    }

    // Settle betting pool after battle
    pub fn settle_betting_pool(ctx: Context<SettleBettingPool>) -> Result<()> {
        let pool = &mut ctx.accounts.betting_pool;
        let battle = &ctx.accounts.battle;

        require!(battle.is_finished, GameError::BattleNotFinished);
        require!(!pool.is_settled, GameError::PoolAlreadySettled);
        require!(battle.winner.is_some(), GameError::NoWinner);

        pool.is_settled = true;
        pool.winner = battle.winner;

        msg!("Betting pool settled. Winner: Player {}", battle.winner.unwrap());
        Ok(())
    }

    // Claim betting winnings
    pub fn claim_bet_winnings(ctx: Context<ClaimBetWinnings>) -> Result<()> {
        let pool = &ctx.accounts.betting_pool;
        let bet = &mut ctx.accounts.bet;

        require!(pool.is_settled, GameError::PoolNotSettled);
        require!(!bet.is_claimed, GameError::AlreadyClaimed);
        require!(bet.bettor == ctx.accounts.bettor.key(), GameError::NotBetOwner);

        // Check if bet won
        let won = pool.winner == Some(bet.bet_on_player);
        require!(won, GameError::BetLost);

        // Calculate winnings
        let winning_pool = if bet.bet_on_player == 1 {
            pool.player1_bets
        } else {
            pool.player2_bets
        };

        let house_cut = (pool.total_pool * pool.house_edge as u64) / 100;
        let distributable = pool.total_pool - house_cut;
        let winnings = (bet.amount * distributable) / winning_pool;

        // Transfer winnings
        **ctx.accounts.betting_pool.to_account_info().try_borrow_mut_lamports()? -= winnings;
        **ctx.accounts.bettor.to_account_info().try_borrow_mut_lamports()? += winnings;

        bet.is_claimed = true;

        msg!("Winnings claimed: {} SOL", winnings);
        Ok(())
    }

    // Heal character (costs SOL)
    pub fn heal_character(ctx: Context<HealCharacter>) -> Result<()> {
        require!(ctx.accounts.character.current_hp < ctx.accounts.character.max_hp, GameError::AlreadyFullHealth);

        let heal_cost = 1_000_000; // 0.001 SOL per heal

        // Transfer SOL for healing
        let cpi_context = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            system_program::Transfer {
                from: ctx.accounts.owner.to_account_info(),
                to: ctx.accounts.character.to_account_info(),
            },
        );
        system_program::transfer(cpi_context, heal_cost)?;

        let character = &mut ctx.accounts.character;
        character.current_hp = character.max_hp;

        msg!("{} fully healed!", character.name);
        Ok(())
    }
}

// Helper functions
fn generate_random_u8(timestamp: i64, seed1: u64, seed2: u64) -> u8 {
    let combined = timestamp as u64 ^ seed1 ^ seed2;
    ((combined >> 8) ^ (combined >> 16) ^ (combined >> 24)) as u8
}

fn calculate_damage(
    attacker: &Character,
    defender: &Character,
    battle: &Battle,
    is_player1: bool,
    use_special: bool,
    timestamp: i64,
) -> Result<u64> {
    let mut damage: u64;

    // Base damage roll
    let damage_range = attacker.base_damage_max - attacker.base_damage_min;
    let roll = generate_random_u8(timestamp, battle.turn_number as u64, 3) as u64;
    let base_damage = attacker.base_damage_min as u64 + (roll % (damage_range as u64 + 1));

    // Level scaling
    let level_bonus = (attacker.level as u64 - 1) * 2;
    damage = base_damage + level_bonus;

    // Check for critical hit
    let crit_roll = generate_random_u8(timestamp, battle.turn_number as u64, 4) % 100;
    let mut crit_chance = attacker.crit_chance as u64;

    // Gambler's Fallacy wildcard effect
    if battle.wildcard_type == Some(WildcardEvent::GamblersFallacy) {
        let miss_count = if is_player1 { battle.player1_miss_count } else { battle.player2_miss_count };
        crit_chance += miss_count as u64 * 5;
    }

    let is_crit = (crit_roll as u64) < crit_chance;
    if is_crit {
        damage = match attacker.character_class {
            CharacterClass::Warrior => damage * 2,
            CharacterClass::Assassin => damage * 3,
            CharacterClass::Mage => damage * 2,
            CharacterClass::Tank => damage * 2,
        };
        msg!("Critical hit! Damage: {}", damage);

        // Instant kill check (5% chance when enemy < 20% HP)
        let defender_hp = if is_player1 { battle.player2_hp } else { battle.player1_hp };
        let defender_max_hp = defender.max_hp as u64;
        if defender_hp < (defender_max_hp * 20) / 100 {
            let instant_kill_roll = generate_random_u8(timestamp, battle.turn_number as u64, 5) % 100;
            if instant_kill_roll < 5 {
                damage = defender_hp;
                msg!("INSTANT KILL!");
            }
        }
    }

    // Apply combo bonus
    let combo = if is_player1 { battle.player1_combo } else { battle.player2_combo };
    if combo > 0 {
        let combo_bonus = (damage * 15 * combo as u64) / 100;
        damage += combo_bonus;
        msg!("Combo x{}: +{} damage", combo, combo_bonus);
    }

    // Special move
    if use_special {
        damage = match attacker.character_class {
            CharacterClass::Warrior => damage * 2, // Berserker Rage
            CharacterClass::Assassin => damage * 3, // Shadow Strike
            CharacterClass::Mage => {
                // Arcane Burst - apply DOT
                damage * 2
            }
            CharacterClass::Tank => damage, // Fortress Stance - defensive
        };
        msg!("Special move used!");
    }

    // Apply defense reduction
    let defense_reduction = defender.defense as u64;
    damage = damage.saturating_sub(defense_reduction);

    // Check for dodge
    let dodge_roll = generate_random_u8(timestamp, battle.turn_number as u64, 6) % 100;
    if (dodge_roll as u64) < defender.dodge_chance as u64 {
        damage = 0;
        msg!("Attack dodged!");
    }

    Ok(damage)
}

fn apply_stance_modifiers(
    mut damage: u64,
    attacker_stance: BattleStance,
    defender_stance: BattleStance,
    is_player1: bool,
    battle: &mut Battle,
) -> u64 {
    match attacker_stance {
        BattleStance::Aggressive => {
            damage = (damage * 130) / 100; // +30% damage
        }
        BattleStance::Defensive => {
            damage = (damage * 70) / 100; // -30% damage
        }
        BattleStance::Berserker => {
            damage = damage * 2; // 2x damage
            // Self-damage 25%
            let self_damage = (damage * 25) / 100;
            if is_player1 {
                battle.player1_hp = battle.player1_hp.saturating_sub(self_damage);
            } else {
                battle.player2_hp = battle.player2_hp.saturating_sub(self_damage);
            }
            msg!("Berserker stance: {} self-damage", self_damage);
        }
        BattleStance::Counter => {
            // Counter only works if attacked
            if defender_stance == BattleStance::Aggressive {
                damage = (damage * 150) / 100; // 1.5x counter
            } else {
                damage = 0; // Miss if not attacked
                msg!("Counter stance missed!");
            }
        }
        BattleStance::Balanced => {}
    }

    // Defender stance modifiers
    match defender_stance {
        BattleStance::Defensive => {
            damage = (damage * 50) / 100; // +50% defense = 50% damage taken
        }
        BattleStance::Aggressive => {
            damage = (damage * 150) / 100; // -50% defense = 150% damage taken
        }
        _ => {}
    }

    damage
}

fn apply_wildcard_effects(
    mut damage: u64,
    battle: &mut Battle,
    is_player1: bool,
    timestamp: i64,
) -> Result<u64> {
    if let Some(wildcard) = battle.wildcard_type {
        match wildcard {
            WildcardEvent::DoubleOrNothing => {
                let roll = generate_random_u8(timestamp, battle.turn_number as u64, 7) % 2;
                if roll == 0 {
                    damage = 0;
                    msg!("Double or Nothing: MISS!");
                } else {
                    damage *= 2;
                    msg!("Double or Nothing: DOUBLE!");
                }
            }
            WildcardEvent::ReverseRoles => {
                // Swap HP percentages
                let p1_percent = (battle.player1_hp * 100) / battle.player1_hp.max(1);
                let p2_percent = (battle.player2_hp * 100) / battle.player2_hp.max(1);
                
                let temp = battle.player1_hp;
                battle.player1_hp = (battle.player1_hp * p2_percent) / 100;
                battle.player2_hp = (temp * p1_percent) / 100;
                msg!("Reverse Roles: HP swapped!");
            }
            WildcardEvent::MysteryBox => {
                let buff_roll = generate_random_u8(timestamp, battle.turn_number as u64, 8) % 4;
                match buff_roll {
                    0 => {
                        damage *= 3;
                        msg!("Mystery Box: Triple damage!");
                    }
                    1 => {
                        if is_player1 {
                            battle.player1_reflection = 50;
                        } else {
                            battle.player2_reflection = 50;
                        }
                        msg!("Mystery Box: 50% damage reflection!");
                    }
                    2 => {
                        if is_player1 {
                            battle.player1_hp += 50;
                        } else {
                            battle.player2_hp += 50;
                        }
                        msg!("Mystery Box: +50 HP!");
                    }
                    _ => {
                        if is_player1 {
                            battle.player1_combo += 3;
                        } else {
                            battle.player2_combo += 3;
                        }
                        msg!("Mystery Box: +3 combo!");
                    }
                }
            }
            WildcardEvent::DeathRoulette => {
                let roll = generate_random_u8(timestamp, battle.turn_number as u64, 9) % 2;
                if roll == 0 {
                    if is_player1 {
                        battle.player1_hp = 0;
                    } else {
                        battle.player2_hp = 0;
                    }
                    msg!("Death Roulette: INSTANT DEATH!");
                } else {
                    if is_player1 {
                        battle.player1_hp = 999;
                    } else {
                        battle.player2_hp = 999;
                    }
                    msg!("Death Roulette: FULL HEAL!");
                }
            }
            WildcardEvent::ComboBreaker => {
                if is_player1 {
                    let stolen = battle.player2_combo;
                    battle.player1_combo += stolen;
                    battle.player2_combo = 0;
                    msg!("Combo Breaker: Stole {} combo!", stolen);
                } else {
                    let stolen = battle.player1_combo;
                    battle.player2_combo += stolen;
                    battle.player1_combo = 0;
                    msg!("Combo Breaker: Stole {} combo!", stolen);
                }
            }
            WildcardEvent::TimeWarp => {
                // Rewind one turn (restore some HP)
                if is_player1 {
                    battle.player2_hp += damage.min(50);
                } else {
                    battle.player1_hp += damage.min(50);
                }
                damage = 0;
                msg!("Time Warp: Turn rewound!");
            }
            WildcardEvent::LuckySeven => {
                if battle.last_damage_roll == 7 {
                    damage *= 7;
                    msg!("Lucky Seven: 7x damage!");
                }
            }
            WildcardEvent::GamblersFallacy => {
                // Handled in calculate_damage
            }
        }
    }

    Ok(damage)
}

fn calculate_betting_score(character: &Character, current_hp: u64) -> u64 {
    let hp_percent = (current_hp * 100) / character.max_hp as u64;
    let win_rate = if character.total_wins + character.total_losses > 0 {
        (character.total_wins * 100) / (character.total_wins + character.total_losses)
    } else {
        50
    };

    let level_score = character.level as u64 * 10;
    let hp_score = hp_percent;
    let win_score = win_rate as u64;
    let mmr_score = character.mmr / 10;

    level_score + hp_score + win_score + mmr_score
}

fn get_required_xp(level: u16) -> u64 {
    let xp_curve: [u64; 11] = [0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200, 4000];
    
    if level < 11 {
        xp_curve[level as usize]
    } else {
        // For levels 11-50, use formula
        4000 + ((level as u64 - 10) * 500)
    }
}

// Account contexts
#[derive(Accounts)]
#[instruction(character_class: CharacterClass, name: String)]
pub struct CreateCharacter<'info> {
    #[account(
        init,
        payer = owner,
        space = 8 + Character::INIT_SPACE,
        seeds = [b"character", name.as_bytes(), owner.key().as_ref()],
        bump
    )]
    pub character: Account<'info, Character>,
    #[account(mut)]
    pub owner: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CreateBattle<'info> {
    #[account(
        init,
        payer = player1_owner,
        space = 8 + Battle::INIT_SPACE,
        seeds = [b"battle", player1_character.key().as_ref(), player2_character.key().as_ref()],
        bump
    )]
    pub battle: Account<'info, Battle>,
    #[account(mut)]
    pub player1_character: Account<'info, Character>,
    pub player2_character: Account<'info, Character>,
    #[account(mut)]
    pub player1_owner: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ExecuteTurn<'info> {
    #[account(mut)]
    pub battle: Account<'info, Battle>,
    #[account(mut)]
    pub attacker_character: Account<'info, Character>,
    pub defender_character: Account<'info, Character>,
    pub attacker: Signer<'info>,
}

#[derive(Accounts)]
pub struct FinalizeBattle<'info> {
    #[account(mut)]
    pub battle: Account<'info, Battle>,
    #[account(mut)]
    pub player1_character: Account<'info, Character>,
    #[account(mut)]
    pub player2_character: Account<'info, Character>,
}

#[derive(Accounts)]
pub struct CreateBettingPool<'info> {
    #[account(
        init,
        payer = creator,
        space = 8 + BettingPool::INIT_SPACE,
        seeds = [b"betting_pool", battle.key().as_ref()],
        bump
    )]
    pub betting_pool: Account<'info, BettingPool>,
    pub battle: Account<'info, Battle>,
    pub player1_character: Account<'info, Character>,
    pub player2_character: Account<'info, Character>,
    #[account(mut)]
    pub creator: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PlaceBet<'info> {
    #[account(
        init,
        payer = bettor,
        space = 8 + Bet::INIT_SPACE,
        seeds = [b"bet", betting_pool.key().as_ref(), bettor.key().as_ref()],
        bump
    )]
    pub bet: Account<'info, Bet>,
    #[account(mut)]
    pub betting_pool: Account<'info, BettingPool>,
    pub battle: Account<'info, Battle>,
    #[account(mut)]
    pub bettor: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SettleBettingPool<'info> {
    #[account(mut)]
    pub betting_pool: Account<'info, BettingPool>,
    pub battle: Account<'info, Battle>,
}

#[derive(Accounts)]
pub struct ClaimBetWinnings<'info> {
    #[account(mut)]
    pub betting_pool: Account<'info, BettingPool>,
    #[account(mut)]
    pub bet: Account<'info, Bet>,
    #[account(mut)]
    pub bettor: Signer<'info>,
}

#[derive(Accounts)]
pub struct HealCharacter<'info> {
    #[account(mut, has_one = owner)]
    pub character: Account<'info, Character>,
    #[account(mut)]
    pub owner: Signer<'info>,
    pub system_program: Program<'info, System>,
}

// State accounts
#[account]
#[derive(InitSpace)]
pub struct Character {
    pub owner: Pubkey,
    pub character_class: CharacterClass,
    #[max_len(32)]
    pub name: String,
    pub level: u16,
    pub xp: u64,
    pub max_hp: u64,
    pub current_hp: u64,
    pub base_damage_min: u16,
    pub base_damage_max: u16,
    pub crit_chance: u16,
    pub dodge_chance: u16,
    pub defense: u16,
    pub total_wins: u32,
    pub total_losses: u32,
    pub max_combo: u16,
    pub mmr: u64,
    pub special_cooldown: u8,
    pub created_at: i64,
    pub last_battle: i64,
}

#[account]
#[derive(InitSpace)]
pub struct Battle {
    pub player1: Pubkey,
    pub player2: Pubkey,
    pub match_type: MatchType,
    pub stake_amount: u64,
    pub created_at: i64,
    pub turn_number: u32,
    pub current_turn: u8,
    pub is_finished: bool,
    pub winner: Option<u8>,
    
    // Battle state
    pub player1_hp: u64,
    pub player2_hp: u64,
    pub player1_combo: u16,
    pub player2_combo: u16,
    pub player1_stance: BattleStance,
    pub player2_stance: BattleStance,
    pub player1_dot_damage: u64,
    pub player2_dot_damage: u64,
    pub player1_dot_turns: u8,
    pub player2_dot_turns: u8,
    pub player1_reflection: u16,
    pub player2_reflection: u16,
    pub player1_miss_count: u16,
    pub player2_miss_count: u16,
    pub last_damage_roll: u8,
    pub wildcard_active: bool,
    pub wildcard_type: Option<WildcardEvent>,
}

#[account]
#[derive(InitSpace)]
pub struct BettingPool {
    pub battle: Pubkey,
    pub total_pool: u64,
    pub player1_bets: u64,
    pub player2_bets: u64,
    pub player1_odds: u64,
    pub player2_odds: u64,
    pub house_edge: u8,
    pub is_settled: bool,
    pub winner: Option<u8>,
    pub created_at: i64,
}

#[account]
#[derive(InitSpace)]
pub struct Bet {
    pub bettor: Pubkey,
    pub betting_pool: Pubkey,
    pub amount: u64,
    pub bet_on_player: u8,
    pub is_claimed: bool,
}

// Enums
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum CharacterClass {
    Warrior,
    Assassin,
    Mage,
    Tank,
}

impl CharacterClass {
    pub fn to_string(&self) -> &str {
        match self {
            CharacterClass::Warrior => "Warrior",
            CharacterClass::Assassin => "Assassin",
            CharacterClass::Mage => "Mage",
            CharacterClass::Tank => "Tank",
        }
    }
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum MatchType {
    Casual,
    Ranked,
    Tournament,
    Staked,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum BattleStance {
    Aggressive,
    Defensive,
    Balanced,
    Berserker,
    Counter,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum WildcardEvent {
    DoubleOrNothing,
    ReverseRoles,
    MysteryBox,
    DeathRoulette,
    ComboBreaker,
    TimeWarp,
    LuckySeven,
    GamblersFallacy,
}



// Error codes
#[error_code]
pub enum GameError {
    #[msg("Name is too long (max 32 characters)")]
    NameTooLong,
    #[msg("Battle has already finished")]
    BattleAlreadyFinished,
    #[msg("Not your turn")]
    NotYourTurn,
    #[msg("Battle is not finished yet")]
    BattleNotFinished,
    #[msg("No winner determined")]
    NoWinner,
    #[msg("Invalid bet target (must be 1 or 2)")]
    InvalidBetTarget,
    #[msg("Invalid bet amount")]
    InvalidBetAmount,
    #[msg("Pool already settled")]
    PoolAlreadySettled,
    #[msg("Pool not settled yet")]
    PoolNotSettled,
    #[msg("Bet already claimed")]
    AlreadyClaimed,
    #[msg("Not the bet owner")]
    NotBetOwner,
    #[msg("Bet lost")]
    BetLost,
    #[msg("Character already at full health")]
    AlreadyFullHealth,
}
