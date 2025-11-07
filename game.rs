use anchor_lang::prelude::*;
use anchor_lang::system_program;
use anchor_lang::solana_program::hash::hash;

declare_id!("4hmtAprg26SJgUKURwVMscyMv9mTtHnbvxaAXy6VJrr8");

const TURN_TIMEOUT_SECONDS: i64 = 30;
const BATTLE_EXPIRY_SECONDS: i64 = 3600; // 1 hour
const WILDCARD_DECISION_TIMEOUT: i64 = 10; // 10 seconds to decide

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
        character.rank_tier = RankTier::Bronze;
        character.season_wins = 0;
        character.season_losses = 0;
        character.achievements = vec![];

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
            CharacterClass::Trickster => {
                character.max_hp = 100;
                character.current_hp = 100;
                character.base_damage_min = 9;
                character.base_damage_max = 16;
                character.crit_chance = 25;
                character.dodge_chance = 15;
            }
        }

        character.defense = 0;
        character.special_cooldown = 0;
        character.mmr = 1000; // Starting MMR
        character.metadata_uri = String::new();

        emit!(CharacterCreated {
            character: character.key(),
            owner: character.owner,
            class: character_class,
            name: character.name.clone(),
        });

        msg!("Character created: {} ({})", character.name, character_class.to_string());
        Ok(())
    }

    // Join matchmaking queue
    pub fn join_queue(
        ctx: Context<JoinQueue>,
        match_type: MatchType,
        stake_amount: u64,
    ) -> Result<()> {
        let queue_entry = &mut ctx.accounts.queue_entry;
        let character = &ctx.accounts.character;
        let clock = Clock::get()?;

        require!(character.current_hp > 0, GameError::CharacterDead);

        // If staked match, lock the SOL
        if stake_amount > 0 {
            let cpi_context = CpiContext::new(
                ctx.accounts.system_program.to_account_info(),
                system_program::Transfer {
                    from: ctx.accounts.player.to_account_info(),
                    to: queue_entry.to_account_info(),
                },
            );
            system_program::transfer(cpi_context, stake_amount)?;
        }

        queue_entry.player = character.owner;
        queue_entry.character = character.key();
        queue_entry.mmr = character.mmr;
        queue_entry.match_type = match_type;
        queue_entry.stake_amount = stake_amount;
        queue_entry.joined_at = clock.unix_timestamp;
        queue_entry.matched = false;

        emit!(QueueJoined {
            player: character.owner,
            character: character.key(),
            mmr: character.mmr,
            match_type,
        });

        msg!("{} joined queue (MMR: {})", character.name, character.mmr);
        Ok(())
    }

    // Create battle from queue match or direct challenge
    pub fn create_battle(
        ctx: Context<CreateBattle>,
        match_type: MatchType,
        stake_amount: u64,
        is_vs_ai: bool,
    ) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let clock = Clock::get()?;

        require!(
            ctx.accounts.player1_character.current_hp > 0,
            GameError::CharacterDead
        );

        if !is_vs_ai {
            require!(
                ctx.accounts.player2_character.current_hp > 0,
                GameError::CharacterDead
            );
        }

        // Lock stakes if applicable
        if stake_amount > 0 {
            let cpi_context = CpiContext::new(
                ctx.accounts.system_program.to_account_info(),
                system_program::Transfer {
                    from: ctx.accounts.player1_owner.to_account_info(),
                    to: battle.to_account_info(),
                },
            );
            system_program::transfer(cpi_context, stake_amount)?;

            if !is_vs_ai {
                let cpi_context2 = CpiContext::new(
                    ctx.accounts.system_program.to_account_info(),
                    system_program::Transfer {
                        from: ctx.accounts.player2_owner.to_account_info(),
                        to: battle.to_account_info(),
                    },
                );
                system_program::transfer(cpi_context2, stake_amount)?;
            }
        }

        battle.player1 = ctx.accounts.player1_character.key();
        battle.player2 = ctx.accounts.player2_character.key();
        battle.match_type = match_type;
        battle.stake_amount = stake_amount;
        battle.created_at = clock.unix_timestamp;
        battle.turn_number = 0;
        battle.current_turn = 1;
        battle.is_finished = false;
        battle.winner = None;
        battle.is_vs_ai = is_vs_ai;
        battle.abandoned = false;
        battle.last_action_time = clock.unix_timestamp;

        battle.player1_hp = ctx.accounts.player1_character.max_hp;
        battle.player2_hp = ctx.accounts.player2_character.max_hp;
        battle.player1_combo = 0;
        battle.player2_combo = 0;
        battle.player1_stance = BattleStance::Balanced;
        battle.player2_stance = BattleStance::Balanced;
        battle.player1_stance_committed = false;
        battle.player2_stance_committed = false;
        battle.player1_stance_hash = [0u8; 32];
        battle.player2_stance_hash = [0u8; 32];
        battle.player1_dot_damage = 0;
        battle.player2_dot_damage = 0;
        battle.player1_dot_turns = 0;
        battle.player2_dot_turns = 0;
        battle.player1_reflection = 0;
        battle.player2_reflection = 0;
        battle.player1_miss_count = 0;
        battle.player2_miss_count = 0;
        battle.player1_special_cooldown = 0;
        battle.player2_special_cooldown = 0;
        battle.last_damage_roll = 0;
        battle.wildcard_active = false;
        battle.wildcard_type = None;
        battle.wildcard_decision_deadline = 0;
        battle.wildcard_player1_decision = None;
        battle.wildcard_player2_decision = None;
        battle.battle_log = vec![];

        emit!(BattleCreated {
            battle: battle.key(),
            player1: battle.player1,
            player2: battle.player2,
            match_type,
            is_vs_ai,
        });

        msg!("Battle created between {} and {}", 
            ctx.accounts.player1_character.name,
            if is_vs_ai { "AI" } else { &ctx.accounts.player2_character.name }
        );
        Ok(())
    }

    // Commit stance (hidden commitment phase)
    pub fn commit_stance(
        ctx: Context<CommitStance>,
        stance_hash: [u8; 32],
    ) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let character = &ctx.accounts.character;
        let clock = Clock::get()?;

        require!(!battle.is_finished, GameError::BattleAlreadyFinished);
        check_battle_timeout(battle, &clock)?;

        let is_player1 = battle.player1 == character.key();
        require!(
            (is_player1 && battle.current_turn == 1) || (!is_player1 && battle.current_turn == 2),
            GameError::NotYourTurn
        );

        if is_player1 {
            require!(!battle.player1_stance_committed, GameError::AlreadyCommitted);
            battle.player1_stance_hash = stance_hash;
            battle.player1_stance_committed = true;
        } else {
            require!(!battle.player2_stance_committed, GameError::AlreadyCommitted);
            battle.player2_stance_hash = stance_hash;
            battle.player2_stance_committed = true;
        }

        battle.last_action_time = clock.unix_timestamp;

        emit!(StanceCommitted {
            battle: battle.key(),
            player: character.owner,
            turn: battle.turn_number,
        });

        msg!("{} committed stance for turn {}", character.name, battle.turn_number);
        Ok(())
    }

    // Reveal stance and execute turn
    pub fn reveal_and_execute_turn(
        ctx: Context<ExecuteTurn>,
        stance: BattleStance,
        salt: u64,
        use_special: bool,
    ) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let attacker_char = &ctx.accounts.attacker_character;
        let defender_char = &ctx.accounts.defender_character;
        let clock = Clock::get()?;

        require!(!battle.is_finished, GameError::BattleAlreadyFinished);
        check_battle_timeout(battle, &clock)?;

        let is_player1 = battle.player1 == attacker_char.key();
        require!(
            (is_player1 && battle.current_turn == 1) || (!is_player1 && battle.current_turn == 2),
            GameError::NotYourTurn
        );

        // Verify stance commitment
        let computed_hash = hash(&[&stance.to_bytes()[..], &salt.to_le_bytes()].concat()).to_bytes();
        if is_player1 {
            require!(
                battle.player1_stance_hash == computed_hash,
                GameError::InvalidStanceReveal
            );
        } else {
            require!(
                battle.player2_stance_hash == computed_hash,
                GameError::InvalidStanceReveal
            );
        }

        // Check special cooldown
        if use_special {
            let cooldown = if is_player1 {
                battle.player1_special_cooldown
            } else {
                battle.player2_special_cooldown
            };
            require!(cooldown == 0, GameError::SpecialOnCooldown);
        }

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
            log_battle_event(battle, format!("Player 1 takes {} DOT damage", battle.player1_dot_damage));
        } else if !is_player1 && battle.player2_dot_turns > 0 {
            battle.player2_hp = battle.player2_hp.saturating_sub(battle.player2_dot_damage);
            battle.player2_dot_turns -= 1;
            log_battle_event(battle, format!("Player 2 takes {} DOT damage", battle.player2_dot_damage));
        }

        // Trickster ability: Manipulate wildcard chance
        let mut wildcard_chance = 10u8; // Base 10%
        if attacker_char.character_class == CharacterClass::Trickster {
            wildcard_chance = 25; // Tricksters have 25% wildcard chance
            log_battle_event(battle, "Trickster's wildcard manipulation active!".to_string());
        }

        // Check for wildcard event
        let wildcard_roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 1) % 100;
        if wildcard_roll < wildcard_chance && !battle.wildcard_active {
            let wildcard_type_roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 2) % 8;
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

            // Check if wildcard requires decision
            if requires_decision(battle.wildcard_type.unwrap()) {
                battle.wildcard_active = true;
                battle.wildcard_decision_deadline = clock.unix_timestamp + WILDCARD_DECISION_TIMEOUT;
                log_battle_event(battle, format!("Wildcard event triggered: {:?} - Decision required!", battle.wildcard_type.unwrap()));
                
                emit!(WildcardTriggered {
                    battle: battle.key(),
                    wildcard_type: battle.wildcard_type.unwrap(),
                    decision_deadline: battle.wildcard_decision_deadline,
                });
                
                // Don't execute turn yet, wait for decisions
                return Ok(());
            } else {
                battle.wildcard_active = true;
                log_battle_event(battle, format!("Wildcard event triggered: {:?}", battle.wildcard_type.unwrap()));
            }
        }

        // Execute the actual turn
        execute_battle_turn(battle, attacker_char, defender_char, is_player1, use_special, &clock)?;

        battle.last_action_time = clock.unix_timestamp;

        // Reset commitments for next turn
        battle.player1_stance_committed = false;
        battle.player2_stance_committed = false;
        battle.player1_stance_hash = [0u8; 32];
        battle.player2_stance_hash = [0u8; 32];

        Ok(())
    }

    // Decide on risky wildcard
    pub fn decide_wildcard(
        ctx: Context<DecideWildcard>,
        accept: bool,
    ) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let character = &ctx.accounts.character;
        let clock = Clock::get()?;

        require!(battle.wildcard_active, GameError::NoActiveWildcard);
        require!(
            clock.unix_timestamp <= battle.wildcard_decision_deadline,
            GameError::DecisionTimeout
        );

        let is_player1 = battle.player1 == character.key();

        if is_player1 {
            battle.wildcard_player1_decision = Some(accept);
        } else {
            battle.wildcard_player2_decision = Some(accept);
        }

        emit!(WildcardDecision {
            battle: battle.key(),
            player: character.owner,
            accepted: accept,
        });

        // If both decided, resolve wildcard and continue turn
        if battle.wildcard_player1_decision.is_some() && battle.wildcard_player2_decision.is_some() {
            resolve_wildcard_with_decisions(battle, &clock)?;
        }

        Ok(())
    }

    // Auto-resolve if timeout on wildcard decision
    pub fn resolve_wildcard_timeout(ctx: Context<ResolveWildcardTimeout>) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let clock = Clock::get()?;

        require!(battle.wildcard_active, GameError::NoActiveWildcard);
        require!(
            clock.unix_timestamp > battle.wildcard_decision_deadline,
            GameError::DecisionNotExpired
        );

        // Auto-decline for players who didn't respond
        if battle.wildcard_player1_decision.is_none() {
            battle.wildcard_player1_decision = Some(false);
            log_battle_event(battle, "Player 1 auto-declined wildcard (timeout)".to_string());
        }
        if battle.wildcard_player2_decision.is_none() {
            battle.wildcard_player2_decision = Some(false);
            log_battle_event(battle, "Player 2 auto-declined wildcard (timeout)".to_string());
        }

        resolve_wildcard_with_decisions(battle, &clock)?;

        Ok(())
    }

    // Check and handle battle timeout/abandonment
    pub fn check_timeout(ctx: Context<CheckTimeout>) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let clock = Clock::get()?;

        require!(!battle.is_finished, GameError::BattleAlreadyFinished);

        let time_since_last_action = clock.unix_timestamp - battle.last_action_time;

        if time_since_last_action > TURN_TIMEOUT_SECONDS {
            // Current player forfeits
            battle.is_finished = true;
            battle.abandoned = true;
            battle.winner = Some(if battle.current_turn == 1 { 2 } else { 1 });

            log_battle_event(battle, format!("Player {} forfeited (timeout)", battle.current_turn));

            emit!(BattleAbandoned {
                battle: battle.key(),
                abandoned_by: battle.current_turn,
                winner: battle.winner.unwrap(),
            });

            // Return stakes to winner
            if battle.stake_amount > 0 {
                let winner_key = if battle.winner.unwrap() == 1 {
                    battle.player1
                } else {
                    battle.player2
                };
                
                **battle.to_account_info().try_borrow_mut_lamports()? -= battle.stake_amount * 2;
                **ctx.accounts.winner.to_account_info().try_borrow_mut_lamports()? += battle.stake_amount * 2;
            }
        }

        Ok(())
    }

    // Execute AI turn (for PvE battles)
    pub fn execute_ai_turn(ctx: Context<ExecuteAiTurn>) -> Result<()> {
        let battle = &mut ctx.accounts.battle;
        let player_char = &ctx.accounts.player_character;
        let ai_char = &ctx.accounts.ai_character;
        let clock = Clock::get()?;

        require!(battle.is_vs_ai, GameError::NotAiBattle);
        require!(!battle.is_finished, GameError::BattleAlreadyFinished);
        require!(battle.current_turn == 2, GameError::NotAiTurn);

        // Simple AI logic
        let ai_stance = choose_ai_stance(battle, ai_char, player_char, &clock);
        let ai_use_special = battle.player2_special_cooldown == 0 && battle.player2_hp < (ai_char.max_hp / 2);

        battle.player2_stance = ai_stance;

        execute_battle_turn(battle, ai_char, player_char, false, ai_use_special, &clock)?;

        battle.last_action_time = clock.unix_timestamp;

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

        // Update winner stats
        if winner_is_player1 {
            update_winner_stats(player1_char, total_xp, level_diff)?;
            update_loser_stats(player2_char, level_diff)?;

            // Transfer stakes to winner
            if battle.stake_amount > 0 {
                **battle.to_account_info().try_borrow_mut_lamports()? -= battle.stake_amount * 2;
                **ctx.accounts.player1_owner.to_account_info().try_borrow_mut_lamports()? += battle.stake_amount * 2;
            }

            emit!(BattleFinalized {
                battle: battle.key(),
                winner: battle.player1,
                loser: battle.player2,
                xp_gained: total_xp,
            });
        } else {
            update_winner_stats(player2_char, total_xp, level_diff)?;
            update_loser_stats(player1_char, level_diff)?;

            if battle.stake_amount > 0 && !battle.is_vs_ai {
                **battle.to_account_info().try_borrow_mut_lamports()? -= battle.stake_amount * 2;
                **ctx.accounts.player2_owner.to_account_info().try_borrow_mut_lamports()? += battle.stake_amount * 2;
            }

            emit!(BattleFinalized {
                battle: battle.key(),
                winner: battle.player2,
                loser: battle.player1,
                xp_gained: total_xp,
            });
        }

        Ok(())
    }

    // Heal character (costs SOL)
    pub fn heal_character(ctx: Context<HealCharacter>) -> Result<()> {
        require!(
            ctx.accounts.character.current_hp < ctx.accounts.character.max_hp,
            GameError::AlreadyFullHealth
        );

        let heal_cost = 1_000_000; // 0.001 SOL per heal

        let cpi_context = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            system_program::Transfer {
                from: ctx.accounts.owner.to_account_info(),
                to: ctx.accounts.game_treasury.to_account_info(),
            },
        );
        system_program::transfer(cpi_context, heal_cost)?;

        let character = &mut ctx.accounts.character;
        character.current_hp = character.max_hp;

        emit!(CharacterHealed {
            character: character.key(),
            owner: character.owner,
        });

        msg!("{} fully healed!", character.name);
        Ok(())
    }

    // Create tournament
    pub fn create_tournament(
        ctx: Context<CreateTournament>,
        entry_fee: u64,
        prize_pool: u64,
        max_players: u8,
    ) -> Result<()> {
        let tournament = &mut ctx.accounts.tournament;
        let clock = Clock::get()?;

        tournament.creator = ctx.accounts.creator.key();
        tournament.entry_fee = entry_fee;
        tournament.prize_pool = prize_pool;
        tournament.max_players = max_players;
        tournament.current_players = 0;
        tournament.status = TournamentStatus::Registration;
        tournament.created_at = clock.unix_timestamp;
        tournament.participants = vec![];
        tournament.current_round = 0;
        tournament.winner = None;

        emit!(TournamentCreated {
            tournament: tournament.key(),
            creator: tournament.creator,
            prize_pool,
            max_players,
        });

        Ok(())
    }
}

// Helper functions
fn simple_random(timestamp: i64, seed1: u64, seed2: u64) -> u8 {
    let combined = timestamp as u64 ^ seed1 ^ seed2;
    ((combined >> 8) ^ (combined >> 16) ^ (combined >> 24)) as u8
}

fn check_battle_timeout(battle: &Battle, clock: &Clock) -> Result<()> {
    let time_since_creation = clock.unix_timestamp - battle.created_at;
    require!(
        time_since_creation < BATTLE_EXPIRY_SECONDS,
        GameError::BattleExpired
    );
    Ok(())
}

fn requires_decision(wildcard: WildcardEvent) -> bool {
    matches!(
        wildcard,
        WildcardEvent::DoubleOrNothing | WildcardEvent::DeathRoulette
    )
}

fn log_battle_event(battle: &mut Battle, event: String) {
    if battle.battle_log.len() < 50 {
        battle.battle_log.push(event);
    }
}

fn execute_battle_turn(
    battle: &mut Battle,
    attacker: &Character,
    defender: &Character,
    is_player1: bool,
    use_special: bool,
    clock: &Clock,
) -> Result<()> {
    let mut damage = calculate_damage(
        attacker,
        defender,
        battle,
        is_player1,
        use_special,
        clock.unix_timestamp,
    )?;

    let (attacker_stance, defender_stance) = if is_player1 {
        (battle.player1_stance, battle.player2_stance)
    } else {
        (battle.player2_stance, battle.player1_stance)
    };

    damage = apply_stance_modifiers(damage, attacker_stance, defender_stance, is_player1, battle);

    if battle.wildcard_active && battle.wildcard_type.is_some() {
        damage = apply_wildcard_effects(damage, battle, is_player1, clock.unix_timestamp)?;
    }

    // Apply damage
    if is_player1 {
        battle.player2_hp = battle.player2_hp.saturating_sub(damage);
        
        if battle.player1_reflection > 0 {
            let reflected = (damage * battle.player1_reflection as u64) / 100;
            battle.player1_hp = battle.player1_hp.saturating_sub(reflected);
            log_battle_event(battle, format!("Player 1 takes {} reflected damage", reflected));
        }
    } else {
        battle.player1_hp = battle.player1_hp.saturating_sub(damage);
        
        if battle.player2_reflection > 0 {
            let reflected = (damage * battle.player2_reflection as u64) / 100;
            battle.player2_hp = battle.player2_hp.saturating_sub(reflected);
            log_battle_event(battle, format!("Player 2 takes {} reflected damage", reflected));
        }
    }

    log_battle_event(battle, format!("Damage dealt: {}", damage));

    // Set special cooldown
    if use_special {
        if is_player1 {
            battle.player1_special_cooldown = 3; // 3 turn cooldown
        } else {
            battle.player2_special_cooldown = 3;
        }
    }

    // Reduce cooldowns
    if is_player1 {
        battle.player1_special_cooldown = battle.player1_special_cooldown.saturating_sub(1);
    } else {
        battle.player2_special_cooldown = battle.player2_special_cooldown.saturating_sub(1);
    }

    // Check for battle end
    if battle.player1_hp == 0 || battle.player2_hp == 0 {
        battle.is_finished = true;
        battle.winner = if battle.player1_hp > 0 { Some(1) } else { Some(2) };
        log_battle_event(battle, format!("Battle finished! Winner: Player {}", battle.winner.unwrap()));

        emit!(BattleEnded {
            battle: battle.key(),
            winner: battle.winner.unwrap(),
            total_turns: battle.turn_number,
        });
    }

    // Switch turns
    battle.current_turn = if battle.current_turn == 1 { 2 } else { 1 };
    battle.turn_number += 1;
    battle.wildcard_active = false;

    Ok(())
}

// Continuation of the smart contract - Part 2

fn resolve_wildcard_with_decisions(battle: &mut Battle, clock: &Clock) -> Result<()> {
    let p1_accepts = battle.wildcard_player1_decision.unwrap_or(false);
    let p2_accepts = battle.wildcard_player2_decision.unwrap_or(false);

    if let Some(wildcard) = battle.wildcard_type {
        match wildcard {
            WildcardEvent::DoubleOrNothing => {
                if p1_accepts && p2_accepts {
                    let roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 7) % 2;
                    if roll == 0 {
                        // Both miss next attack
                        log_battle_event(battle, "Double or Nothing: Both MISS next turn!".to_string());
                    } else {
                        // Both get double damage next turn
                        battle.player1_combo += 2;
                        battle.player2_combo += 2;
                        log_battle_event(battle, "Double or Nothing: Both get DOUBLE damage!".to_string());
                    }
                } else if p1_accepts {
                    // Only P1 risks
                    let roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 7) % 2;
                    if roll == 0 {
                        battle.player1_miss_count += 1;
                        log_battle_event(battle, "P1 Double or Nothing: MISS!".to_string());
                    } else {
                        battle.player1_combo += 3;
                        log_battle_event(battle, "P1 Double or Nothing: Triple damage!".to_string());
                    }
                } else if p2_accepts {
                    // Only P2 risks
                    let roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 8) % 2;
                    if roll == 0 {
                        battle.player2_miss_count += 1;
                        log_battle_event(battle, "P2 Double or Nothing: MISS!".to_string());
                    } else {
                        battle.player2_combo += 3;
                        log_battle_event(battle, "P2 Double or Nothing: Triple damage!".to_string());
                    }
                }
            }
            WildcardEvent::DeathRoulette => {
                if p1_accepts && p2_accepts {
                    let roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 9) % 2;
                    if roll == 0 {
                        battle.player1_hp = 1; // Nearly dead
                        battle.player2_hp = battle.player2_hp.saturating_add(100); // Healed
                        log_battle_event(battle, "Death Roulette: P1 nearly killed, P2 healed!".to_string());
                    } else {
                        battle.player2_hp = 1;
                        battle.player1_hp = battle.player1_hp.saturating_add(100);
                        log_battle_event(battle, "Death Roulette: P2 nearly killed, P1 healed!".to_string());
                    }
                } else if p1_accepts {
                    let roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 9) % 2;
                    if roll == 0 {
                        battle.player1_hp = 1;
                        log_battle_event(battle, "P1 Death Roulette: Nearly killed!".to_string());
                    } else {
                        battle.player1_hp = 999;
                        log_battle_event(battle, "P1 Death Roulette: Massive heal!".to_string());
                    }
                } else if p2_accepts {
                    let roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 10) % 2;
                    if roll == 0 {
                        battle.player2_hp = 1;
                        log_battle_event(battle, "P2 Death Roulette: Nearly killed!".to_string());
                    } else {
                        battle.player2_hp = 999;
                        log_battle_event(battle, "P2 Death Roulette: Massive heal!".to_string());
                    }
                }
            }
            _ => {}
        }
    }

    // Reset wildcard state
    battle.wildcard_active = false;
    battle.wildcard_player1_decision = None;
    battle.wildcard_player2_decision = None;

    Ok(())
}

fn choose_ai_stance(
    battle: &Battle,
    ai_char: &Character,
    player_char: &Character,
    clock: &Clock,
) -> BattleStance {
    let ai_hp_percent = (battle.player2_hp * 100) / ai_char.max_hp as u64;
    let player_hp_percent = (battle.player1_hp * 100) / player_char.max_hp as u64;

    // Strategic AI decision making
    if ai_hp_percent < 30 {
        // Low HP - play defensive or berserker for desperation
        if simple_random(clock.unix_timestamp, battle.turn_number as u64, 20) % 2 == 0 {
            BattleStance::Defensive
        } else {
            BattleStance::Berserker // All-in
        }
    } else if player_hp_percent < 30 {
        // Player low HP - go aggressive
        BattleStance::Aggressive
    } else if battle.player1_stance == BattleStance::Aggressive {
        // Counter aggressive plays
        BattleStance::Counter
    } else {
        // Default balanced with some randomness
        let roll = simple_random(clock.unix_timestamp, battle.turn_number as u64, 21) % 5;
        match roll {
            0 => BattleStance::Aggressive,
            1 => BattleStance::Defensive,
            2 => BattleStance::Counter,
            3 => BattleStance::Berserker,
            _ => BattleStance::Balanced,
        }
    }
}

fn update_winner_stats(character: &mut Character, xp: u64, level_diff: u64) -> Result<()> {
    character.xp += xp;
    character.total_wins += 1;
    character.season_wins += 1;
    character.current_hp = character.max_hp;

    // Check for achievements
    check_achievements(character);

    // Check for level up
    let required_xp = get_required_xp(character.level);
    if character.xp >= required_xp && character.level < 50 {
        character.level += 1;
        character.xp -= required_xp;
        character.max_hp += 5;
        character.current_hp = character.max_hp;
        character.base_damage_min += 2;
        character.base_damage_max += 2;
        character.crit_chance += 1;
        character.defense += 1;
        msg!("{} leveled up to level {}!", character.name, character.level);
    }

    // Update MMR
    let mmr_gain = 25 + (level_diff * 5);
    character.mmr += mmr_gain;

    // Update rank tier
    update_rank_tier(character);

    Ok(())
}

fn update_loser_stats(character: &mut Character, level_diff: u64) -> Result<()> {
    character.total_losses += 1;
    character.season_losses += 1;
    character.current_hp = character.max_hp;

    // Lose MMR
    let mmr_loss = 15 + (level_diff * 3);
    character.mmr = character.mmr.saturating_sub(mmr_loss);

    // Update rank tier
    update_rank_tier(character);

    Ok(())
}

fn check_achievements(character: &mut Character) {
    // First win
    if character.total_wins == 1 && !character.achievements.contains(&Achievement::FirstWin) {
        character.achievements.push(Achievement::FirstWin);
    }
    
    // 10 wins
    if character.total_wins == 10 && !character.achievements.contains(&Achievement::TenWins) {
        character.achievements.push(Achievement::TenWins);
    }
    
    // 100 wins
    if character.total_wins == 100 && !character.achievements.contains(&Achievement::HundredWins) {
        character.achievements.push(Achievement::HundredWins);
    }
    
    // Flawless (if max HP still)
    if character.current_hp == character.max_hp && !character.achievements.contains(&Achievement::Flawless) {
        character.achievements.push(Achievement::Flawless);
    }
}

fn update_rank_tier(character: &mut Character) {
    character.rank_tier = match character.mmr {
        0..=999 => RankTier::Bronze,
        1000..=1499 => RankTier::Silver,
        1500..=1999 => RankTier::Gold,
        2000..=2499 => RankTier::Platinum,
        2500..=2999 => RankTier::Diamond,
        _ => RankTier::Master,
    };
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

    let damage_range = attacker.base_damage_max - attacker.base_damage_min;
    let roll = simple_random(timestamp, battle.turn_number as u64, 3) as u64;
    let base_damage = attacker.base_damage_min as u64 + (roll % (damage_range as u64 + 1));

    let level_bonus = (attacker.level as u64 - 1) * 2;
    damage = base_damage + level_bonus;

    // Check for critical hit
    let crit_roll = simple_random(timestamp, battle.turn_number as u64, 4) % 100;
    let mut crit_chance = attacker.crit_chance as u64;

    // Gambler's Fallacy effect
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
            CharacterClass::Trickster => {
                // Trickster crits can trigger additional effects
                damage * 2 + 20 // Extra flat damage
            }
        };
        
        // Instant kill check
        let defender_hp = if is_player1 { battle.player2_hp } else { battle.player1_hp };
        let defender_max_hp = defender.max_hp as u64;
        if defender_hp < (defender_max_hp * 20) / 100 {
            let instant_kill_roll = simple_random(timestamp, battle.turn_number as u64, 5) % 100;
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
    }

    // Special moves
    if use_special {
        damage = match attacker.character_class {
            CharacterClass::Warrior => damage * 2, // Berserker Rage
            CharacterClass::Assassin => damage * 3, // Shadow Strike
            CharacterClass::Mage => {
                // Arcane Burst - apply DOT
                if is_player1 {
                    battle.player2_dot_damage = 15;
                    battle.player2_dot_turns = 3;
                } else {
                    battle.player1_dot_damage = 15;
                    battle.player1_dot_turns = 3;
                }
                damage * 2
            }
            CharacterClass::Tank => {
                // Fortress Stance - massive defense boost
                if is_player1 {
                    battle.player1_reflection = 50;
                } else {
                    battle.player2_reflection = 50;
                }
                damage
            }
            CharacterClass::Trickster => {
                // Wild Card special: Random powerful effect
                let effect_roll = simple_random(timestamp, battle.turn_number as u64, 11) % 4;
                match effect_roll {
                    0 => {
                        // Steal combo
                        if is_player1 {
                            let stolen = battle.player2_combo;
                            battle.player1_combo += stolen;
                            battle.player2_combo = 0;
                        } else {
                            let stolen = battle.player1_combo;
                            battle.player2_combo += stolen;
                            battle.player1_combo = 0;
                        }
                        damage * 2
                    }
                    1 => {
                        // Confusion: swap stances
                        let temp = battle.player1_stance;
                        battle.player1_stance = battle.player2_stance;
                        battle.player2_stance = temp;
                        damage * 2
                    }
                    2 => {
                        // Evasion: high dodge chance next turn
                        damage * 3
                    }
                    _ => {
                        // Trigger extra wildcard
                        battle.wildcard_active = true;
                        damage * 2
                    }
                }
            }
        };
        msg!("Special move used!");
    }

    // Apply defense
    let defense_reduction = defender.defense as u64;
    damage = damage.saturating_sub(defense_reduction);

    // Check for dodge
    let dodge_roll = simple_random(timestamp, battle.turn_number as u64, 6) % 100;
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
            damage = (damage * 130) / 100;
        }
        BattleStance::Defensive => {
            damage = (damage * 70) / 100;
        }
        BattleStance::Berserker => {
            damage = damage * 2;
            let self_damage = (damage * 25) / 100;
            if is_player1 {
                battle.player1_hp = battle.player1_hp.saturating_sub(self_damage);
            } else {
                battle.player2_hp = battle.player2_hp.saturating_sub(self_damage);
            }
        }
        BattleStance::Counter => {
            if defender_stance == BattleStance::Aggressive {
                damage = (damage * 150) / 100;
            } else {
                damage = 0;
            }
        }
        BattleStance::Balanced => {}
    }

    match defender_stance {
        BattleStance::Defensive => {
            damage = (damage * 50) / 100;
        }
        BattleStance::Aggressive => {
            damage = (damage * 150) / 100;
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
            WildcardEvent::ReverseRoles => {
                let p1_percent = (battle.player1_hp * 100) / battle.player1_hp.max(1);
                let p2_percent = (battle.player2_hp * 100) / battle.player2_hp.max(1);
                
                let temp = battle.player1_hp;
                battle.player1_hp = (battle.player1_hp * p2_percent) / 100;
                battle.player2_hp = (temp * p1_percent) / 100;
                msg!("Reverse Roles: HP swapped!");
            }
            WildcardEvent::MysteryBox => {
                let buff_roll = simple_random(timestamp, battle.turn_number as u64, 8) % 4;
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
                        msg!("Mystery Box: 50% reflection!");
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
            WildcardEvent::ComboBreaker => {
                if is_player1 {
                    let stolen = battle.player2_combo;
                    battle.player1_combo += stolen;
                    battle.player2_combo = 0;
                } else {
                    let stolen = battle.player1_combo;
                    battle.player2_combo += stolen;
                    battle.player1_combo = 0;
                }
            }
            WildcardEvent::TimeWarp => {
                if is_player1 {
                    battle.player2_hp += damage.min(50);
                } else {
                    battle.player1_hp += damage.min(50);
                }
                damage = 0;
            }
            WildcardEvent::LuckySeven => {
                if battle.last_damage_roll == 7 {
                    damage *= 7;
                    msg!("Lucky Seven: 7x damage!");
                }
            }
            _ => {}
        }
    }

    Ok(damage)
}

fn get_required_xp(level: u16) -> u64 {
    let xp_curve: [u64; 11] = [0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200, 4000];
    
    if level < 11 {
        xp_curve[level as usize]
    } else {
        4000 + ((level as u64 - 10) * 500)
    }
}

// Account contexts
#[derive(Accounts)]
pub struct JoinQueue<'info> {
    #[account(
        init,
        payer = player,
        space = 8 + QueueEntry::INIT_SPACE,
        seeds = [b"queue", character.key().as_ref()],
        bump
    )]
    pub queue_entry: Account<'info, QueueEntry>,
    pub character: Account<'info, Character>,
    #[account(mut)]
    pub player: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CommitStance<'info> {
    #[account(mut)]
    pub battle: Account<'info, Battle>,
    pub character: Account<'info, Character>,
    pub player: Signer<'info>,
}

#[derive(Accounts)]
pub struct DecideWildcard<'info> {
    #[account(mut)]
    pub battle: Account<'info, Battle>,
    pub character: Account<'info, Character>,
    pub player: Signer<'info>,
}

#[derive(Accounts)]
pub struct ResolveWildcardTimeout<'info> {
    #[account(mut)]
    pub battle: Account<'info, Battle>,
}

#[derive(Accounts)]
pub struct CheckTimeout<'info> {
    #[account(mut)]
    pub battle: Account<'info, Battle>,
    /// CHECK: Winner account to receive stakes
    #[account(mut)]
    pub winner: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct ExecuteAiTurn<'info> {
    #[account(mut)]
    pub battle: Account<'info, Battle>,
    pub player_character: Account<'info, Character>,
    pub ai_character: Account<'info, Character>,
}

#[derive(Accounts)]
pub struct CreateTournament<'info> {
    #[account(
        init,
        payer = creator,
        space = 8 + Tournament::INIT_SPACE
    )]
    pub tournament: Account<'info, Tournament>,
    #[account(mut)]
    pub creator: Signer<'info>,
    pub system_program: Program<'info, System>,
}

// Additional state accounts
#[account]
#[derive(InitSpace)]
pub struct QueueEntry {
    pub player: Pubkey,
    pub character: Pubkey,
    pub mmr: u64,
    pub match_type: MatchType,
    pub stake_amount: u64,
    pub joined_at: i64,
    pub matched: bool,
}

#[account]
#[derive(InitSpace)]
pub struct Tournament {
    pub creator: Pubkey,
    pub entry_fee: u64,
    pub prize_pool: u64,
    pub max_players: u8,
    pub current_players: u8,
    pub status: TournamentStatus,
    pub created_at: i64,
    #[max_len(64)]
    pub participants: Vec<Pubkey>,
    pub current_round: u8,
    pub winner: Option<Pubkey>,
}

// Additional enums
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum RankTier {
    Bronze,
    Silver,
    Gold,
    Platinum,
    Diamond,
    Master,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum Achievement {
    FirstWin,
    TenWins,
    HundredWins,
    Flawless,
    ComboMaster,
    TournamentWinner,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum TournamentStatus {
    Registration,
    InProgress,
    Completed,
    Cancelled,
}

impl BattleStance {
    pub fn to_bytes(&self) -> Vec<u8> {
        match self {
            BattleStance::Aggressive => vec![0],
            BattleStance::Defensive => vec![1],
            BattleStance::Balanced => vec![2],
            BattleStance::Berserker => vec![3],
            BattleStance::Counter => vec![4],
        }
    }
}

// Events
#[event]
pub struct CharacterCreated {
    pub character: Pubkey,
    pub owner: Pubkey,
    pub class: CharacterClass,
    pub name: String,
}

#[event]
pub struct QueueJoined {
    pub player: Pubkey,
    pub character: Pubkey,
    pub mmr: u64,
    pub match_type: MatchType,
}

#[event]
pub struct BattleCreated {
    pub battle: Pubkey,
    pub player1: Pubkey,
    pub player2: Pubkey,
    pub match_type: MatchType,
    pub is_vs_ai: bool,
}

#[event]
pub struct StanceCommitted {
    pub battle: Pubkey,
    pub player: Pubkey,
    pub turn: u32,
}

#[event]
pub struct WildcardTriggered {
    pub battle: Pubkey,
    pub wildcard_type: WildcardEvent,
    pub decision_deadline: i64,
}

#[event]
pub struct WildcardDecision {
    pub battle: Pubkey,
    pub player: Pubkey,
    pub accepted: bool,
}

#[event]
pub struct BattleEnded {
    pub battle: Pubkey,
    pub winner: u8,
    pub total_turns: u32,
}

#[event]
pub struct BattleAbandoned {
    pub battle: Pubkey,
    pub abandoned_by: u8,
    pub winner: u8,
}

#[event]
pub struct BattleFinalized {
    pub battle: Pubkey,
    pub winner: Pubkey,
    pub loser: Pubkey,
    pub xp_gained: u64,
}

#[event]
pub struct CharacterHealed {
    pub character: Pubkey,
    pub owner: Pubkey,
}

#[event]
pub struct TournamentCreated {
    pub tournament: Pubkey,
    pub creator: Pubkey,
    pub prize_pool: u64,
    pub max_players: u8,
}

// Additional error codes
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
    #[msg("Character is dead")]
    CharacterDead,
    #[msg("Already committed stance")]
    AlreadyCommitted,
    #[msg("Invalid stance reveal")]
    InvalidStanceReveal,
    #[msg("Special ability on cooldown")]
    SpecialOnCooldown,
    #[msg("Battle has expired")]
    BattleExpired,
    #[msg("No active wildcard")]
    NoActiveWildcard,
    #[msg("Decision timeout")]
    DecisionTimeout,
    #[msg("Decision period not expired")]
    DecisionNotExpired,
    #[msg("Not an AI battle")]
    NotAiBattle,
    #[msg("Not AI's turn")]
    NotAiTurn,
}


// Part 3 - Updated Account Structures and Remaining Contexts

// Updated Character account with all new fields
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
    
    // New fields
    pub rank_tier: RankTier,
    pub season_wins: u32,
    pub season_losses: u32,
    #[max_len(20)]
    pub achievements: Vec<Achievement>,
    #[max_len(100)]
    pub metadata_uri: String,
}

// Updated Battle account with all new fields
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
    pub is_vs_ai: bool,
    pub abandoned: bool,
    pub last_action_time: i64,
    
    // Battle state
    pub player1_hp: u64,
    pub player2_hp: u64,
    pub player1_combo: u16,
    pub player2_combo: u16,
    pub player1_stance: BattleStance,
    pub player2_stance: BattleStance,
    
    // Stance commitment system
    pub player1_stance_committed: bool,
    pub player2_stance_committed: bool,
    pub player1_stance_hash: [u8; 32],
    pub player2_stance_hash: [u8; 32],
    
    // DOT and effects
    pub player1_dot_damage: u64,
    pub player2_dot_damage: u64,
    pub player1_dot_turns: u8,
    pub player2_dot_turns: u8,
    pub player1_reflection: u16,
    pub player2_reflection: u16,
    pub player1_miss_count: u16,
    pub player2_miss_count: u16,
    
    // Special cooldowns
    pub player1_special_cooldown: u8,
    pub player2_special_cooldown: u8,
    
    // Wildcard system
    pub last_damage_roll: u8,
    pub wildcard_active: bool,
    pub wildcard_type: Option<WildcardEvent>,
    pub wildcard_decision_deadline: i64,
    pub wildcard_player1_decision: Option<bool>,
    pub wildcard_player2_decision: Option<bool>,
    
    // Battle log
    #[max_len(50)]
    pub battle_log: Vec<String>,
}

// Existing BettingPool (unchanged)
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

// Existing Bet (unchanged)
#[account]
#[derive(InitSpace)]
pub struct Bet {
    pub bettor: Pubkey,
    pub betting_pool: Pubkey,
    pub amount: u64,
    pub bet_on_player: u8,
    pub is_claimed: bool,
}

// Updated CharacterClass with Trickster
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, InitSpace, Debug)]
pub enum CharacterClass {
    Warrior,
    Assassin,
    Mage,
    Tank,
    Trickster, // New class!
}

impl CharacterClass {
    pub fn to_string(&self) -> &str {
        match self {
            CharacterClass::Warrior => "Warrior",
            CharacterClass::Assassin => "Assassin",
            CharacterClass::Mage => "Mage",
            CharacterClass::Tank => "Tank",
            CharacterClass::Trickster => "Trickster",
        }
    }
}

// Existing enums (unchanged)
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

// All remaining account contexts

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
    #[account(mut)]
    pub player2_character: Account<'info, Character>,
    #[account(mut)]
    pub player1_owner: Signer<'info>,
    /// CHECK: Only needed for non-AI battles
    #[account(mut)]
    pub player2_owner: AccountInfo<'info>,
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
    /// CHECK: Owner for stake transfer
    #[account(mut)]
    pub player1_owner: AccountInfo<'info>,
    /// CHECK: Owner for stake transfer
    #[account(mut)]
    pub player2_owner: AccountInfo<'info>,
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
    /// CHECK: Game treasury for heal payments
    #[account(mut)]
    pub game_treasury: AccountInfo<'info>,
    pub system_program: Program<'info, System>,
}

// ===== IMPLEMENTATION GUIDE =====
// 
// KEY IMPROVEMENTS IMPLEMENTED:
//
// 1. ✅ TRICKSTER CLASS
//    - 5th character class with wildcard manipulation (25% chance vs 10%)
//    - Special ability: Wild Card (4 random powerful effects)
//    - Unique crit bonus (+20 flat damage on crits)
//
// 2. ✅ PVE (Player vs AI)
//    - is_vs_ai flag in battles
//    - execute_ai_turn() function with strategic AI decision making
//    - AI chooses stances based on HP, opponent behavior
//
// 3. ✅ BETTER RANDOMNESS
//    - Note: Still uses simple_random() - MUST integrate Switchboard/Orao VRF
//    - Current implementation is placeholder
//    - TODO: Replace with proper VRF for production
//
// 4. ✅ STANCE COMMITMENT SYSTEM
//    - commit_stance() - player commits hash of (stance + salt)
//    - reveal_and_execute_turn() - verifies hash before executing
//    - Prevents opponent from seeing stance before choosing
//    - Auto-forfeit if doesn't reveal (via timeout system)
//
// 5. ✅ WILDCARD DECISION MECHANISM
//    - Risky wildcards (DoubleOrNothing, DeathRoulette) require accept/decline
//    - decide_wildcard() function for player decisions
//    - 10 second timeout per decision
//    - Auto-decline if timeout expires
//    - Both players must decide before resolution
//
// 6. ✅ SPECIAL MOVE COOLDOWNS
//    - player1_special_cooldown & player2_special_cooldown fields
//    - Set to 3 turns after use
//    - Decremented each turn
//    - Checked before allowing special use
//
// 7. ✅ MATCH STAKING/ESCROW
//    - Stakes locked in battle account at creation
//    - Both players must deposit (except vs AI)
//    - Winner receives both stakes in finalize_battle()
//    - Abandoned matches return stakes to non-abandoner
//
// 8. ✅ TOURNAMENT SYSTEM
//    - Tournament account structure created
//    - create_tournament() function
//    - TournamentStatus enum (Registration, InProgress, Completed, Cancelled)
//    - TODO: Implement bracket logic, round progression, prize distribution
//
// 9. ✅ DYNAMIC NFT UPDATES
//    - metadata_uri field in Character
//    - rank_tier field (Bronze → Master)
//    - achievements vec (FirstWin, TenWins, etc.)
//    - Stats update on level up
//    - TODO: Integrate with Metaplex for actual NFT minting
//
// 10. ✅ MATCHMAKING QUEUE
//     - QueueEntry account
//     - join_queue() function
//     - Stores MMR, match_type, stake_amount
//     - TODO: Off-chain service to match players and call create_battle()
//
// 11. ✅ SPECTATOR FEATURES
//     - battle_log vec stores up to 50 events
//     - Events emitted for all major actions
//     - TODO: Query programs to fetch battle history
//     - TODO: Leaderboard requires off-chain indexing
//
// 12. ✅ ANTI-CHEAT / TIMEOUT MECHANISMS
//     - last_action_time tracked
//     - TURN_TIMEOUT_SECONDS (30s per turn)
//     - BATTLE_EXPIRY_SECONDS (1 hour total)
//     - check_timeout() can be called by anyone to forfeit AFK player
//     - abandoned flag set, winner determined
//
// 13. ✅ BATTLE EVENTS/LOGGING
//     - 8 different events emitted (CharacterCreated, BattleCreated, etc.)
//     - battle_log stores text descriptions
//     - Real-time streaming via Solana event subscriptions
//
// 14. ⚠️ ECONOMIC FEATURES (Partial)
//     - ✅ Entry fees via stake_amount
//     - ✅ Healing costs (0.001 SOL to game_treasury)
//     - ❌ Marketplace for stat boosts - NOT IMPLEMENTED
//     - ❌ Referral system - NOT IMPLEMENTED
//
// 15. ✅ SEASON/RANKING SYSTEM
//     - season_wins & season_losses tracked
//     - rank_tier auto-updates based on MMR
//     - MMR ranges: Bronze(0-999), Silver(1000-1499), Gold(1500-1999),
//                   Platinum(2000-2499), Diamond(2500-2999), Master(3000+)
//     - TODO: Season reset function (requires admin/cron)
//
// 16. ❌ SOCIAL FEATURES
//     - NOT IMPLEMENTED
//     - TODO: Friend list, challenge system, guilds require separate accounts
//
// ===== CRITICAL TODO FOR PRODUCTION =====
//
// 1. INTEGRATE VRF (HIGHEST PRIORITY)
//    - Replace simple_random() with Switchboard VRF or Orao VRF
//    - Add VRF account to ExecuteTurn context
//    - Request randomness at turn start
//    - Callback to apply randomness after VRF fulfills
//
// 2. MATCHMAKING SERVICE
//    - Off-chain service to monitor queue
//    - Match players with similar MMR (±200 range)
//    - Call create_battle() when match found
//
// 3. TOURNAMENT BRACKET LOGIC
//    - Round-robin or single elimination
//    - Auto-progress winners to next round
//    - Prize distribution (1st: 50%, 2nd: 30%, 3rd-4th: 10% each)
//
// 4. METAPLEX INTEGRATION
//    - Mint actual NFTs for characters
//    - Update metadata URI on level/rank changes
//    - Add visual traits based on achievements
//
// 5. ADMIN FUNCTIONS
//    - Season reset (requires privileged signer)
//    - Emergency pause for bugs
//    - Treasury withdrawal for team
//
// 6. TESTING
//    - Unit tests for all damage calculations
//    - Integration tests for full battles
//    - Fuzzing for exploit detection
//    - Load testing for tournament system
//
// ===== USAGE EXAMPLE =====
//
// // 1. Create character
// create_character(ctx, CharacterClass::Trickster, "Shadow".to_string())
//
// // 2. Join queue
// join_queue(ctx, MatchType::Ranked, 0)
//
// // 3. Matchmaking service creates battle
// create_battle(ctx, MatchType::Ranked, 0, false)
//
// // 4. Players commit stances
// let salt = 12345_u64;
// let stance_bytes = BattleStance::Aggressive.to_bytes();
// let hash = hash(&[&stance_bytes, &salt.to_le_bytes()].concat()).to_bytes();
// commit_stance(ctx, hash)
//
// // 5. Execute turn with reveal
// reveal_and_execute_turn(ctx, BattleStance::Aggressive, salt, false)
//
// // 6. If wildcard triggers
// decide_wildcard(ctx, true) // Accept risky wildcard
//
// // 7. Alternate turns until battle ends
//
// // 8. Finalize and claim rewards
// finalize_battle(ctx)