-- ===========================================================================
--  聊天指令关键词配置 / Chat command keyword configuration
--  ---------------------------------------------------------------------
--  这个文件决定"你在聊天框里说什么，伙伴会做什么"，随便改，不影响其他逻辑。
--
--  用法：
--  1. 说话时必须带上伙伴的名字，伙伴才会听。例如"温蒂，砍树"。
--  2. 每一条 zh / en 里的词都是"包含匹配"：只要你说的话里出现这个词就算数。
--     中文不需要空格；英文会自动按单词边界匹配，"ok" 不会误配 "okay"。
--  3. 同时匹配到多个指令时，**最长的词获胜**。所以想让某个词优先，
--     就把它写得长一点，例如"砍树"比"砍"优先。
--     长度一样时，**这个文件里靠前的那一条获胜**。
--     例如"捡种子"排在"捡东西"前面，所以说"捡种子"是去捡种子而不是整理。
--     想调整优先级，把整条 { id = ... } 往上或往下挪即可。
--  4. 加词就在花括号里多写一行，删词直接删掉那一行。
--     一组可以留空 {}，表示这个指令没有中文（或英文）触发词。
--  5. 等号左边的 id 是给程序用的，**不要改也不要删**，只改引号里的词。
--
--  特别说明：
--  * allow_pickup（可以/行/好）只在伙伴刚问完"能不能捡"的 90 秒内才会生效，
--    平时聊天说"好"不会误触发。
--  * set_base（基地/家）只有伙伴正在跟随的那个玩家说才有效。
--  * hold_position（别动/在这等我）伙伴站在你旁边时也能听，不必正在跟随。
-- ===========================================================================

return {
    { id = "revive",
        zh = {"复活", "重生", "归来", "活"},
        en = {"revive", "resurrect", "come back to life"} },
    -- 换伙伴告别时把东西一起带走，而不是丢在原地。
    -- 说完这句之后再去面板换伙伴，伙伴就会揣着所有家当走远消失。
    -- 想反悔就说"东西留下"。排在最前面，所以和下面等长的词撞车时它优先。
    { id = "farewell_gift",
        zh = {"带走吧","拿走吧","不要了","送你"},
        en = {"take it with you", "take them with you", "it's yours", "keep it"} },
    { id = "farewell_keep",
        zh = {"东西留下","留下东西","别带走"},
        en = {"leave it behind", "leave your things", "don't take it"} },

    -- 别跟着我了
    { id = "stop_follow",
        zh = {"别跟着我","别找我","走开","快走","离开","别烦我","你走","自己玩","一边去"},
        en = {"don't follow me", "stop following", "leave me alone", "go away",
              "play on your own"} },

    -- 停止当前的工作
    { id = "stop_task",
        zh = {"停下来","停吧","别干了","休息","停止","别捡"},
        en = {"stop working", "stop now", "take a break", "stop"} },

    -- 原地待命：以当前位置为家，32 单位内闲逛，不再自己建基地
    { id = "hold_position",
        zh = {"留在这","在这等我","待在这","就在这","别动","在这","待着"},
        en = {"wait here", "stay here", "hold position", "stay put",
              "don't move", "hold still"} },

    -- 切换基地：只有正在跟随的玩家说才有效，永久生效到下次切换
    { id = "set_base",
        zh = {"这是家","新基地","基地","家"},
        en = {"this is home", "new base", "make this home", "our base", "home base"} },

    -- 回答伙伴"能不能捡这些东西"的提问
    { id = "allow_pickup",
        zh = {"没问题","可以","好的","行","好","可"},
        en = {"yes", "sure", "go ahead", "ok", "okay", "no problem"} },

    -- 跟着我
    { id = "follow",
        zh = {"跟着我","跟我来","来我这","找我","跟随我","跟随","陪我","一起走",
              "一块走","到我这","到这来","回来"},
        en = {"follow me", "come with me", "come here", "find me",
              "stay with me", "let's go", "come back"} },

    -- 询问伙伴当前正在做什么，不改变当前行为
    { id = "ask_activity",
        zh = {"干什么", "做什么", "干啥", "做啥"},
        en = {"what are you doing", "what are you up to"} },

    { id = "explore",
        zh = {"探图", "开图", "出去逛", "出去走", "出门走"},
        en = {"explore", "go exploring", "scout the map"} },
    { id = "stop_fish",
        zh = {"别钓", "走吧"},
        en = {} },
    { id = "fish",
        zh = {"钓鱼", "打鱼", "抓鱼"},
        en = {"go fishing", "catch fish", "fish"} },
    { id = "rockfruit",
        zh = {"石果"},
        en = {"rock fruit", "rock avocado"} },
    { id = "bullkelp",
        zh = {"海带"},
        en = {"bull kelp", "bullkelp"} },
    { id = "dry_meat",
        zh = {"晾肉", "晾干", "晾肉架"},
        en = {"dry meat", "dry food", "meat rack"} },

    -- 坐椅子与起身
    { id = "sit",
        zh = {"坐上去", "椅子", "凳子"},
        en = {"sit down", "take a seat", "chair", "stool"} },
    { id = "stop_sit",
        zh = {"站起来", "别坐", "下椅子", "离开椅子"},
        en = {"stand up", "stop sitting", "leave the chair"} },
    -- 骑绑定的牛跟随玩家
    { id = "ride",
        zh = {"上牛", "坐牛", "骑"},
        en = {"mount", "ride"} },
    -- 下牛并恢复普通步行跟随
    { id = "stop_ride",
        zh = {"停止骑牛", "别骑", "下来", "下牛", "走路"},
        en = {"stop riding", "dismount", "get off", "walk"} },

    -- 背包
    { id = "backpack_drop",
        zh = {"丢包","包丢下来"},
        en = {"drop backpack", "drop your bag", "put down your backpack"} },
    { id = "backpack",
        zh = {"换包","捡包","拿包","换一个","另一个","别的包","这个包"},
        en = {"change backpack", "swap backpack", "pick up backpack",
              "take this bag", "another bag"} },

    -- 吃饭
    { id = "food",
        zh = {"吃饭","快吃","吃个这","吃"},
        en = {"eat something", "have a meal", "eat"} },

    -- 采集与干活（都需要好感度超过 50）
    { id = "butterfly",
        zh = {"打蝴蝶", "杀蝴蝶"},
        en = {"hunt butterflies", "kill butterflies"} },
    { id = "dig_grass",
        zh = {"挖草", "移植草", "铲草"},
        en = {"dig grass", "transplant grass"} },
    { id = "dig_sapling",
        zh = {"挖树苗", "移植树苗", "铲树苗"},
        en = {"dig saplings", "transplant saplings"} },
    { id = "dig_stump",
        zh = {"挖树", "挖树根", "铲树根", "铲掉"},
        en = {"dig stumps", "dig tree roots"} },
    { id = "grass",
        zh = {"摘草","摘树枝","摘点草","摘点树枝","收集草","收集树枝"},
        en = {"pick grass", "pick twigs", "gather grass", "gather twigs"} },
    { id = "mine",
        zh = {"挖矿","挖石头","挖开","挖掉","挖","敲"},
        en = {"mine rocks", "go mining", "mine"} },
    { id = "chop",
        zh = {"砍树","砍木头","砍"},
        en = {"chop trees", "chop wood", "chop"} },
    { id = "harvest",
        zh = {"收菜","摘菜","收庄稼"},
        en = {"harvest crops", "pick crops", "harvest"} },
    { id = "seeds",
        zh = {"捡种子"},
        en = {"collect seeds", "pick up seeds"} },
    { id = "hoe",
        zh = {"锄地","挖地","挖田","挖坑","刨地","挖一下田","刨坑"},
        en = {"till soil", "hoe the farm", "till the farm"} },
    { id = "water",
        zh = {"浇水","浇田","灌水"},
        en = {"water crops", "water the farm", "water"} },
    { id = "tidy",
        zh = {"整理基地","打扫","捡垃圾","整理","收拾基地","收拾","捡东西","捡起来"},
        en = {"tidy the base", "clean up", "collect rubbish", "tidy", "tidy up",
              "clean the base", "pick up rubbish", "pick up trash",
              "pick up items", "pick things up"} },
    { id = "equipment",
        zh = {"捡装备","拾装备","捡武器","捡护甲"},
        en = {"pick up equipment", "collect equipment", "pick up gear",
              "collect gear"} },
    { id = "carry_statue",
        zh = {"搬起来", "搬雕像", "搬一下", "搬雕塑", "搬东西"},
        en = {"carry statue", "move statue", "carry sculpture"} },
}
