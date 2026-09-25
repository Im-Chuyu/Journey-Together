-- ===========================================================================
--  中文伙伴台词配置文件 / Chinese companion dialogue configuration
--  ---------------------------------------------------------------------
--  这个文件是伙伴所有台词的唯一来源，随便改，不会影响其他逻辑。
--
--  1. lines 里的每一组都是"随机台词"，伙伴会从中随机挑一条说出来。
--     每一条写成 {"中文"}，中文内容放在本文件，英文内容放在对应的 en 文件。
--     一组里至少保留 1 条；想让随机效果好一些，建议每组 4 条以上。
--
--  2. replies 里的每一条都是"固定回复"，只有一条 {"中文"}。
--
--  3. 文本里可以写 {1}，伙伴说话时会替换成对应的名字或数字。
--     如果这一条没有写 {1}，但是程序带了名字过来，
--     伙伴会自动说成 "名字，台词内容"。
--
--  4. 不要删除任何一组的名字（等号左边的 key），只改引号里的文字最安全。
--     新增台词就在花括号里多加一行即可。
--
--  5. 普通台词以头顶气泡 + 附近玩家聊天框播出；到来、告别、鬼魂求助为世界公屏公告。
-- ===========================================================================

local M = {}

M.voice_order = {
    {'pet_feed', 1},
    {'pet_feed', 2},
    {'pet_feed', 3},
    {'pet_feed', 4},
    {'pet_travel', 1},
    {'pet_travel', 2},
    {'pet_travel', 3},
    {'pet_adopt', 1},
    {'pet_adopt', 2},
    {'pet_adopt', 3},
    {'explore', 1},
    {'explore', 2},
    {'explore', 3},
    {'explore', 4},
    {'explore_mount', 1},
    {'explore_mount', 2},
    {'explore_mount', 3},
    {'explore_dismount', 1},
    {'explore_dismount', 2},
    {'explore_dismount', 3},
    {'fish_prepare', 1},
    {'fish_prepare', 2},
    {'fish_prepare', 3},
    {'fish_search', 1},
    {'fish_search', 2},
    {'fish_search', 3},
    {'fish_replace', 1},
    {'fish_replace', 2},
    {'fish_replace', 3},
    {'fish_cast', 1},
    {'fish_cast', 2},
    {'fish_cast', 3},
    {'fish_caught', 1},
    {'fish_caught', 2},
    {'fish_caught', 3},
    {'fish_full', 1},
    {'fish_full', 2},
    {'fish_full', 3},
    {'butterfly_hunt', 1},
    {'butterfly_hunt', 2},
    {'butterfly_hunt', 3},
    {'butterfly_hunt', 4},
    {'butterfly_loot', 1},
    {'butterfly_loot', 2},
    {'butterfly_loot', 3},
    {'ghost_help', 1},
    {'ghost_help', 2},
    {'ghost_help', 3},
    {'ghost_help', 4},
    {'ghost_help', 5},
    {'ghost_help_depart', 1},
    {'ghost_help_depart', 2},
    {'ghost_help_depart', 3},
    {'skin_changed', 1},
    {'skin_changed', 2},
    {'skin_changed', 3},
    {'skin_changed', 4},
    {'skin_changed', 5},
    {'skin_changed', 6},
    {'skin_changed', 7},
    {'skin_changed', 8},
    {'skin_changed', 9},
    {'skin_changed', 10},
    {'gather_hurt', 1},
    {'gather_hurt', 2},
    {'gather_hurt', 3},
    {'wormhole_follow', 1},
    {'wormhole_follow', 2},
    {'wormhole_follow', 3},
    {'rift_follow', 1},
    {'rift_follow', 2},
    {'rift_follow', 3},
    {'rift_follow', 4},
    {'sit_rest', 1},
    {'sit_rest', 2},
    {'sit_rest', 3},
    {'sit_rest', 4},
    {'sit_together', 1},
    {'sit_together', 2},
    {'sit_together', 3},
    {'sit_together', 4},
    {'book_read', 1},
    {'book_read', 2},
    {'book_read', 3},
    {'book_read', 4},
    {'book_shelf_read', 1},
    {'book_shelf_read', 2},
    {'book_shelf_read', 3},
    {'book_shelf_read', 4},
    {'book_ground_pickup', 1},
    {'book_ground_pickup', 2},
    {'book_store', 1},
    {'book_store', 2},
    {'book_store', 3},
    {'book_store', 4},
    {'rockfruit', 1},
    {'rockfruit', 2},
    {'rockfruit', 3},
    {'rockfruit_ask', 1},
    {'rockfruit_ask', 2},
    {'rockfruit_ask', 3},
    {'rockfruit_mine_answer', 1},
    {'rockfruit_mine_answer', 2},
    {'rockfruit_store_answer', 1},
    {'rockfruit_store_answer', 2},
    {'bullkelp', 1},
    {'bullkelp', 2},
    {'bullkelp', 3},
    {'dry_meat', 1},
    {'dry_meat', 2},
    {'dry_meat', 3},
    {'dry_meat_collect', 1},
    {'dry_meat_collect', 2},
    {'dry_meat_collect', 3},
    {'carry_statue', 1},
    {'carry_statue', 2},
    {'carry_statue', 3},
    {'carry_statue_mount', 1},
    {'carry_statue_mount', 2},
    {'carry_statue_mount', 3},
    {'ride_mount', 1},
    {'ride_mount', 2},
    {'ride_mount', 3},
    {'ride_chase', 1},
    {'ride_chase', 2},
    {'ride_chase', 3},
    {'ride_dismount', 1},
    {'ride_dismount', 2},
    {'ride_dismount', 3},
    {'follow', 1},
    {'follow', 2},
    {'follow', 3},
    {'follow', 4},
    {'follow', 5},
    {'follow', 6},
    {'idle', 1},
    {'idle', 2},
    {'idle', 3},
    {'idle', 4},
    {'idle', 5},
    {'idle', 6},
    {'idle', 7},
    {'idle', 8},
    {'idle', 9},
    {'idle', 10},
    {'idle', 11},
    {'idle', 12},
    {'activity_idle', 1},
    {'activity_idle', 2},
    {'activity_idle', 3},
    {'activity_chop', 1},
    {'activity_chop', 2},
    {'activity_chop', 3},
    {'activity_mine', 1},
    {'activity_mine', 2},
    {'activity_mine', 3},
    {'activity_dig', 1},
    {'activity_dig', 2},
    {'activity_dig', 3},
    {'activity_fish', 1},
    {'activity_fish', 2},
    {'activity_fish', 3},
    {'activity_explore', 1},
    {'activity_explore', 2},
    {'activity_explore', 3},
    {'activity_fight', 1},
    {'activity_fight', 2},
    {'activity_fight', 3},
    {'activity_feed', 1},
    {'activity_feed', 2},
    {'activity_feed', 3},
    {'activity_tidy', 1},
    {'activity_tidy', 2},
    {'activity_tidy', 3},
    {'activity_cook', 1},
    {'activity_cook', 2},
    {'activity_cook', 3},
    {'activity_eat', 1},
    {'activity_eat', 2},
    {'activity_eat', 3},
    {'activity_build', 1},
    {'activity_build', 2},
    {'activity_build', 3},
    {'activity_follow', 1},
    {'activity_follow', 2},
    {'activity_follow', 3},
    {'activity_ride', 1},
    {'activity_ride', 2},
    {'activity_ride', 3},
    {'activity_sit', 1},
    {'activity_sit', 2},
    {'activity_sit', 3},
    {'work', 1},
    {'work', 2},
    {'work', 3},
    {'work', 4},
    {'work', 5},
    {'work', 6},
    {'chop', 1},
    {'chop', 2},
    {'chop', 3},
    {'chop', 4},
    {'chop', 5},
    {'chop', 6},
    {'mine', 1},
    {'mine', 2},
    {'mine', 3},
    {'mine', 4},
    {'mine', 5},
    {'mine', 6},
    {'gather', 1},
    {'gather', 2},
    {'gather', 3},
    {'gather', 4},
    {'gather', 5},
    {'gather', 6},
    {'plant', 1},
    {'plant', 2},
    {'plant', 3},
    {'plant', 4},
    {'plant', 5},
    {'plant', 6},
    {'fertilizer_search', 1},
    {'fertilizer_search', 2},
    {'fertilizer_search', 3},
    {'fertilizer_collect', 1},
    {'fertilizer_collect', 2},
    {'fertilizer_collect', 3},
    {'fertilize', 1},
    {'fertilize', 2},
    {'fertilize', 3},
    {'build', 1},
    {'build', 2},
    {'build', 3},
    {'build', 4},
    {'build', 5},
    {'build', 6},
    {'store', 1},
    {'store', 2},
    {'store', 3},
    {'store', 4},
    {'store', 5},
    {'store', 6},
    {'recipe_cook', 1},
    {'recipe_cook', 2},
    {'recipe_cook', 3},
    {'recipe_cook', 4},
    {'recipe_cook', 5},
    {'recipe_clear', 1},
    {'recipe_clear', 2},
    {'recipe_clear', 3},
    {'recipe_ready', 1},
    {'recipe_ready', 2},
    {'recipe_ready', 3},
    {'recipe_ready', 4},
    {'cook', 1},
    {'cook', 2},
    {'cook', 3},
    {'cook', 4},
    {'cook', 5},
    {'cook', 6},
    {'eat', 1},
    {'eat', 2},
    {'eat', 3},
    {'eat', 4},
    {'eat', 5},
    {'eat', 6},
    {'fed', 1},
    {'fed', 2},
    {'fed', 3},
    {'fed', 4},
    {'fed', 5},
    {'fed', 6},
    {'fed', 7},
    {'fed', 8},
    {'fed_careful', 1},
    {'fed_careful', 2},
    {'fed_careful', 3},
    {'fed_careful', 4},
    {'fed_careful', 5},
    {'fed_careful', 6},
    {'gift', 1},
    {'gift', 2},
    {'gift', 3},
    {'gift', 4},
    {'gift', 5},
    {'gift', 6},
    {'gift', 7},
    {'gift', 8},
    {'feed_player', 1},
    {'feed_player', 2},
    {'feed_player', 3},
    {'feed_player', 4},
    {'feed_player', 5},
    {'feed_player', 6},
    {'feed_player', 7},
    {'feed_player', 8},
    {'beefalo_feed', 1},
    {'beefalo_feed', 2},
    {'beefalo_feed', 3},
    {'beefalo_feed', 4},
    {'beefalo_feed', 5},
    {'beefalo_feed', 6},
    {'beefalo_feed', 7},
    {'beefalo_feed', 8},
    {'beefalo_feed', 9},
    {'beefalo_feed', 10},
    {'beefalo_cook', 1},
    {'beefalo_cook', 2},
    {'beefalo_cook', 3},
    {'player_takes_food', 1},
    {'player_takes_food', 2},
    {'player_takes_food', 3},
    {'player_takes_food', 4},
    {'player_takes_food', 5},
    {'player_takes_food', 6},
    {'player_takes_sack', 1},
    {'player_takes_sack', 2},
    {'player_takes_sack', 3},
    {'player_takes_sack', 4},
    {'player_takes_sack', 5},
    {'player_takes_sack', 6},
    {'beefalo_cooked', 1},
    {'beefalo_cooked', 2},
    {'beefalo_cooked', 3},
    {'hurt', 1},
    {'hurt', 2},
    {'hurt', 3},
    {'hurt', 4},
    {'hurt', 5},
    {'hurt', 6},
    {'meal_open', 1},
    {'meal_open', 2},
    {'meal_open', 3},
    {'meal_open', 4},
    {'meal_take', 1},
    {'meal_take', 2},
    {'meal_take', 3},
    {'meal_take', 4},
    {'meal_return', 1},
    {'meal_return', 2},
    {'meal_return', 3},
    {'meal_return', 4},
    {'player_attack', 1},
    {'player_attack', 2},
    {'player_attack', 3},
    {'player_attack', 4},
    {'ghost_return_question', 1},
    {'ghost_return_question', 2},
    {'ghost_return_question', 3},
    {'fight', 1},
    {'fight', 2},
    {'fight', 3},
    {'fight', 4},
    {'fight', 5},
    {'fight', 6},
    {'fight', 7},
    {'fight', 8},
    {'fight', 9},
    {'fight', 10},
    {'fight', 11},
    {'fight_boss', 1},
    {'fight_boss', 2},
    {'fight_boss', 3},
    {'fight_boss', 4},
    {'fight_boss', 5},
    {'fight_boss', 6},
    {'fight_boss', 7},
    {'fight_boss', 8},
    {'fight_boss', 9},
    {'flee', 1},
    {'flee', 2},
    {'flee', 3},
    {'flee', 4},
    {'flee', 5},
    {'flee', 6},
    {'greeting', 1},
    {'greeting', 2},
    {'greeting', 3},
    {'greeting', 4},
    {'greeting', 5},
    {'greeting', 6},
    {'care_health', 1},
    {'care_health', 2},
    {'care_health', 3},
    {'care_health', 4},
    {'care_hunger', 1},
    {'care_hunger', 2},
    {'care_hunger', 3},
    {'care_hunger', 4},
    {'care_sanity', 1},
    {'care_sanity', 2},
    {'care_sanity', 3},
    {'care_sanity', 4},
    {'gift_sack', 1},
    {'gift_sack', 2},
    {'gift_sack', 3},
    {'gift_food', 1},
    {'gift_food', 2},
    {'gift_food', 3},
    {'gift_food', 4},
    {'gift_food', 5},
    {'gift_food_settled', 1},
    {'gift_food_settled', 2},
    {'gift_food_settled', 3},
    {'gift_food_settled', 4},
    {'gift_food_settled', 5},
    {'hold_position', 1},
    {'hold_position', 2},
    {'hold_position', 3},
    {'hold_position', 4},
    {'hold_position', 5},
    {'hold_idle', 1},
    {'hold_idle', 2},
    {'hold_idle', 3},
    {'hold_idle', 4},
    {'hold_idle', 5},
    {'base_set', 1},
    {'base_set', 2},
    {'base_set', 3},
    {'base_set', 4},
    {'base_set', 5},
    {'base_idle', 1},
    {'base_idle', 2},
    {'base_idle', 3},
    {'base_idle', 4},
    {'base_idle', 5},
    {'late_join', 1},
    {'late_join', 2},
    {'late_join', 3},
    {'late_join', 4},
    {'wander', 1},
    {'wander', 2},
    {'wander', 3},
    {'wander', 4},
    {'ask_pickup', 1},
    {'ask_pickup', 2},
    {'ask_pickup', 3},
    {'ask_pickup', 4},
    {'pickup_allowed', 1},
    {'pickup_allowed', 2},
    {'pickup_allowed', 3},
    {'revived_thanks', 1},
    {'revived_thanks', 2},
    {'revived_thanks', 3},
    {'revived_thanks', 4},
    {'revived_thanks', 5},
    {'revive_player', 1},
    {'revive_player', 2},
    {'revive_player', 3},
    {'revive_player', 4},
    {'revive_player', 5},
    {'revive_drop', 1},
    {'revive_drop', 2},
    {'revive_drop', 3},
    {'revive_drop', 4},
    {'farewell', 1},
    {'farewell', 2},
    {'farewell', 3},
    {'farewell', 4},
    {'farewell', 5},
    {'switch_arrive', 1},
    {'switch_arrive', 2},
    {'switch_arrive', 3},
    {'switch_arrive', 4},
    {'cold', 1},
    {'cold', 2},
    {'cold', 3},
    {'hot', 1},
    {'hot', 2},
    {'hot', 3},
    {'worn_out', 1},
    {'worn_out', 2},
    {'worn_out', 3},
    {'dark', 1},
    {'dark', 2},
    {'dark', 3},
    {'command_refuse_human', 1},
    {'describe_carry_statue', 1},
    {'carry_statue_follow', 1},
    {'carry_statue_mount', 1},
    {'carry_statue_none', 1},
    {'describe_rockfruit', 1},
    {'describe_bullkelp', 1},
    {'describe_dry_meat', 1},
    {'dry_meat_done', 1},
    {'describe_monkeytail', 1},
    {'describe_monkeytail', 2},
    {'describe_monkeytail', 3},
    {'describe_monkeytail', 4},
    {'monkeytail_done', 1},
    {'monkeytail_done', 2},
    {'monkeytail_done', 3},
    {'monkeytail_done', 4},
    {'monkeytail_none', 1},
    {'monkeytail_none', 2},
    {'monkeytail_none', 3},
    {'describe_banana', 1},
    {'describe_banana', 2},
    {'describe_banana', 3},
    {'describe_banana', 4},
    {'banana_done', 1},
    {'banana_done', 2},
    {'banana_done', 3},
    {'banana_done', 4},
    {'banana_none', 1},
    {'banana_none', 2},
    {'banana_none', 3},
    {'pet_unknown', 1},
    {'pet_full', 1},
    {'pet_materials', 1},
    {'pet_no_den', 1},
    {'pet_unavailable', 1},
    {'pet_prepare', 1},
    {'pet_done', 1},
    {'describe_explore', 1},
    {'describe_fish', 1},
    {'fish_no_rod', 1},
    {'fish_rod_done', 1},
    {'fish_rod_missing', 1},
    {'ghost_revive_nearby', 1},
    {'ghost_revive_portal', 1},
    {'ghost_revive_none', 1},
    {'ghost_revive_no_portal', 1},
    {'ghost_revive_failed', 1},
    {'ghost_revive_return', 1},
    {'ghost_revive_return_blocked', 1},
    {'bookstation_prepare', 1},
    {'bookstation_make_room', 1},
    {'bookstation_blocked', 1},
    {'bookstation_cannot_make', 1},
    {'bookstation_done', 1},
    {'book_last_stored', 1},
    {'book_last_keep', 1},
    {'book_used_up', 1},
    {'book_read_failed', 1},
    {'follow_ok', 1},
    {'follow_busy', 1},
    {'follow_unfamiliar', 1},
    {'ride_ok', 1},
    {'ride_stop_ok', 1},
    {'ride_unavailable', 1},
    {'ride_not_following', 1},
    {'affinity_work', 1},
    {'affinity_items', 1},
    {'affinity_name', 1},
    {'affinity_locked', 1},
    {'affinity_skin', 1},
    {'name_invalid', 1},
    {'name_ok', 1},
    {'special_no_book', 1},
    {'special_no_food', 1},
    {'special_cannot_make', 1},
    {'recipe_batch_done', 1},
    {'recipe_inventory_full', 1},
    {'special_device_place_failed', 1},
    {'special_recall', 1},
    {'special_read_ok', 1},
    {'special_spice_ok', 1},
    {'special_command_ok', 1},
    {'no_backpack', 1},
    {'backpack_unreachable', 1},
    {'carry_backpack_ask', 1},
    {'carry_backpack_ask', 2},
    {'carry_backpack_ask', 3},
    {'carry_backpack_yes', 1},
    {'carry_backpack_yes', 2},
    {'carry_backpack_yes', 3},
    {'carry_backpack_done', 1},
    {'carry_backpack_done', 2},
    {'carry_backpack_done', 3},
    {'carry_backpack_failed', 1},
    {'carry_backpack_failed', 2},
    {'no_tool', 1},
    {'hoe_incomplete', 1},
    {'describe_butterfly', 1},
    {'butterfly_none', 1},
    {'butterfly_done', 1},
    {'describe_sit', 1},
    {'sit_unavailable', 1},
    {'sit_stop_ok', 1},
    {'describe_dig_grass', 1},
    {'describe_dig_sapling', 1},
    {'describe_dig_stump', 1},
    {'dig_full', 1},
    {'dig_none', 1},
    {'dig_done', 1},
    {'describe_hoe', 1},
    {'describe_water', 1},
    {'describe_chop', 1},
    {'describe_mine', 1},
    {'describe_grass', 1},
    {'describe_harvest', 1},
    {'describe_seeds', 1},
    {'describe_tidy', 1},
    {'describe_hold', 1},
    {'describe_base', 1},
    {'base_needs_follow', 1},
    {'switch_needs_follow', 1},
    {'farewell_gift_ok', 1},
    {'farewell_gift_cancel', 1},
}

M.lines = {
    pet_feed = {
    -- fn1
        {"饿了吧，小家伙，来吃一口。"},
    -- fn2
        {"这点小零食留给你，慢慢吃。"},
    -- fn3
        {"别围着我转啦，知道你饿了。"},
    -- fn4
        {"吃饱了再陪我走一会儿。"},
    },
    pet_travel = {
    -- fn5
        {"材料带齐了，去巢穴接个小伙伴。"},
    -- fn6
        {"不知道它见到我会不会开心呢。"},
    -- fn7
        {"等我回来，咱们就多一位朋友了。"},
    },
    pet_adopt = {
    -- fn8
        {"来吧，以后我们一起走。"},
    -- fn9
        {"给你准备了好吃的，跟我回家吧。"},
    -- fn10
        {"小家伙，以后我照顾你。"},
    },
    explore = {
    -- fn11
        {"这边还没走过，我去看看。"},
    -- fn12
        {"路我记着呢，叫我一声就回来。"},
    -- fn13
        {"先照顾好自己，再接着往前走。"},
    -- fn14
        {"绕过这片树林，看看另一边有什么。"},
    },
    explore_mount = {
    -- fn15
        {"有牛儿同行，今天能走远一些了。"},
    -- fn16
        {"借你的脚力，去看看没走过的地方。"},
    -- fn17
        {"事情忙完了，骑上牛继续探路。"},
    },
    explore_dismount = {
    -- fn18
        {"找块好落脚的地方，我先下来一下。"},
    -- fn19
        {"这段先用脚走，探路的事还记着呢。"},
    -- fn20
        {"先下牛处理点事情，忙完再继续走。"},
    },
    fish_prepare = {
    -- fn21
        {"先把钓竿备好，鱼儿可不等人。"},
    -- fn22
        {"找找钓竿，没有就做一根。"},
    -- fn23
        {"材料凑齐了，再去池塘边坐坐。"},
    },
    fish_search = {
    -- fn24
        {"附近没有合适的池塘，再往前找找。"},
    -- fn25
        {"这边的鱼暂时钓不了了，换个地方。"},
    -- fn26
        {"钓竿带好了，就差一处好水塘。"},
    },
    fish_replace = {
    -- fn27
        {"钓竿用坏了，看看身上的材料还能不能再做一根。"},
    -- fn28
        {"先补一根钓竿，再回来等鱼上钩。"},
    -- fn29
        {"钓竿也得换班，材料够就继续。"},
    },
    fish_cast = {
    -- fn30
        {"就在这里下竿吧。"},
    -- fn31
        {"安静等一等，看看今天的收获。"},
    -- fn32
        {"鱼儿，上钩吧。"},
    },
    fish_caught = {
    -- fn33
        {"又钓到一条，收好了。"},
    -- fn34
        {"这条留着做顿好饭。"},
    -- fn35
        {"收获不错，再来一竿。"},
    },
    fish_full = {
    -- fn36
        {"身上装不下了，鱼先放岸边。"},
    -- fn37
        {"这条先放这里，回头记得来拿。"},
    -- fn38
        {"鱼比口袋多啦，先摆在脚边。"},
    },
    butterfly_hunt = {
    -- fn39
        {"得再靠近一点，这小家伙飞得可快。"},
    -- fn40
        {"先盯住这一只，别让它飞远了。"},
    -- fn41
        {"等我靠近了再出手。"},
    -- fn42
        {"这回得跟紧些，不能挥空了。"},
    },
    butterfly_loot = {
    -- fn43
        {"拿到了，先把吃的收好。"},
    -- fn44
        {"这一点也能救急，不能落下。"},
    -- fn45
        {"先捡起来，再看要不要继续。"},
    },
    ghost_help = {
    -- fn46
        {"我是{1}，不小心变成鬼魂了，有人能来救救我吗？"},
    -- fn47
        {"{1}在这里求救！谁方便带颗救赎之心来？我的东西还掉在原地呢。"},
    -- fn48
        {"我是{1}，现在只能飘着了。有空的朋友帮我复活一下吧。"},
    -- fn49
        {"{1}还在等救援，谁能帮我重新站起来？等活过来再好好谢谢你。"},
    -- fn50
        {"我是{1}，这次真的需要帮忙了！有人愿意过来救我吗？"},
    },
    ghost_help_depart = {
    -- fn51
        {"我是{1}，大家先忙吧，我自己飘去大门复活，之后回来捡东西。"},
    -- fn52
        {"{1}准备去大门复活了，不用特地赶来啦，我还得回来收拾遗物呢。"},
    -- fn53
        {"我是{1}，看来大家都挺忙，我先去大门找回身体，再回来拿自己的东西。"},
    },
    skin_changed = {
    -- fn54
        {"换好了！你觉得这身怎么样？"},
    -- fn55
        {"你挑的这套还挺合适，谢谢啦。"},
    -- fn56
        {"新造型，新心情，今天走路都精神些了。"},
    -- fn57
        {"让我转一圈，你帮我看看有没有哪里不整齐。"},
    -- fn58
        {"穿得这么好看，等会儿干活可得小心点。"},
    -- fn59
        {"眼光不错嘛，下回还找你帮我挑。"},
    -- fn60
        {"这下见到熟人，他们还能一眼认出我吗？"},
    -- fn61
        {"收拾得焕然一新，咱们接着出发吧。"},
    -- fn62
        {"怎么样，有没有比刚才更像个可靠的伙伴？"},
    -- fn63
        {"有你帮忙挑衣服，倒省了我纠结半天。"},
    },
    gather_hurt = {
    -- fn64
        {"采这个会受伤，先换个地方，过一会儿再来。"},
    -- fn65
        {"这份材料有点扎手，先让它待着吧。"},
    -- fn66
        {"刚才吃了点苦头，这个先记下来，暂时不碰。"},
    },
    wormhole_follow = {
    -- fn67
        {"等我一下，我也从这里过去。"},
    -- fn68
        {"你先过去，我马上就到。"},
    -- fn69
        {"这条近路有点黏，不过总比绕远好。"},
    },
    rift_follow = {
    -- fn70
        {"等等我，这条裂隙我也能走吧？"},
    -- fn71
        {"趁它还没合上，我这就跟过来。"},
    -- fn72
        {"你先过去，我马上从这边跳进来。"},
    -- fn73
        {"这回的近路看着还挺神奇。"},
    },
    sit_rest = {
    -- fn74
        {"这儿有把椅子，我坐一会儿，出发时叫我。"},
    -- fn75
        {"附近挺安静，让腿也歇一歇。"},
    -- fn76
        {"有现成的座位，就不站着发呆了。"},
    -- fn77
        {"坐着看看风景，你要走我就跟上。"},
    },
    sit_together = {
    -- fn78
        {"你也坐下了？那我就在旁边陪你一会儿。"},
    -- fn79
        {"旁边还有空位，正好一起歇歇脚。"},
    -- fn80
        {"今天走了不少路，坐下来聊两句吧。"},
    -- fn81
        {"好呀，一起坐会儿。等你休息好了再出发。"},
    },
    book_read = {
    -- fn82
        {"让我翻到这一页，知识也需要耐心。"},
    -- fn83
        {"听仔细了，这可不是普通的故事书。"},
    -- fn84
        {"书里的办法，正好能派上用场。"},
    -- fn85
        {"这一段我记得，不过还是核对一下好。"},
    },
    book_shelf_read = {
    -- fn86
        {"书就在架子里，我打开书架直接读。"},
    -- fn87
        {"找到了，让它留在书架里就好。"},
    -- fn88
        {"书不用搬来搬去，在这里读也一样。"},
    -- fn89
        {"读完就关好书架，知识也要好好保管。"},
    },
    book_ground_pickup = {
    -- fn90
        {"书在地上，先捡起来再读。"},
    -- fn91
        {"找到一本落在地上的书，别让它受潮了。"},
    },
    book_store = {
    -- fn92
        {"这本书只剩最后一次了，放进书架养护一下。"},
    -- fn93
        {"书页已经很旧了，先让它歇歇。"},
    -- fn94
        {"有书架就别急着把书用光，留着还能慢慢恢复。"},
    -- fn95
        {"最后几页要爱惜，我先替你收好。"},
    },
    rockfruit = {
    -- fn96
        {"石果交给我吧，硬的我来敲，软的我来摘。"},
    -- fn97
        {"这果子长得像石头，脾气也确实像石头。"},
    -- fn98
        {"先把附近的石果收好，别让它们在地上装无辜。"},
    },
    rockfruit_ask = {
    -- fn99
        {"石果收好了，要我继续敲开，还是放进最近的箱子？"},
    -- fn100
        {"硬邦邦的都在这儿了，你说敲不敲？三十秒内告诉我。"},
    -- fn101
        {"要不要敲石果？你不说我就当它们只是普通收藏品。"},
    },
    rockfruit_mine_answer = {
    -- fn102
        {"好，既然你点头了，我这就把石果敲开。"},
    -- fn103
        {"没问题，石头外壳准备接受命运吧。"},
    },
    rockfruit_store_answer = {
    -- fn104
        {"好，不敲就不敲，我把它们收进箱子，留着以后再说。"},
    -- fn105
        {"行，今天先不和石果较劲，箱子会照顾好它们。"},
    },
    bullkelp = {
    -- fn106
        {"我去摘海带，顺便看看海边有没有把我吹成海带。"},
    -- fn107
        {"海带都别躲，今天一个也别想漏网。"},
    -- fn108
        {"摘完我就放进冰箱，给它们安排一个凉快的位置。"},
    },
    dry_meat = {
    -- fn109
        {"我去给食材找个晾肉架，晒太阳总比在包里闷着好。"},
    -- fn110
        {"晾肉架准备好了吗？我这就把能晾的都挂上去。"},
    -- fn111
        {"今天的菜单是风干，厨师本人暂时不参与风干。"},
    },
    dry_meat_collect = {
    -- fn112
        {"晾好了？我来把这批风味收回来。"},
    -- fn113
        {"太阳干活很卖力，我负责把成果收进冰箱。"},
    -- fn114
        {"晾肉架今天交作业了，收货。"},
    },
    carry_statue = {
    -- fn115
        {"这尊雕像有点沉，不过我搬得动。"},
    -- fn116
        {"别催，我正和这块石头培养默契。"},
    -- fn117
        {"搬东西也是一种锻炼，今天的手臂有事做了。"},
    },
    carry_statue_mount = {
    -- fn118
        {"骑牛搬雕像，今天的运输规格有点高。"},
    -- fn119
        {"牛儿，慢一点，咱们车上还有一位石头客人。"},
    -- fn120
        {"放心，雕像坐得比我还稳。"},
    },
    -- ---------- 日常行为 ----------
    ride_mount = {
    -- fn121
        {"离得太远了，骑牛过去会快些。"},
    -- fn122
        {"牛儿，载我去找他吧。"},
    -- fn123
        {"先借你的脚力赶路。"},
    },
    ride_chase = {
    -- fn124
        {"我骑牛追上去，很快就到。"},
    -- fn125
        {"别走太远，我这就赶上。"},
    -- fn126
        {"有坐骑就不用担心赶不上了。"},
    },
    ride_dismount = {
    -- fn127
        {"到了这里，我走过去就好。"},
    -- fn128
        {"谢谢你载我一程。"},
    -- fn129
        {"辛苦啦，接下来我们慢慢走。"},
    },
    follow = {
    -- fn130
        {"好，我跟着你。"},
    -- fn131
        {"一起走吧，我就在身边。"},
    -- fn132
        {"你带路，我会跟上的。"},
    -- fn133
        {"去哪里都好，我们一起。"},
    -- fn134
        {"嗯，别担心落下我。"},
    -- fn135
        {"我来啦，我们一起走。"},
    },
    idle = {
    -- fn136
        {"这里很安静，歇一会儿吧。"},
    -- fn137
        {"今天也慢慢来，不着急。"},
    -- fn138
        {"有个能回来的地方，真好。"},
    -- fn139
        {"我在附近走走。"},
    -- fn140
        {"每阵风都让我想起很多事情。"},
    -- fn141
        {"事情做完了，喘口气吧。"},
    -- fn142
        {"我在检查今天的风有没有把我的发型吹乱。"},
    -- fn143
        {"暂时没大事，正好陪影子散散步。"},
    -- fn144
        {"别看我发呆，我这是在认真恢复能量。"},
    -- fn145
        {"风景不错，连发呆都有点舍不得结束。"},
    -- fn146
        {"我在附近待命，顺便想想晚饭吃什么。"},
    -- fn147
        {"今天也辛苦啦，能歇一会儿就歇一会儿。"},
    },
    activity_idle = {
    -- fn148
        {"没看见吗？我正在悠闲地待机，顺便观察风向。"},
    -- fn149
        {"暂时没急事，正替大家把安静的气氛维持住。"},
    -- fn150
        {"我在休息，休息也是生存计划的一部分。"},
    },
    activity_chop = {
    -- fn151
        {"没看见吗？我在砍树呀。"},
    -- fn152
        {"我要准备点木头过冬用。"},
    -- fn153
        {"不是你叫我砍树的吗？我这就快好了。"},
    },
    activity_mine = {
    -- fn154
        {"我在和石头谈判，目前它还不肯投降。"},
    -- fn155
        {"正在挖矿，看看今天能不能挖出点惊喜。"},
    -- fn156
        {"我在给基地准备石头和矿料。"},
    },
    activity_dig = {
    -- fn157
        {"我在挖东西，地面马上就会变得更有规划。"},
    -- fn158
        {"正在移植这些植物，给它们换个更好的住处。"},
    -- fn159
        {"铲子在手，附近的草丛树苗都得排队。"},
    },
    activity_fish = {
    -- fn160
        {"我在钓鱼，鱼竿比我还需要耐心。"},
    -- fn161
        {"正在等鱼儿上钩，别把水面吓跑了。"},
    -- fn162
        {"我在给晚饭争取一点水产。"},
    },
    activity_explore = {
    -- fn163
        {"我在探图，看看世界还有什么没见过的角落。"},
    -- fn164
        {"正在开路，放心，我还记得回来的方向。"},
    -- fn165
        {"我在出去逛逛，发现好东西就带回来。"},
    },
    activity_fight = {
    -- fn166
        {"我在打架呀，等我把这位客人请走。"},
    -- fn167
        {"正在保护你，也顺便保护我自己。"},
    -- fn168
        {"我在处理麻烦，处理完就回来。"},
    },
    activity_feed = {
    -- fn169
        {"我在给小家伙喂饭，它的肚子比看起来诚实。"},
    -- fn170
        {"正在照顾宠物，养宠物可不能只负责可爱。"},
    -- fn171
        {"我在给它准备一口吃的，马上就好。"},
    },
    activity_tidy = {
    -- fn172
        {"我在整理物资，箱子都快认识我了。"},
    -- fn173
        {"正在把没急用的东西安置好，免得它们到处旅行。"},
    -- fn174
        {"我在收拾，基地总得有点秩序。"},
    },
    activity_cook = {
    -- fn175
        {"我在做饭，今天的锅不会空着。"},
    -- fn176
        {"正在把食材变成更像样的晚餐。"},
    -- fn177
        {"我在准备料理，等会儿记得趁热吃。"},
    },
    activity_eat = {
    -- fn178
        {"我在吃饭，重要的生存会议正在召开。"},
    -- fn179
        {"正在补充能量，空肚子可做不了大事。"},
    -- fn180
        {"我在认真吃饭，别担心，没把你的份吃掉。"},
    },
    activity_build = {
    -- fn181
        {"我在制作东西，材料马上就会变成有用的家当。"},
    -- fn182
        {"正在建造，基地要一点一点变得可靠。"},
    -- fn183
        {"我在忙着做东西，等成品出来你就知道了。"},
    },
    activity_follow = {
    -- fn184
        {"我在跟着你呀，难道我藏得太好了？"},
    -- fn185
        {"正在陪你走，顺便看看路边有没有好东西。"},
    -- fn186
        {"我在你身边待命，你往哪儿走我就往哪儿走。"},
    },
    activity_ride = {
    -- fn187
        {"我在骑牛赶路，四条腿果然比两条腿忙。"},
    -- fn188
        {"正在骑牛追上你，别跑得太快。"},
    -- fn189
        {"我在和牛一起赶路，今天的路程有坐骑负责。"},
    },
    activity_sit = {
    -- fn190
        {"我在坐着休息，椅子今天表现得很可靠。"},
    -- fn191
        {"正在坐着陪你，腿也需要一点尊重。"},
    -- fn192
        {"我在椅子上待命，叫我一声就出发。"},
    },
    work = {
    -- fn193
        {"这件事交给我吧。"},
    -- fn194
        {"一点一点来，总能做好的。"},
    -- fn195
        {"我会仔细些的。"},
    -- fn196
        {"先把眼前的事情做好。"},
    -- fn197
        {"忙一会儿，之后再休息。"},
    -- fn198
        {"能帮上忙就好。"},
    },
    chop = {
    -- fn199
        {"这些木头应该够用一阵了。"},
    -- fn200
        {"再备一点木头，夜里就安心些。"},
    -- fn201
        {"小心，别站在树倒下的地方。"},
    -- fn202
        {"把木头带回去，还有不少用处。"},
    -- fn203
        {"一斧一斧地来。"},
    -- fn204
        {"这些树长得真高。"},
    },
    mine = {
    -- fn205
        {"石头里也藏着有用的东西呢。"},
    -- fn206
        {"敲下来的碎石，别扎到脚。"},
    -- fn207
        {"把这些矿石收好。"},
    -- fn208
        {"再敲几下试试。"},
    -- fn209
        {"这些材料以后会用得上。"},
    -- fn210
        {"坚硬的石头，也可以慢慢敲开。"},
    },
    gather = {
    -- fn211
        {"这个也带上吧。"},
    -- fn212
        {"慢慢收，不要漏掉了。"},
    -- fn213
        {"有这些储备，就踏实多了。"},
    -- fn214
        {"路过能用的东西，就收好。"},
    -- fn215
        {"这附近还有些东西可以收。"},
    -- fn216
        {"背包里又多了一点收获。"},
    },
    plant = {
    -- fn217
        {"在这里好好长大吧。"},
    -- fn218
        {"以后这里会更绿一些。"},
    -- fn219
        {"给你留好了位置。"},
    -- fn220
        {"慢慢长，我们会等的。"},
    -- fn221
        {"把根安顿好，就不怕了。"},
    -- fn222
        {"这一小片也有生气了。"},
    },
    fertilizer_search = {
    -- fn223
        {"去草原看看，给基地找些肥料。"},
    -- fn224
        {"这一带找完了，再往前看看。"},
    -- fn225
        {"草丛还等着肥料呢，我去找找。"},
    },
    fertilizer_collect = {
    -- fn226
        {"这份肥料带回去，草丛用得上。"},
    -- fn227
        {"收好这些，回基地再施肥。"},
    -- fn228
        {"又找到一点肥料了。"},
    },
    fertilize = {
    -- fn229
        {"给你补点养分，继续长吧。"},
    -- fn230
        {"肥料用上了，等着草丛恢复。"},
    -- fn231
        {"这一丛也照顾好了。"},
    },
    build = {
    -- fn232
        {"这样就更像一个家了。"},
    -- fn233
        {"又做好了一件。"},
    -- fn234
        {"放在这里应该很合适。"},
    -- fn235
        {"准备周全些，之后就方便了。"},
    -- fn236
        {"材料没有白费呢。"},
    -- fn237
        {"一点点把需要的东西补齐。"},
    },
    store = {
    -- fn238
        {"同样的东西放在一起，比较好找。"},
    -- fn239
        {"把这些收好，以后用。"},
    -- fn240
        {"整理一下，背包就轻松了。"},
    -- fn241
        {"需要的时候，就知道来哪里拿了。"},
    -- fn242
        {"东西各有各的位置。"},
    -- fn243
        {"留一点备用，总是好的。"},
    },
    recipe_cook = {
    -- fn244
        {"这些食材能凑一锅，做熟了更划算。"},
    -- fn245
        {"锅就在旁边，给自己做顿像样的饭。"},
    -- fn246
        {"先留着这几样，我有个好菜谱。"},
    -- fn247
        {"添好材料，接下来就交给火候了。"},
    -- fn248
        {"冰箱里的材料正好够，今天不用啃生的了。"},
    },
    recipe_clear = {
    -- fn249
        {"锅里还有上次的材料，我先收好再开工。"},
    -- fn250
        {"这些还能用，找个合适的地方存起来。"},
    -- fn251
        {"先腾出锅，接下来按你的菜谱做。"},
    },
    recipe_ready = {
    -- fn252
        {"出锅啦，闻着就不错。"},
    -- fn253
        {"这份先收好，饿了就有饭吃。"},
    -- fn254
        {"没白忙活，热乎饭到手了。"},
    -- fn255
        {"做好啦，带上继续赶路。"},
    },
    cook = {
    -- fn256
        {"热乎一点，吃着也舒服些。"},
    -- fn257
        {"慢慢烤，别烤焦了。"},
    -- fn258
        {"等一小会儿就好了。"},
    -- fn259
        {"先把这份食物处理好。"},
    -- fn260
        {"火候要看仔细些。"},
    -- fn261
        {"能好好吃上一顿就好了。"},
    },
    eat = {
    -- fn262
        {"先吃一点，再继续吧。"},
    -- fn263
        {"肚子舒服些，才有力气。"},
    -- fn264
        {"这顿饭来得正好。"},
    -- fn265
        {"不能只顾着忙呀。"},
    -- fn266
        {"慢慢吃，不着急。"},
    -- fn267
        {"吃过了，就能继续赶路了。"},
    },
    fed = {
    -- fn268
        {"谢谢你，还记得给我留一份。"},
    -- fn269
        {"收到啦，你也别饿着自己。"},
    -- fn270
        {"你这么照顾我，我很开心。"},
    -- fn271
        {"谢谢，这一口很暖心。"},
    -- fn272
        {"有你惦记着，真好。"},
    -- fn273
        {"我吃到了，你也要照顾好自己呀。"},
    -- fn274
        {"谢谢你陪我吃东西。"},
    -- fn275
        {"这份心意我收下了。"},
    },
    fed_careful = {
    -- fn276
        {"谢谢你，不过这个要小心吃呢。"},
    -- fn277
        {"我吃下了，接下来缓一缓。"},
    -- fn278
        {"这口滋味有些特别。"},
    -- fn279
        {"别担心，我会留意自己的身体。"},
    -- fn280
        {"下次我们找些更合适的吃吧。"},
    -- fn281
        {"你的心意我知道啦，食物也要挑一挑。"},
    },
    gift = {
    -- fn282
        {"给我的吗？谢谢，我会好好用的。"},
    -- fn283
        {"有这个在，路上就安心些了。"},
    -- fn284
        {"谢谢你替我准备这些。"},
    -- fn285
        {"我收好了，你别担心。"},
    -- fn286
        {"又麻烦你照顾我了。"},
    -- fn287
        {"这份装备，我会珍惜的。"},
    -- fn288
        {"谢谢，有需要的时候就能用上了。"},
    -- fn289
        {"你也给自己留好装备呀。"},
    },
    feed_player = {
    -- fn290
        {"你先吃一点，别饿着自己。"},
    -- fn291
        {"慢慢吃，我会陪着你的。"},
    -- fn292
        {"看起来饿了，先补充一点力气吧。"},
    -- fn293
        {"这份食物给你，路还要继续走呢。"},
    -- fn294
        {"先吃饱一点，再继续忙，好吗？"},
    -- fn295
        {"别只顾着赶路，也要照顾好自己。"},
    -- fn296
        {"我这里还有一些，先拿去吃吧。"},
    -- fn297
        {"希望这一口能让你舒服些。"},
    },
    beefalo_feed = {
    -- fn298
        {"来，吃点东西，慢慢变乖。"},
    -- fn299
        {"别闹，吃饱了才有力气驮我们。"},
    -- fn300
        {"树枝和草都有，今天一定把你哄好。"},
    -- fn301
        {"顺从一点嘛，我还给你留了好吃的。"},
    -- fn302
        {"来，先把肚子填到舒服。"},
    -- fn303
        {"这头牛的脾气，还得慢慢练。"},
    -- fn304
        {"别顶我，我是来送饭的。"},
    -- fn305
        {"一口一口来，咱们慢慢熟悉。"},
    -- fn306
        {"吃饱就歇会儿，不急着赶路。"},
    -- fn307
        {"好好吃饭，下次可别把我甩下来了。"},
    },
    beefalo_cook = {
    -- fn308
        {"我去煮些蒸树枝，给牛准备口粮。"},
    -- fn309
        {"树枝够多了，正好做点牛喜欢的。"},
    -- fn310
        {"先把牛照顾好，赶路才省心。"},
    },
    player_takes_food = {
    -- fn311
        {"饿了就直说嘛，怎么还拿我的口粮。"},
    -- fn312
        {"最近穷得吃不起饭了吗？我这里还有一点。"},
    -- fn313
        {"拿吧拿吧，别把自己饿坏了。"},
    -- fn314
        {"原来你也惦记着我的这口饭呀。"},
    -- fn315
        {"慢慢吃，别噎着。我可不跟你抢。"},
    -- fn316
        {"下次饿了叫我一声，咱们一起吃。"},
    },
    player_takes_sack = {
    -- fn317
        {"连我的饭盒也拿走？你是饿得有多急呀。"},
    -- fn318
        {"这个饭盒我还要用呢，别拿去卖了。"},
    -- fn319
        {"拿我的熊桶做什么，自己没有饭盒吗？"},
    -- fn320
        {"饭盒可以借你，记得里面的吃的也别浪费。"},
    -- fn321
        {"我的午饭跟着你跑了，晚上可得请我吃饭。"},
    -- fn322
        {"你拿饭盒，我拿什么装饭呀？"},
    },
    beefalo_cooked = {
    -- fn323
        {"蒸树枝好了，给我们的牛留着。"},
    -- fn324
        {"这一锅可不是给咱们吃的哦。"},
    -- fn325
        {"牛的口粮收好了，下次饿了就有得吃。"},
    },
    hurt = {
    -- fn326
        {"有点疼……我会小心的。"},
    -- fn327
        {"先避开这里。"},
    -- fn328
        {"我还撑得住。"},
    -- fn329
        {"别再这样了，好吗？"},
    -- fn330
        {"缓一口气，我还能走。"},
    -- fn331
        {"得更小心一点了。"},
    },
    meal_open = {
    -- fn332
        {"我看看随身带的食物。"},
    -- fn333
        {"先打开熊桶，吃一点再走。"},
    -- fn334
        {"吃的就在身边，不用跑远。"},
    -- fn335
        {"我带了口粮，先补充点力气。"},
    },
    meal_take = {
    -- fn336
        {"我从这里拿一点吃的。"},
    -- fn337
        {"先吃需要的，剩下的放回来。"},
    -- fn338
        {"这里还有食物，正好补充一下。"},
    -- fn339
        {"拿出来吃一口，不会都带走的。"},
    },
    meal_return = {
    -- fn340
        {"剩下的放回原处。"},
    -- fn341
        {"吃好了，把余下的收好。"},
    -- fn342
        {"刚才暂存的食物，现在可以放回去了。"},
    -- fn343
        {"没吃完的留在这里保管。"},
    },
    player_attack = {
    -- fn344
        {"你为什么要攻击我？先停手，我们可以谈谈。"},
    -- fn345
        {"别再打我了，我不会对你动手。"},
    -- fn346
        {"我是来帮忙的，不是来挨打的。"},
    -- fn347
        {"你再这样，我只能保护自己了。"},
    },
    ghost_return_question = {
    -- fn348
        {"我会先留在这里。可以让我回去拿东西吗？"},
    -- fn349
        {"如果你同意，我可以回去把东西带回来。"},
    -- fn350
        {"我能回去取一些物资，再回来找你吗？"},
    },
    fight = {
    -- fn351
        {"小心，我会照应你的。"},
    -- fn352
        {"别慌，我们看准时机。"},
    -- fn353
        {"我不会让你独自应付的。"},
    -- fn354
        {"保持距离，别受伤。"},
    -- fn355
        {"来不及躲，就一起应对吧。"},
    -- fn356
        {"我在这里，不要怕。"},
    -- fn357
        {"看准时机，别让它喘过气来。"},
    -- fn358
        {"我来牵制它，你找机会攻击。"},
    -- fn359
        {"别乱了阵脚，我们一起上。"},
    -- fn360
        {"退一步，等它先出手。"},
    -- fn361
        {"我还能打，继续！"},
    },
    fight_boss = {
    -- fn362
        {"这么大的家伙也不是不能打，跟紧我！"},
    -- fn363
        {"巨兽来了，别站在它正面！"},
    -- fn364
        {"我来帮你牵制它，抓住机会！"},
    -- fn365
        {"盯住它的动作，别被范围攻击卷进去。"},
    -- fn366
        {"这场仗有点大，但我们不是一个人。"},
    -- fn367
        {"看准时机，别让它喘过气来。"},
    -- fn368
        {"我们先拆掉它的节奏，再找机会重击。"},
    -- fn369
        {"它要放大招了，散开！"},
    -- fn370
        {"别站在它脚下，范围攻击要来了。"},
    },
    flee = {
    -- fn371
        {"这里不安全，先走吧。"},
    -- fn372
        {"活着离开，比什么都重要。"},
    -- fn373
        {"我们换条路。"},
    -- fn374
        {"别硬撑，退开一点。"},
    -- fn375
        {"先离远些，再想办法。"},
    -- fn376
        {"跟紧些，我们离开这里。"},
    },

    -- ---------- 打招呼与关心（会自动加上"名字，"前缀）----------
    greeting = {
    -- fn377
        {"你好。"},
    -- fn378
        {"见到你真好。"},
    -- fn379
        {"一路还顺利吗？"},
    -- fn380
        {"路上小心呀。"},
    -- fn381
        {"忙累了就歇一会儿吧。"},
    -- fn382
        {"希望你今天也平平安安。"},
    },
    care_health = {
    -- fn383
        {"你还好吗？"},
    -- fn384
        {"你看起来受伤了，先缓一缓吧。"},
    -- fn385
        {"别太勉强自己，我陪你休息一会儿。"},
    -- fn386
        {"先照顾好自己，好吗？我有些担心你。"},
    },
    care_hunger = {
    -- fn387
        {"你要吃饱饱啊！"},
    -- fn388
        {"肚子是不是饿了？我们找点吃的吧。"},
    -- fn389
        {"忙了这么久，要不要吃点东西呀。"},
    -- fn390
        {"别饿着自己呀，我陪你找吃的。"},
    },
    care_sanity = {
    -- fn391
        {"你要好好休息啊！"},
    -- fn392
        {"是不是有些累了？我们慢一点吧。"},
    -- fn393
        {"别绷得太紧，停下来歇一会儿吧。"},
    -- fn394
        {"我在这里陪着你，安心休息一下吧。"},
    },

    -- ---------- 收到放在身上的食物 ----------
    gift_sack = {
    -- fn395
        {"谢谢你送的熊桶，做好的饭可以好好保存了。"},
    -- fn396
        {"这下随身的料理有地方放了，谢谢你。"},
    -- fn397
        {"我会把料理收进去，好好用它。"},
    },
    gift_food = {
    -- fn398
        {"这些吃的先放我这里吗？我会好好收着。"},
    -- fn399
        {"谢谢，我先替你拿着。"},
    -- fn400
        {"有吃的在身上，心里踏实多了。"},
    -- fn401
        {"这份口粮我收下啦。"},
    -- fn402
        {"你总是想着让我吃饱。"},
    },
    gift_food_settled = {
    -- fn403
        {"这些吃的一直放在我这儿，谢谢你惦记着。"},
    -- fn404
        {"你给的这份口粮，我一直留着呢。"},
    -- fn405
        {"有人愿意分东西给我，真的很开心。"},
    -- fn406
        {"这份心意我记下了。"},
    -- fn407
        {"谢谢你，我不会饿肚子了。"},
    },

    -- ---------- 原地待命 ----------
    hold_position = {
    -- fn408
        {"好，我就在这里等你。"},
    -- fn409
        {"我不走远，就在这附近。"},
    -- fn410
        {"知道了，我留在这儿。"},
    -- fn411
        {"我在这里守着，你放心去吧。"},
    -- fn412
        {"好的，我原地待命。"},
    },
    hold_idle = {
    -- fn413
        {"我还在这里等着呢。"},
    -- fn414
        {"就在这附近走走，不会走远的。"},
    -- fn415
        {"你回来的时候，我一定还在。"},
    -- fn416
        {"这地方我记住了。"},
    -- fn417
        {"慢慢来，我不急。"},
    },

    -- ---------- 切换基地 ----------
    base_set = {
    -- fn418
        {"好，以后这里就是我们的家了。"},
    -- fn419
        {"我记住这个地方了。"},
    -- fn420
        {"新家就定在这里吧。"},
    -- fn421
        {"以后我就在这附近等你。"},
    -- fn422
        {"这里挺好的，我喜欢。"},
    },
    base_idle = {
    -- fn423
        {"在家附近走走，心里安稳。"},
    -- fn424
        {"这里就是家了呢。"},
    -- fn425
        {"我不会离家太远的。"},
    -- fn426
        {"家里有吃的就好办了。"},
    -- fn427
        {"回到熟悉的地方，真舒服。"},
    },

    -- ---------- 迟来的伙伴（世界已经过了 200 天）----------
    late_join = {
    -- fn428
        {"这个世界已经走了很久了呢，我就不乱盖房子了。"},
    -- fn429
        {"你们已经安顿好了，我跟着你们就行。"},
    -- fn430
        {"我只采一点草和树枝，别的东西先不动。"},
    -- fn431
        {"这里的东西都是你们的，我不会乱拿。"},
    },
    wander = {
    -- fn432
        {"没什么吃的了，我到处走走看看。"},
    -- fn433
        {"出去转一圈，说不定能找到点什么。"},
    -- fn434
        {"路还长，慢慢走吧。"},
    -- fn435
        {"我去远一点的地方看看。"},
    },
    ask_pickup = {
    -- fn436
        {"地上这些东西，我可以捡起来吗？"},
    -- fn437
        {"这些不是草和食物，要我收起来吗？"},
    -- fn438
        {"我看到一些材料，需要我捡吗？说一声可以就行。"},
    -- fn439
        {"这些东西能动吗？我怕是你们要用的。"},
    },
    pickup_allowed = {
    -- fn440
        {"好，那我就帮你们把东西收起来。"},
    -- fn441
        {"明白了，以后看到材料我就捡。"},
    -- fn442
        {"谢谢，我会小心收好的。"},
    },

    -- ---------- 死亡与复活 ----------
    revived_thanks = {
    -- fn443
        {"谢谢你把我带回来……我还以为再也见不到你了。"},
    -- fn444
        {"是你救了我吗？谢谢，我记住了。"},
    -- fn445
        {"我回来了。谢谢你没有放弃我。"},
    -- fn446
        {"这份恩情，我会用行动还的。"},
    -- fn447
        {"还能站在这里，多亏了你。"},
    },
    revive_player = {
    -- fn448
        {"别怕，我在这儿，回来吧。"},
    -- fn449
        {"把这个拿好，我们还没走完呢。"},
    -- fn450
        {"我来晚了，抱歉。快回来。"},
    -- fn451
        {"这颗心给你，站起来吧。"},
    -- fn452
        {"我不会丢下你的。"},
    },
    revive_drop = {
    -- fn453
        {"我把它放在这儿了，去碰一下就能回来。"},
    -- fn454
        {"这个能带你回来，就在你脚边。"},
    -- fn455
        {"能帮的我都放下了，剩下的靠你自己。"},
    -- fn456
        {"看到了吗？去作祟它。"},
    },

    -- ---------- 更换伙伴（告别与到来）----------
    -- 告别是说给在场所有人听的，所以不要在这里写任何具体名字。
    farewell = {
    -- fn457
        {"大家……我要走了。谢谢你们陪我这一程。"},
    -- fn458
        {"该说再见了。别送我，我自己走就好。"},
    -- fn459
        {"我会记得这里的每一天的。保重。"},
    -- fn460
        {"不用担心我，很快会有人来陪你们的。"},
    -- fn461
        {"路要分开走，但我不会忘记你们。"},
    },
    switch_arrive = {
    -- fn462
        {"你们好，以后请多关照。"},
    -- fn463
        {"听说这里有人在等我？"},
    -- fn464
        {"希望我们能成为好朋友"},
    -- fn465
        {"这是哪，有人在吗？"},
    },

    -- ---------- 冷热与光线 ----------
    cold = {
    -- fn466
        {"有点冷了，我加件保暖的。"},
    -- fn467
        {"冻得手都僵了，先穿上吧。"},
    -- fn468
        {"这天气可真凉。"},
    },
    hot = {
    -- fn469
        {"太热了，我换个凉快点的。"},
    -- fn470
        {"这个天气，得想办法降降温。"},
    -- fn471
        {"晒得有点晕，先遮一遮。"},
    },
    worn_out = {
    -- fn472
        {"这件快坏了，我先脱下来收好。"},
    -- fn473
        {"再穿下去就彻底坏了，先收起来吧。"},
    -- fn474
        {"东西快用坏了，得省着点。"},
    },
    dark = {
    -- fn475
        {"天黑了，我点个灯。"},
    -- fn476
        {"暗下来了，跟紧我。"},
    -- fn477
        {"有光就安心多了。"},
    },
}

M.replies = {
    -- fn478
    command_refuse_human = {"按理说，你这个级别的人类还没有权力命令我，但是为了满足你，我会听你的下一条命令。"},
    -- fn479
    describe_carry_statue = {"我去搬最近的雕像，然后跟着你走。"},
    -- fn480
    carry_statue_follow = {"雕像搬好了，我会抱着它跟着你。附近有牛的话，我再骑牛搬。"},
    -- fn481
    carry_statue_mount = {"抱稳了，雕像也能坐牛赶路。"},
    -- fn482
    carry_statue_none = {"附近没有我能搬的雕像。"},
    -- fn483
    describe_rockfruit = {"我先用工具开采石果，没有工具就摘附近的石果灌木。"},
    -- fn484
    describe_bullkelp = {"好的，摘完我再放进冰箱。"},
    -- fn485
    describe_dry_meat = {"我把身上能晾的食材都挂到附近的晾肉架上。"},
    -- fn486
    dry_meat_done = {"能晾的食材都挂好了，接下来交给风和太阳。"},
    describe_monkeytail = {
    -- fn487
        "我先摘附近的猴尾草和芦苇，五秒后再看一圈。",
    -- fn488
        "收到，我会把这附近能摘的猴尾草和芦苇都收好。",
    -- fn489
        "猴尾草和芦苇交给我吧，我会分批检查附近。",
    -- fn490
        "我去找附近能采摘的猴尾草和芦苇，五秒后再确认一遍。",
    },
    monkeytail_done = {
    -- fn491
        "猴尾草和芦苇都收好了，我把材料带回来了。",
    -- fn492
        "这一带能摘的猴尾草和芦苇已经找过了。",
    -- fn493
        "材料在我身上，附近的芦苇没有漏掉。",
    -- fn494
        "采集结束啦，芦苇都在我这儿，交给你安排。",
    },
    monkeytail_none = {
    -- fn495
        "附近没有能摘的猴尾草或芦苇。",
    -- fn496
        "我找了一圈，这次没有采到猴尾草或芦苇。",
    -- fn497
        "附近的目标都不适合采摘，我先回来。",
    },
    describe_banana = {
    -- fn498
        "我去摘附近二十格内的香蕉丛，摘完交给你或放进冰箱。",
    -- fn499
        "香蕉交给我吧，我只摘这附近的，装好后再回来。",
    -- fn500
        "收到香蕉任务，我去把附近成熟的香蕉丛收一遍。",
    -- fn501
        "我去找香蕉丛，摘到的香蕉会给你，或者放进附近冰箱。",
    },
    banana_done = {
    -- fn502
        "香蕉收好了，已经交给你或放进附近的冰箱。",
    -- fn503
        "附近的香蕉丛摘完啦，剩下的我先替你保管。",
    -- fn504
        "香蕉都处理好了，冰箱能放的我已经放进去。",
    -- fn505
        "任务完成，香蕉没有乱丢，都收在安全的地方。",
    },
    banana_none = {
    -- fn506
        "附近二十格内没有成熟的香蕉丛。",
    -- fn507
        "我找过了，这一圈暂时没有能摘的香蕉。",
    -- fn508
        "附近的香蕉丛都还不能采，我先回来。",
    },
    -- fn509
    pet_unknown = {"你想领养哪种宠物？比如小蛾子、小座狼或者一吃。"},
    -- fn510
    pet_full = {"我已经有小伙伴要照顾，不能再领养啦。"},
    -- fn511
    pet_materials = {"身上的领养材料还没凑齐，准备好了再叫我吧。"},
    -- fn512
    pet_no_den = {"没找到能到达的宠物巢穴，这次先回来。"},
    -- fn513
    pet_unavailable = {"这次没能办成领养，我先回来找你。"},
    -- fn514
    pet_prepare = {"材料够了，我去宠物巢穴领养，接到它就回来找你。"},
    -- fn515
    pet_done = {"领到了！我带着新朋友回来找你。"},
    -- fn516
    describe_explore = {"我去没走过的地方探探路，需要我就叫我回来。"},
    -- fn517
    describe_fish = {"我去找池塘钓鱼，钓竿坏了有材料就再做一根。要停就叫我。"},
    -- fn518
    fish_no_rod = {"没找到能用的淡水钓竿，材料或附近的科技站也不够。"},
    -- fn519
    fish_rod_done = {"钓竿用完了，现在没法再做一根，我先回来。"},
    -- fn520
    fish_rod_missing = {"钓竿不在身边了，我先回来。"},
    -- fn521
    ghost_revive_nearby = {"我去作祟附近的复活物品，等我回来。"},
    -- fn522
    ghost_revive_portal = {"我去大门那里复活，回来再找你。"},
    -- fn523
    ghost_revive_none = {"附近没有能让我作祟复活的东西。"},
    -- fn524
    ghost_revive_no_portal = {"这个世界里没找到绚丽之门或天体传送门。"},
    -- fn525
    ghost_revive_failed = {"这次没能复活，附近可用的办法都试过了。"},
    -- fn526
    ghost_revive_return = {"我活过来了，这就回来找你。"},
    -- fn527
    ghost_revive_return_blocked = {"我已经复活了，但回去的路被挡住了。来接我一下吧。"},
    -- fn528
    bookstation_prepare = {"好，我找齐材料，把书架放在你脚下这块地皮的中央。"},
    -- fn529
    bookstation_make_room = {"你挡住书架的位置啦，我先带你往旁边挪一点。"},
    -- fn530
    bookstation_blocked = {"这里放不下书架，或者旁边没有安全的落脚处。换块空地再叫我吧。"},
    -- fn531
    bookstation_cannot_make = {"做书架需要两个活木、四张莎草纸和一支羽毛笔，身上和附近箱子的材料还没凑齐。"},
    -- fn532
    bookstation_done = {"书架放好了，就在这块地皮的中央。书也有地方休息了。"},
    -- fn533
    book_last_stored = {"这本书只能再读一次，先放在书架里养护。确实急用的话，三十秒内再叫我读这本书吧。"},
    -- fn534
    book_last_keep = {"这本书只能再读一次，附近没有能存放它的书架，我先留着。三十秒内再叫我，我就读。"},
    -- fn535
    book_used_up = {"读完了，这本书也用尽了。下次得准备一本新的。"},
    -- fn536
    book_read_failed = {"这次没能读成，可能是书被移走了，或现在不适合施展它的效果。"},
    -- ---------- 聊天指令的固定回复 ----------
    -- fn537
    follow_ok = {"好，我跟你走。"},
    -- fn538
    follow_busy = {"我现在先陪另一位朋友。"},
    -- fn539
    follow_unfamiliar = {"我们还不够熟悉。"},
    -- fn540
    ride_ok = {"好，我骑牛追上你。"},
    -- fn541
    ride_stop_ok = {"好，我下来走。"},
    -- fn542
    ride_unavailable = {"现在没有能骑的牛，我先走过去。"},
    -- fn543
    ride_not_following = {"你先让我跟着你，我才能骑牛去找你。"},
    -- fn544
    affinity_work = {"好感度超过50后，我才愿意帮你做这些事。"},
    -- fn545
    affinity_items = {"好感度达到20后才能动我的物品哦。"},
    -- fn546
    affinity_name = {"好感度达到80后，再为我取个名字吧。"},
    -- fn547
    affinity_locked = {"好感度达到{1}后才能使用这个功能。"},
    -- fn548
    affinity_skin = {"好感度达到40后才能换装。"},
    -- fn549
    name_invalid = {"请取一个简短的名字，不要带换行或特殊标记。"},
    -- fn550
    name_ok = {"好呀，以后就叫我{1}。"},
    -- fn551
    special_no_book = {"我找不到这本书。"},
    -- fn552
    special_no_food = {"没有找到这份料理，或者它不在身上。"},
    -- fn553
    special_cannot_make = {"材料或设备不够，我现在做不了。"},
    -- fn554
    recipe_batch_done = {"已经做好{1}份啦，剩下的材料或厨具条件不够再做一锅了。"},
    -- fn555
    recipe_inventory_full = {"身上装不下了，我先停一停，锅里的料理给你留着。"},
    -- fn556
    special_device_place_failed = {"厨具做好了，但附近没有合适的空地，我先不乱放。"},
    -- fn557
    special_recall = {"好，我让阿比盖尔回去休息一会儿。"},
    -- fn558
    special_read_ok = {"我去找这本书来读。"},
    -- fn559
    special_spice_ok = {"好，我来给这份料理调味。"},
    -- fn560
    special_command_ok = {"好，我来准备。"},
    -- fn561
    no_backpack = {"附近没有能用的背包，我先不制作新的。"},
    -- fn562
    backpack_unreachable = {"那个背包我现在过不去，等这边安全一点再说。"},
    carry_backpack_ask = {
    -- fn563
        "重物放下了，我能先回去拿背包吗？",
    -- fn564
        "背包还留在刚才搬重物的地方，我可以去取回来吗？",
    -- fn565
        "现在空出手了，能让我先去拿回背包吗？",
    },
    carry_backpack_yes = {
    -- fn566
        "好，我去取背包，拿到就回来找你。",
    -- fn567
        "收到，取完背包我就回来。",
    -- fn568
        "那我先去拿包，有牛就骑牛过去。",
    },
    carry_backpack_done = {
    -- fn569
        "背包拿回来了，我回来了。",
    -- fn570
        "包找回来了，继续跟着你。",
    -- fn571
        "背包带回来了，我们继续走吧。",
    },
    carry_backpack_failed = {
    -- fn572
        "暂时没法取回背包，我先回来跟着你。",
    -- fn573
        "这趟没能顺利取回背包，我先跟上你。",
    },
    -- fn574
    no_tool = {"附近没有可用的工具，我暂时做不了这个。"},
    -- fn575
    hoe_incomplete = {"能整理的坑都整理好了，有些位置被作物或障碍挡住，我处理不了，你能帮帮我吗。"},

    -- ---------- 指令说明 ----------
    -- fn576
    describe_butterfly = {"好，我去打你周围的蝴蝶，不会追太远。"},
    -- fn577
    butterfly_none = {"你附近没有我现在能打到的蝴蝶。"},
    -- fn578
    butterfly_done = {"附近能打的蝴蝶已经处理好了，飞远的就不追了。"},
    -- fn579
    describe_sit = {"好，我找最近的空椅子坐下。"},
    -- fn580
    sit_unavailable = {"附近没有能坐的空椅子，我先站着吧。"},
    -- fn581
    sit_stop_ok = {"好，我下来了，先活动一会儿。"},
    -- fn582
    describe_dig_grass = {"我去拿铲子，把你附近能挖的草丛挖出来。"},
    -- fn583
    describe_dig_sapling = {"我来挖附近的树苗，挖出来的也会收好。"},
    -- fn584
    describe_dig_stump = {"我来清理附近的树根，长着的树就不动了。"},
    -- fn585
    dig_full = {"身上装不下了，我先停手，免得挖出来没地方放。"},
    -- fn586
    dig_none = {"你附近没有我现在能挖的目标。"},
    -- fn587
    dig_done = {"这一圈能挖的都处理好了。"},
    -- fn588
    describe_hoe = {"锄禾日当午，汗滴禾下土。"},
    -- fn589
    describe_water = {"植物宝宝要多喝水呀！"},
    -- fn590
    describe_chop = {"砍树，砍树，如果能盖房子就好了。"},
    -- fn591
    describe_mine = {"今天扮演的角色是矿工，嘿呦！"},
    -- fn592
    describe_grass = {"我帮你收些好东西。"},
    -- fn593
    describe_harvest = {"我来帮你收菜吧。"},
    -- fn594
    describe_seeds = {"我会帮你捡种子，为我们的丰收计划做准备。"},
    -- fn595
    describe_tidy = {"我会帮你收拾这里的。"},
    -- fn596
    describe_hold = {"我会待在这里等你~"},
    -- fn597
    describe_base = {"以后这里就是我的家啦！"},
    -- fn598
    base_needs_follow = {"你得先让我跟着你，我才知道要搬到哪里。"},
    -- fn599
    switch_needs_follow = {"抱歉，我还不想走。"},
    -- 玩家说"带走吧/送你/不要了"：走的时候把身上的东西一起带走
    -- fn600
    farewell_gift_ok = {"那我就都收下了，走的时候一起带走。"},
    -- fn601
    farewell_gift_cancel = {"好，那我走的时候把东西留下。"},
}

return M

