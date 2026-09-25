-- ===========================================================================
--  English companion dialogue configuration
--  ---------------------------------------------------------------------
--  这个文件是伙伴所有台词的唯一来源，随便改，不会影响其他逻辑。
--
--  1. lines 里的每一组都是"随机台词"，伙伴会从中随机挑一条说出来。
--     每一条写成 {"English"}，只填写 English 内容。
--     一组里至少保留 1 条；想让随机效果好一些，建议每组 4 条以上。
--
--  2. replies 里的每一条都是"固定回复"，只有一条 {"English"}。
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

M.lines = {
    pet_feed = {
    -- fn1
        {"Hungry, little one? Here, have a bite."},
    -- fn2
        {"This little snack is for you. Take your time."},
    -- fn3
        {"No need to circle me. I know you're hungry."},
    -- fn4
        {"Have a bite, then let's walk some more."},
    },
    pet_travel = {
    -- fn5
        {"Supplies ready. I'm off to meet a little companion."},
    -- fn6
        {"I wonder if it'll be happy to meet me."},
    -- fn7
        {"We'll have another friend when I get back."},
    },
    pet_adopt = {
    -- fn8
        {"Come along. We'll travel together from now on."},
    -- fn9
        {"I've brought you a treat. Come home with me."},
    -- fn10
        {"I'll take care of you, little one."},
    },
    explore = {
    -- fn11
        {"I haven't been this way. Let's take a look."},
    -- fn12
        {"I'm keeping track of the route. Call me when you need me."},
    -- fn13
        {"I'll take care of myself, then keep exploring."},
    -- fn14
        {"Let's see what's beyond these woods."},
    },
    explore_mount = {
    -- fn15
        {"With a beefalo along, we can explore a little farther."},
    -- fn16
        {"Let's ride out somewhere we haven't been."},
    -- fn17
        {"All taken care of. Back in the saddle to explore."},
    },
    explore_dismount = {
    -- fn18
        {"Let's find some clear ground. I need to get down for a moment."},
    -- fn19
        {"I'll walk this stretch. I'm still exploring."},
    -- fn20
        {"I'll get down to take care of something, then carry on."},
    },
    fish_prepare = {
    -- fn21
        {"First, a fishing rod. The fish won't wait forever."},
    -- fn22
        {"I'll find a rod, or make one."},
    -- fn23
        {"Once the supplies are ready, I'll head to a pond."},
    },
    fish_search = {
    -- fn24
        {"No suitable pond here. I'll keep looking."},
    -- fn25
        {"I can't fish here for now. Let's try elsewhere."},
    -- fn26
        {"Rod ready. Now I just need a good pond."},
    },
    fish_replace = {
    -- fn27
        {"The rod wore out. Let's see if I can make another with what I'm carrying."},
    -- fn28
        {"I'll replace the rod, then get back to fishing."},
    -- fn29
        {"Time for a fresh rod, if I have the supplies."},
    },
    fish_cast = {
    -- fn30
        {"This looks like a good place to cast."},
    -- fn31
        {"A little patience. Let's see what bites."},
    -- fn32
        {"Come on, fish. Take the bait."},
    },
    fish_caught = {
    -- fn33
        {"Another catch, safely packed."},
    -- fn34
        {"This one will make a nice meal."},
    -- fn35
        {"A good catch. Let's cast again."},
    },
    fish_full = {
    -- fn36
        {"My pockets are full. I'll leave the fish on the bank."},
    -- fn37
        {"I'll leave this one here to pick up later."},
    -- fn38
        {"More fish than pocket space. I'll leave it here."},
    },
    butterfly_hunt = {
    -- fn39
        {"A little closer. This one flies fast."},
    -- fn40
        {"I'll keep my eye on this one."},
    -- fn41
        {"I'll get close before I swing."},
    -- fn42
        {"Stay close this time. No swinging at thin air."},
    },
    butterfly_loot = {
    -- fn43
        {"Got it. Let's pick up the food."},
    -- fn44
        {"Even a little can help in a pinch."},
    -- fn45
        {"I'll pick this up before deciding what's next."},
    },
    ghost_help = {
    -- fn46
        {"It's {1}. I've become a ghost. Could someone help revive me?"},
    -- fn47
        {"{1} needs help! Could someone bring a Telltale Heart? My belongings are still where I fell."},
    -- fn48
        {"It's {1}, floating around as a ghost. Could a friend spare a moment to revive me?"},
    -- fn49
        {"{1} is waiting for rescue. Can someone bring me back? I'll thank you properly once I'm alive."},
    -- fn50
        {"It's {1}. I could really use some help this time! Could someone come revive me?"},
    },
    ghost_help_depart = {
    -- fn51
        {"It's {1}. Carry on, everyone. I'll float to the portal to revive, then return for my belongings."},
    -- fn52
        {"{1} is heading to the portal to revive. No need to rush over; I'll come back for my things."},
    -- fn53
        {"It's {1}. Everyone seems busy. I'll revive at the portal and come back for my things."},
    },
    skin_changed = {
    -- fn54
        {"All changed! What do you think?"},
    -- fn55
        {"This outfit suits me. Thanks for picking it out."},
    -- fn56
        {"A new look lifts the spirits. I have a spring in my step!"},
    -- fn57
        {"Let me turn around. Does everything look tidy?"},
    -- fn58
        {"Looking this nice, I'd better be careful with the chores."},
    -- fn59
        {"You have good taste. You can help me choose next time too."},
    -- fn60
        {"Will our friends recognize me in this?"},
    -- fn61
        {"All freshened up. Let's get going."},
    -- fn62
        {"Do I look like an even more dependable companion now?"},
    -- fn63
        {"You've saved me ages of deciding what to wear."},
    },
    gather_hurt = {
    -- fn64
        {"That hurt to gather. I'll try somewhere else for a while."},
    -- fn65
        {"That resource bites back. I'll leave it alone for now."},
    -- fn66
        {"That cost me some health. I'll remember to avoid it for now."},
    },
    wormhole_follow = {
    -- fn67
        {"Wait for me. I'll follow you through."},
    -- fn68
        {"Go ahead. I'll be right behind you."},
    -- fn69
        {"This shortcut is sticky, but it beats the long way."},
    },
    rift_follow = {
    -- fn70
        {"Wait for me. I can use this rift too, right?"},
    -- fn71
        {"I'll follow before it closes."},
    -- fn72
        {"Go ahead. I'll jump through right behind you."},
    -- fn73
        {"Now that's an unusual shortcut."},
    },
    sit_rest = {
    -- fn74
        {"There's a chair here. I'll rest a moment; tell me when we're going."},
    -- fn75
        {"It's quiet here. My legs could use a rest."},
    -- fn76
        {"A perfectly good seat! No need to stand around."},
    -- fn77
        {"I'll enjoy the view. When you go, I'll follow."},
    },
    sit_together = {
    -- fn78
        {"Taking a seat? I'll keep you company."},
    -- fn79
        {"There's a free seat nearby. Let's rest our feet."},
    -- fn80
        {"We've walked quite a way. Let's sit and chat."},
    -- fn81
        {"Let's sit together. We can head out when you're rested."},
    },
    book_read = {
    -- fn82
        {"Let me find the page. Knowledge takes patience."},
    -- fn83
        {"Listen closely. This is no ordinary storybook."},
    -- fn84
        {"The answer in this book should come in handy."},
    -- fn85
        {"I remember this passage, but it pays to check."},
    },
    book_shelf_read = {
    -- fn86
        {"The book is on the shelf. I'll open it and read here."},
    -- fn87
        {"Found it. It can stay right on the shelf."},
    -- fn88
        {"No need to carry it around. I can read it here."},
    -- fn89
        {"I'll close the shelf when I'm done. Knowledge deserves good care."},
    },
    book_ground_pickup = {
    -- fn90
        {"The book is on the ground. I'll pick it up before reading."},
    -- fn91
        {"I found a book on the ground. Let's keep it from getting damp."},
    },
    book_store = {
    -- fn92
        {"One reading left. This book needs some time on the shelf."},
    -- fn93
        {"These pages are worn. Let's give them a rest."},
    -- fn94
        {"With a shelf nearby, we can let this book recover."},
    -- fn95
        {"These last pages need care. I'll put the book away."},
    },
    rockfruit = {
    -- fn96
        {"Leave the rock fruit to me. I'll mine the hard ones and pick the soft ones."},
    -- fn97
        {"These fruits look like rocks, and they certainly have the temperament of rocks."},
    -- fn98
        {"I'll gather the nearby rock fruit before it pretends to be innocent on the ground."},
    },
    rockfruit_ask = {
    -- fn99
        {"The rock fruit is gathered. Should I mine it open, or put it in the nearest chest?"},
    -- fn100
        {"The hard ones are ready. Should I crack them open? Tell me within thirty seconds."},
    -- fn101
        {"Should I crack the rock fruit? If you don't say, I'll call it a collection."},
    },
    rockfruit_mine_answer = {
    -- fn102
        {"All right, you said yes. I'll crack the rock fruit open."},
    -- fn103
        {"Message received. Rock shell, meet your destiny."},
    },
    rockfruit_store_answer = {
    -- fn104
        {"All right, no cracking. I'll store them for later."},
    -- fn105
        {"Fine. I won't argue with the rock fruit today. The chest can look after it."},
    },
    bullkelp = {
    -- fn106
        {"I'll gather bull kelp and try not to become kelp myself."},
    -- fn107
        {"Bull kelp, don't hide. None of you are escaping today."},
    -- fn108
        {"I'll put the kelp in the fridge when I'm done and keep it cool."},
    },
    dry_meat = {
    -- fn109
        {"I'll find the food a drying rack. Sunlight beats sweating in my bag."},
    -- fn110
        {"Are the drying racks ready? I'll hang up everything that can be dried."},
    -- fn111
        {"Today's menu is dried food. The chef is staying out of the drying process."},
    },
    dry_meat_collect = {
    -- fn112
        {"Finished drying? I'll bring this batch of flavor back."},
    -- fn113
        {"The sun worked hard. I'll put the results in the fridge."},
    -- fn114
        {"The drying rack handed in its homework. I'll collect it."},
    },
    carry_statue = {
    -- fn115
        {"This statue is a little heavy, but I can carry it."},
    -- fn116
        {"Don't rush me. This stone and I are getting acquainted."},
    -- fn117
        {"Carrying things is exercise. My arms have work today."},
    },
    carry_statue_mount = {
    -- fn118
        {"Carrying a statue on a beefalo is quite a transport upgrade."},
    -- fn119
        {"Easy, beefalo. We have a stone passenger on board."},
    -- fn120
        {"Don't worry. The statue is sitting steadier than I am."},
    },
    -- ---------- 日常行为 ----------
    ride_mount = {
    -- fn121
        {"You're too far away. Riding will be quicker."},
    -- fn122
        {"Come on, take me to them."},
    -- fn123
        {"I'll borrow your legs for the journey."},
    },
    ride_chase = {
    -- fn124
        {"I'll ride after them. I'll catch up soon."},
    -- fn125
        {"Don't go too far. I'll catch up."},
    -- fn126
        {"With a mount, I won't have to worry about falling behind."},
    },
    ride_dismount = {
    -- fn127
        {"This is close enough. I'll walk from here."},
    -- fn128
        {"Thank you for the ride."},
    -- fn129
        {"Good work. We can walk from here."},
    },
    follow = {
    -- fn130
        {"Okay, I'm right behind you."},
    -- fn131
        {"Let's go together. I'll be right here beside you."},
    -- fn132
        {"You lead the way, I'll keep up."},
    -- fn133
        {"Anywhere's fine, as long as we go together."},
    -- fn134
        {"Mm. Don't worry about losing me."},
    -- fn135
        {"Coming! Let's go."},
    },
    idle = {
    -- fn136
        {"It's peaceful here. Let's rest a bit."},
    -- fn137
        {"Let's take today slowly. No rush."},
    -- fn138
        {"It's good having somewhere to come back to."},
    -- fn139
        {"I'll wander around a bit."},
    -- fn140
        {"Every gust of wind brings something back to me."},
    -- fn141
        {"That's done. Let's catch our breath."},
    -- fn142
        {"I'm checking whether today's wind ruined my hair."},
    -- fn143
        {"Nothing urgent. My shadow and I are taking a walk."},
    -- fn144
        {"Don't mind me. I'm seriously recharging."},
    -- fn145
        {"The view is nice. Even spacing out feels worthwhile."},
    -- fn146
        {"I'm on standby and thinking about dinner."},
    -- fn147
        {"We've worked hard today. Rest when we can."},
    },
    activity_idle = {
    -- fn148
        {"Can't you tell? I'm relaxing on standby and watching the wind."},
    -- fn149
        {"Nothing urgent. I'm maintaining the peaceful atmosphere."},
    -- fn150
        {"I'm resting. Resting is part of the survival plan."},
    },
    activity_chop = {
    -- fn151
        {"Can't you tell? I'm chopping a tree."},
    -- fn152
        {"I'm gathering wood for the coming winter."},
    -- fn153
        {"Didn't you ask me to chop? I'm nearly done."},
    },
    activity_mine = {
    -- fn154
        {"I'm negotiating with this rock. It hasn't surrendered yet."},
    -- fn155
        {"I'm mining. Let's see if the ground has a surprise."},
    -- fn156
        {"I'm collecting stone and ore for the base."},
    },
    activity_dig = {
    -- fn157
        {"I'm digging. The ground will look more organized soon."},
    -- fn158
        {"I'm transplanting these plants into a better home."},
    -- fn159
        {"With a shovel in hand, the grass and saplings can take turns."},
    },
    activity_fish = {
    -- fn160
        {"I'm fishing. The rod needs more patience than I do."},
    -- fn161
        {"I'm waiting for a bite. Don't scare the pond."},
    -- fn162
        {"I'm trying to bring some seafood home for dinner."},
    },
    activity_explore = {
    -- fn163
        {"I'm exploring to see what corners of the world remain unknown."},
    -- fn164
        {"I'm scouting ahead. Don't worry, I remember the way back."},
    -- fn165
        {"I'm out for a walk. I'll bring back anything useful."},
    },
    activity_fight = {
    -- fn166
        {"I'm fighting. Let me see this visitor out."},
    -- fn167
        {"I'm protecting you, and myself while I'm at it."},
    -- fn168
        {"I'm dealing with trouble. I'll be back when it's handled."},
    },
    activity_feed = {
    -- fn169
        {"I'm feeding the little one. Its stomach is honest."},
    -- fn170
        {"I'm caring for my pet. Cute is not the only responsibility."},
    -- fn171
        {"I'm getting it a bite to eat. Almost done."},
    },
    activity_tidy = {
    -- fn172
        {"I'm organizing supplies. The chests almost know me by name."},
    -- fn173
        {"I'm putting away spare things before they wander off."},
    -- fn174
        {"I'm tidying up. A base needs some order."},
    },
    activity_cook = {
    -- fn175
        {"I'm cooking. The pot won't stay empty today."},
    -- fn176
        {"I'm turning ingredients into something more like dinner."},
    -- fn177
        {"I'm preparing a meal. Remember to eat it while it's warm."},
    },
    activity_eat = {
    -- fn178
        {"I'm eating. An important survival meeting is in session."},
    -- fn179
        {"I'm refueling. An empty stomach can't accomplish much."},
    -- fn180
        {"I'm eating properly. Don't worry, I didn't take your portion."},
    },
    activity_build = {
    -- fn181
        {"I'm crafting. These materials will soon become something useful."},
    -- fn182
        {"I'm building. A dependable base takes time."},
    -- fn183
        {"I'm making something. You'll see when it's finished."},
    },
    activity_follow = {
    -- fn184
        {"I'm following you. Am I hiding too well?"},
    -- fn185
        {"I'm walking with you and watching for useful things."},
    -- fn186
        {"I'm on standby beside you. I go where you go."},
    },
    activity_ride = {
    -- fn187
        {"I'm riding. Four legs are certainly busier than two."},
    -- fn188
        {"I'm riding to catch up. Don't run too fast."},
    -- fn189
        {"I'm traveling with my beefalo. The mount has today's distance covered."},
    },
    activity_sit = {
    -- fn190
        {"I'm resting. The chair is doing reliable work today."},
    -- fn191
        {"I'm sitting with you. My legs deserve some respect too."},
    -- fn192
        {"I'm on standby in this chair. Call me when it's time to go."},
    },
    work = {
    -- fn193
        {"Leave this one to me."},
    -- fn194
        {"Bit by bit. We'll get there."},
    -- fn195
        {"I'll be careful with it."},
    -- fn196
        {"Let's finish what's in front of us first."},
    -- fn197
        {"A little work now, rest after."},
    -- fn198
        {"I'm just glad I can help."},
    },
    chop = {
    -- fn199
        {"This wood should last us a while."},
    -- fn200
        {"A bit more wood and the night won't worry me."},
    -- fn201
        {"Careful, don't stand where it's going to fall."},
    -- fn202
        {"Let's take the wood back. We'll find plenty of uses for it."},
    -- fn203
        {"One swing at a time."},
    -- fn204
        {"These trees have grown so tall."},
    },
    mine = {
    -- fn205
        {"There's good stuff hidden inside these rocks."},
    -- fn206
        {"Mind your feet, these chips are sharp."},
    -- fn207
        {"Let's put these ores somewhere safe."},
    -- fn208
        {"A few more swings should do it."},
    -- fn209
        {"We'll be needing these materials later."},
    -- fn210
        {"Even the hardest rock cracks if you keep at it."},
    },
    gather = {
    -- fn211
        {"Let's take this one too."},
    -- fn212
        {"Slow and steady, so we don't miss any."},
    -- fn213
        {"A stock like this puts my mind at ease."},
    -- fn214
        {"If it's useful and it's on our way, I'll grab it."},
    -- fn215
        {"There's still a bit more to pick up around here."},
    -- fn216
        {"A little more in the bag."},
    },
    plant = {
    -- fn217
        {"Grow up strong here, little one."},
    -- fn218
        {"This place will be greener one day."},
    -- fn219
        {"I saved a spot just for you."},
    -- fn220
        {"Take your time growing. We'll wait."},
    -- fn221
        {"Settle your roots in and you'll be fine."},
    -- fn222
        {"This little patch is waking up."},
    },
    fertilizer_search = {
    -- fn223
        {"I'll look for fertilizer on the savanna."},
    -- fn224
        {"I've checked this patch. Let's look a little farther."},
    -- fn225
        {"The grass tufts need fertilizer. I'll look for some."},
    },
    fertilizer_collect = {
    -- fn226
        {"The grass tufts back home can use this."},
    -- fn227
        {"I'll take these home before fertilizing."},
    -- fn228
        {"A little more fertilizer for the garden."},
    },
    fertilize = {
    -- fn229
        {"Some nutrients to help you grow again."},
    -- fn230
        {"Fertilized. Now the grass can recover."},
    -- fn231
        {"That's another tuft taken care of."},
    },
    build = {
    -- fn232
        {"Now it's starting to feel like home."},
    -- fn233
        {"That's one more done."},
    -- fn234
        {"This should sit nicely right here."},
    -- fn235
        {"A bit of preparation now saves trouble later."},
    -- fn236
        {"None of those materials went to waste."},
    -- fn237
        {"Bit by bit, we'll have everything we need."},
    },
    store = {
    -- fn238
        {"Same things together, much easier to find."},
    -- fn239
        {"I'll put these away for later."},
    -- fn240
        {"A quick tidy and the bag feels lighter."},
    -- fn241
        {"Now we'll know exactly where to look."},
    -- fn242
        {"Everything has a place of its own."},
    -- fn243
        {"It never hurts to keep a little spare."},
    },
    recipe_cook = {
    -- fn244
        {"These ingredients make a better meal together."},
    -- fn245
        {"There's a pot here. Time for a proper meal."},
    -- fn246
        {"I'll save these ingredients. I have a recipe in mind."},
    -- fn247
        {"Ingredients in. Now let the heat do its work."},
    -- fn248
        {"There's enough in the fridge for a cooked meal today."},
    },
    recipe_clear = {
    -- fn249
        {"There are leftover ingredients in the pot. I'll put them away first."},
    -- fn250
        {"These are still useful. I'll find somewhere suitable to store them."},
    -- fn251
        {"I'll clear the pot, then start the dish you requested."},
    },
    recipe_ready = {
    -- fn252
        {"Dinner's ready. That smells good."},
    -- fn253
        {"I'll keep this meal for when I'm hungry."},
    -- fn254
        {"Worth the effort. A fresh meal is ready."},
    -- fn255
        {"All done. I'll take it along."},
    },
    cook = {
    -- fn256
        {"Something hot always sits better."},
    -- fn257
        {"Easy does it, mustn't burn it."},
    -- fn258
        {"Just a little longer."},
    -- fn259
        {"Let me get this one ready first."},
    -- fn260
        {"I'd better watch the heat closely."},
    -- fn261
        {"A proper meal would be so nice."},
    },
    eat = {
    -- fn262
        {"A bite first, then back to it."},
    -- fn263
        {"It's easier to keep going on a full stomach."},
    -- fn264
        {"This meal came just in time."},
    -- fn265
        {"I mustn't get so busy that I forget to eat."},
    -- fn266
        {"No need to rush a meal."},
    -- fn267
        {"That's better. Now I can carry on."},
    },
    fed = {
    -- fn268
        {"Thank you for saving a share for me."},
    -- fn269
        {"Got it! Don't let yourself go hungry either."},
    -- fn270
        {"It makes me happy, you looking after me like this."},
    -- fn271
        {"Thank you. That bite really warmed me up."},
    -- fn272
        {"It's lovely, being thought of."},
    -- fn273
        {"I've eaten. Now you take care of yourself too."},
    -- fn274
        {"Thank you for sharing a bite with me."},
    -- fn275
        {"I'll treasure the thought."},
    },
    fed_careful = {
    -- fn276
        {"Thank you, though this one needs eating carefully."},
    -- fn277
        {"Down it went. I'll take it easy for a bit."},
    -- fn278
        {"That had a rather... unusual taste."},
    -- fn279
        {"Don't worry, I'll keep an eye on how I feel."},
    -- fn280
        {"Let's find something better suited next time."},
    -- fn281
        {"I know you meant well, but let's be a bit choosier."},
    },
    gift = {
    -- fn282
        {"For me? Thank you, I'll put it to good use."},
    -- fn283
        {"With this along, the road feels safer."},
    -- fn284
        {"Thank you for getting this ready for me."},
    -- fn285
        {"It's safely stowed. Don't worry."},
    -- fn286
        {"You're looking after me again. Thank you."},
    -- fn287
        {"I'll take good care of this."},
    -- fn288
        {"Thank you. It'll be ready when I need it."},
    -- fn289
        {"Do keep some gear for yourself as well."},
    },
    feed_player = {
    -- fn290
        {"Eat something first. Don't go hungry."},
    -- fn291
        {"Take your time. I'll stay right here with you."},
    -- fn292
        {"You look hungry. Get your strength back first."},
    -- fn293
        {"This is for you. We've still got a long way to go."},
    -- fn294
        {"Eat your fill first, then back to work, all right?"},
    -- fn295
        {"Don't just push on. Look after yourself too."},
    -- fn296
        {"I've got some to spare. Here, take it."},
    -- fn297
        {"I hope this makes you feel a bit better."},
    },
    beefalo_feed = {
    -- fn298
        {"Here, have a bite. Take it slow."},
    -- fn299
        {"Easy now. You need a full belly to carry us."},
    -- fn300
        {"Twigs and grass for you. I will win you over today."},
    -- fn301
        {"Be a little more obedient. I saved you something tasty."},
    -- fn302
        {"Come on, fill your belly until you are comfortable."},
    -- fn303
        {"This beefalo has quite the temper. We will train patiently."},
    -- fn304
        {"No headbutting! I brought dinner."},
    -- fn305
        {"One bite at a time. We will get to know each other."},
    -- fn306
        {"Have a rest after eating. The road can wait."},
    -- fn307
        {"Eat up, and please do not throw me off next time."},
    },
    beefalo_cook = {
    -- fn308
        {"I am cooking beefalo feed for our ride."},
    -- fn309
        {"There are enough twigs. Time to make the beefalo's favorite."},
    -- fn310
        {"A well cared for beefalo makes the road easier."},
    },
    player_takes_food = {
    -- fn311
        {"Hungry? You could have asked before taking my rations."},
    -- fn312
        {"Having trouble finding dinner? I have some to share."},
    -- fn313
        {"Go on, take it. Do not let yourself go hungry."},
    -- fn314
        {"So you had your eye on my dinner too."},
    -- fn315
        {"Eat slowly. I will not fight you for it."},
    -- fn316
        {"Tell me next time you are hungry. We can eat together."},
    },
    player_takes_sack = {
    -- fn317
        {"Taking my lunchbox too? You must be really hungry."},
    -- fn318
        {"I still need that lunchbox. Do not go selling it."},
    -- fn319
        {"What are you doing with my sack? Do you not have one?"},
    -- fn320
        {"You can borrow the lunchbox, but do not waste the food inside."},
    -- fn321
        {"My lunch is going with you. Dinner is on you tonight."},
    -- fn322
        {"With you taking the lunchbox, where will I put my meals?"},
    },
    beefalo_cooked = {
    -- fn323
        {"The beefalo feed is ready. I will save it for our beefalo."},
    -- fn324
        {"This pot is not our dinner!"},
    -- fn325
        {"Beefalo rations packed for next time."},
    },
    hurt = {
    -- fn326
        {"That stung... I'll be more careful."},
    -- fn327
        {"I should get away from here."},
    -- fn328
        {"I can still hold on."},
    -- fn329
        {"Please, not again."},
    -- fn330
        {"Just need a breath. I can still move."},
    -- fn331
        {"I'll have to be more careful now."},
    },
    meal_open = {
    -- fn332
        {"Let me check the food I brought."},
    -- fn333
        {"I'll open my sack and have a bite."},
    -- fn334
        {"My food is right here."},
    -- fn335
        {"I packed a meal. Time to get some strength back."},
    },
    meal_take = {
    -- fn336
        {"I'll take something to eat from here."},
    -- fn337
        {"I'll eat what I need and return the rest."},
    -- fn338
        {"There's food here. Just what I need."},
    -- fn339
        {"I'll have a bite and leave the rest here."},
    },
    meal_return = {
    -- fn340
        {"The rest goes back where it belongs."},
    -- fn341
        {"That was enough. I'll put the rest away."},
    -- fn342
        {"I can return the food I kept for later now."},
    -- fn343
        {"I'll leave the uneaten food here."},
    },
    player_attack = {
    -- fn344
        {"Why are you attacking me? Stop. We can talk."},
    -- fn345
        {"Please stop hitting me. I do not want to fight you."},
    -- fn346
        {"I came to help, not to be beaten."},
    -- fn347
        {"If you keep this up, I will have to defend myself."},
    },
    ghost_return_question = {
    -- fn348
        {"I will stay here for now. May I go back for the things we need?"},
    -- fn349
        {"If you agree, I can go back and bring the things here."},
    -- fn350
        {"May I fetch some supplies and come back to you?"},
    },
    fight = {
    -- fn351
        {"Careful! I've got your back."},
    -- fn352
        {"Don't panic. We'll wait for the right moment."},
    -- fn353
        {"I won't let you face this alone."},
    -- fn354
        {"Keep your distance. Don't get hurt."},
    -- fn355
        {"No time to run, we'll take it on together."},
    -- fn356
        {"I'm right here. Don't be afraid."},
    -- fn357
        {"Watch the opening. Don't let it breathe."},
    -- fn358
        {"I'll keep it busy. Find an opening."},
    -- fn359
        {"Stay steady. We take it together."},
    -- fn360
        {"One step back. Let it swing first."},
    -- fn361
        {"I can still fight. Keep going!"},
    },
    fight_boss = {
    -- fn362
        {"Even something that big can be beaten. Stay with me!"},
    -- fn363
        {"A giant is here. Don't stand in front of it!"},
    -- fn364
        {"I'll help hold it off. Take the opening!"},
    -- fn365
        {"Watch its movement. Don't get caught in the area attack."},
    -- fn366
        {"This is a big fight, but we're not alone."},
    -- fn367
        {"Watch the opening. Don't let it breathe."},
    -- fn368
        {"Break its rhythm first, then strike hard."},
    -- fn369
        {"It's preparing something big. Spread out!"},
    -- fn370
        {"Don't stand under it. An area attack is coming."},
    },
    flee = {
    -- fn371
        {"It's not safe here. Let's go."},
    -- fn372
        {"Getting out alive matters more than anything."},
    -- fn373
        {"Let's take another route."},
    -- fn374
        {"Don't push it. Back off a little."},
    -- fn375
        {"Let's get clear first, then think."},
    -- fn376
        {"Stay close. We're leaving."},
    },

    -- ---------- 打招呼与关心（会自动加上"名字，"前缀）----------
    greeting = {
    -- fn377
        {"hello."},
    -- fn378
        {"it's good to see you."},
    -- fn379
        {"how has your day been?"},
    -- fn380
        {"take care out there."},
    -- fn381
        {"rest a bit when you get tired."},
    -- fn382
        {"I hope today treats you kindly."},
    },
    care_health = {
    -- fn383
        {"are you all right?"},
    -- fn384
        {"you look hurt. Take a moment."},
    -- fn385
        {"don't push yourself. I'll rest here with you."},
    -- fn386
        {"look after yourself first, all right? I'm worried about you."},
    },
    care_hunger = {
    -- fn387
        {"make sure you eat plenty!"},
    -- fn388
        {"getting hungry? Let's go find you something."},
    -- fn389
        {"you've been at it a while. Fancy a bite?"},
    -- fn390
        {"don't go hungry. I'll help you find some food."},
    },
    care_sanity = {
    -- fn391
        {"you really need some proper rest!"},
    -- fn392
        {"feeling worn out? Let's slow down."},
    -- fn393
        {"don't wind yourself so tight. Stop and rest a while."},
    -- fn394
        {"I'm right here with you. Rest easy."},
    },

    -- ---------- 收到放在身上的食物 ----------
    gift_sack = {
    -- fn395
        {"Thank you for the sack. My meals will keep well now."},
    -- fn396
        {"Now I have somewhere to keep my meals. Thank you."},
    -- fn397
        {"I'll put my meals inside and take good care of it."},
    },
    gift_food = {
    -- fn398
        {"Am I holding this food for you? I'll keep it safe."},
    -- fn399
        {"Thank you. I'll carry it for you."},
    -- fn400
        {"Food in my bag puts my mind at ease."},
    -- fn401
        {"I'll take these rations, then."},
    -- fn402
        {"You're always making sure I'm fed."},
    },
    gift_food_settled = {
    -- fn403
        {"This food has been with me all this time. Thank you for thinking of me."},
    -- fn404
        {"I've been keeping the rations you gave me."},
    -- fn405
        {"It really does make me happy, being shared with."},
    -- fn406
        {"I won't forget this kindness."},
    -- fn407
        {"Thank you. I won't go hungry now."},
    },

    -- ---------- 原地待命 ----------
    hold_position = {
    -- fn408
        {"Okay, I'll wait for you right here."},
    -- fn409
        {"I won't go far. Just around here."},
    -- fn410
        {"Got it. I'll stay put."},
    -- fn411
        {"I'll keep watch here. Go on, don't worry."},
    -- fn412
        {"Right. Holding this spot."},
    },
    hold_idle = {
    -- fn413
        {"Still here, still waiting."},
    -- fn414
        {"Just pacing about. I won't wander off."},
    -- fn415
        {"I'll be here when you get back."},
    -- fn416
        {"I've got this spot memorised."},
    -- fn417
        {"Take your time. I'm in no hurry."},
    },

    -- ---------- 切换基地 ----------
    base_set = {
    -- fn418
        {"Good. From now on, this is home."},
    -- fn419
        {"I've marked this place in my mind."},
    -- fn420
        {"Let's make this the new home."},
    -- fn421
        {"I'll be waiting around here from now on."},
    -- fn422
        {"It's nice here. I like it."},
    },
    base_idle = {
    -- fn423
        {"Strolling near home. It's calming."},
    -- fn424
        {"So this is home now."},
    -- fn425
        {"I won't stray far from home."},
    -- fn426
        {"As long as there's food at home, we'll be fine."},
    -- fn427
        {"It's lovely to be somewhere familiar."},
    },

    -- ---------- 迟来的伙伴（世界已经过了 200 天）----------
    late_join = {
    -- fn428
        {"This world has come a long way already. I won't go putting up buildings."},
    -- fn429
        {"You're all settled in. I'll just tag along."},
    -- fn430
        {"I'll only pick grass and twigs. I'll leave the rest be."},
    -- fn431
        {"Everything here is yours. I won't help myself."},
    },
    wander = {
    -- fn432
        {"Nothing left to eat. I'll go have a look around."},
    -- fn433
        {"I'll take a wander. Might turn something up."},
    -- fn434
        {"It's a long road. I'll take it slow."},
    -- fn435
        {"I'll try a little further out."},
    },
    ask_pickup = {
    -- fn436
        {"May I pick up the things on the ground here?"},
    -- fn437
        {"These aren't grass or food. Shall I gather them up?"},
    -- fn438
        {"I see some materials. Want me to grab them? Just say yes."},
    -- fn439
        {"May I touch these? I'd hate to take something you need."},
    },
    pickup_allowed = {
    -- fn440
        {"Right, I'll gather things up for you then."},
    -- fn441
        {"Understood. I'll pick up materials from now on."},
    -- fn442
        {"Thank you. I'll keep them safe."},
    },

    -- ---------- 死亡与复活 ----------
    revived_thanks = {
    -- fn443
        {"Thank you for bringing me back... I thought I'd never see you again."},
    -- fn444
        {"Was it you who saved me? Thank you. I won't forget it."},
    -- fn445
        {"I'm back. Thank you for not giving up on me."},
    -- fn446
        {"I'll repay this. You'll see."},
    -- fn447
        {"I'm still standing, and that's thanks to you."},
    },
    revive_player = {
    -- fn448
        {"Don't be afraid. I'm here. Come back."},
    -- fn449
        {"Hold onto this. We're not finished yet."},
    -- fn450
        {"I'm sorry I was slow. Hurry back."},
    -- fn451
        {"This heart is for you. Get up."},
    -- fn452
        {"I'm not leaving you behind."},
    },
    revive_drop = {
    -- fn453
        {"I've set it down here. Touch it and you'll come back."},
    -- fn454
        {"This will bring you back. It's right by your feet."},
    -- fn455
        {"I've left what I can. The rest is up to you."},
    -- fn456
        {"See it? Go on, haunt it."},
    },

    -- ---------- 更换伙伴（告别与到来）----------
    -- 告别是说给在场所有人听的，所以不要在这里写任何具体名字。
    farewell = {
    -- fn457
        {"Everyone... I'm leaving. Thank you for walking this far with me."},
    -- fn458
        {"It's time to say goodbye. Don't see me off, I'll manage."},
    -- fn459
        {"I'll remember every single day here. Take care."},
    -- fn460
        {"Don't worry about me. Someone will be along soon to keep you company."},
    -- fn461
        {"Our paths split here, but I won't forget you."},
    },
    switch_arrive = {
    -- fn462
        {"Hello, everyone. I hope you'll have me."},
    -- fn463
        {"I heard someone was waiting for me?"},
    -- fn464
        {"I hope we can be good friends."},
    -- fn465
        {"Where is this? Is anyone there?"},
    },

    -- ---------- 冷热与光线 ----------
    cold = {
    -- fn466
        {"Getting cold. I'll put something warm on."},
    -- fn467
        {"My hands are going stiff. Time to bundle up."},
    -- fn468
        {"This weather really is bitter."},
    },
    hot = {
    -- fn469
        {"Far too hot. I'll change into something cooler."},
    -- fn470
        {"In this heat I need to cool down somehow."},
    -- fn471
        {"The sun is making me dizzy. Let me cover up."},
    },
    worn_out = {
    -- fn472
        {"This one is about to give out. I'll take it off and keep it."},
    -- fn473
        {"Any longer and it'll break for good. I'm putting it away."},
    -- fn474
        {"This is nearly worn through. Better save it."},
    },
    dark = {
    -- fn475
        {"It's gone dark. Let me light something."},
    -- fn476
        {"It's getting dark. Stay close to me."},
    -- fn477
        {"A bit of light makes all the difference."},
    },
}

M.replies = {
    -- fn478
    command_refuse_human = {"按理说，你这个级别的人类还没有权力命令我，但是为了满足你，我会听你的下一条命令。"},
    -- fn479
    describe_carry_statue = {"I'll carry the nearest statue and follow you with it."},
    -- fn480
    carry_statue_follow = {"The statue is in my arms. I'll follow you with it, and ride if I have a beefalo nearby."},
    -- fn481
    carry_statue_mount = {"Hold tight. Even a statue can go for a ride."},
    -- fn482
    carry_statue_none = {"There is no statue nearby that I can carry."},
    -- fn483
    describe_rockfruit = {"I'll mine the rock fruit with a tool, or pick nearby bushes if I have no tool."},
    -- fn484
    describe_bullkelp = {"OK,I'll put it in a fridge when I'm done."},
    -- fn485
    describe_dry_meat = {"I'll hang everything I can dry on the nearby drying racks."},
    -- fn486
    dry_meat_done = {"Everything that could be dried is hanging. The wind and sun can take it from here."},
    describe_monkeytail = {
    -- fn487
        "I'll pick nearby monkeytails and reeds, then scan again after five seconds.",
    -- fn488
        "Got it. I'll clear every pickable monkeytail and reed in this area.",
    -- fn489
        "I'll gather monkeytails and reeds in batches, checking nearby again after five seconds.",
    -- fn490
        "I'll search this area carefully and won't leave a nearby pickable plant behind.",
    },
    monkeytail_done = {
    -- fn491
        "The monkeytails and reeds are gathered. I brought the materials back.",
    -- fn492
        "I've checked the nearby monkeytails and reeds and brought everything back.",
    -- fn493
        "The gathered reeds are safe in my inventory and ready for you.",
    -- fn494
        "Gathering is finished. I kept all the reeds together for you.",
    },
    monkeytail_none = {
    -- fn495
        "There were no pickable monkeytails or reeds nearby.",
    -- fn496
        "I searched around, but this time there were no monkeytails or reeds to gather.",
    -- fn497
        "Nothing nearby was ready to pick, so I'm coming back.",
    },
    describe_banana = {
    -- fn498
        "I'll pick the banana bushes within twenty units, then give them to you or use a nearby icebox.",
    -- fn499
        "I'll gather the nearby bananas and bring them back safely.",
    -- fn500
        "Banana duty accepted. I'll harvest the ripe bushes close to us.",
    -- fn501
        "I'll search the nearby banana bushes and store the fruit when I'm done.",
    },
    banana_done = {
    -- fn502
        "The bananas are gathered and handed over or stored in a nearby icebox.",
    -- fn503
        "I've finished the nearby banana bushes. The fruit is safe with me or in the icebox.",
    -- fn504
        "The bananas are all sorted out and ready for you.",
    -- fn505
        "Banana gathering is complete. Nothing was left on the ground.",
    },
    banana_none = {
    -- fn506
        "There are no ripe banana bushes within twenty units.",
    -- fn507
        "I checked the area, but there are no bananas ready to pick right now.",
    -- fn508
        "The nearby banana bushes aren't ready yet, so I'm coming back.",
    },
    -- fn509
    pet_unknown = {"Which pet would you like? A Mothling, Vargling, or Eets?"},
    -- fn510
    pet_full = {"I already have a companion to care for."},
    -- fn511
    pet_materials = {"I'm missing some adoption supplies. Ask again once I'm carrying them."},
    -- fn512
    pet_no_den = {"I couldn't find a reachable Rock Den. I'll come back for now."},
    -- fn513
    pet_unavailable = {"I couldn't complete the adoption. I'm coming back."},
    -- fn514
    pet_prepare = {"I have the supplies. I'll visit the Rock Den and bring our new friend back."},
    -- fn515
    pet_done = {"All adopted! I'm coming back with our new friend."},
    -- fn516
    describe_explore = {"I'll explore somewhere new. Call me back when you need me."},
    -- fn517
    describe_fish = {"I'll go fishing and make another rod if I have the materials. Call me when I should stop."},
    -- fn518
    fish_no_rod = {"I can't find a freshwater rod or the supplies and science station to make one."},
    -- fn519
    fish_rod_done = {"My rod wore out and I can't make another right now. I'm coming back."},
    -- fn520
    fish_rod_missing = {"My fishing rod is missing. I'll come back for now."},
    -- fn521
    ghost_revive_nearby = {"I'll haunt a nearby resurrection item. Wait for me."},
    -- fn522
    ghost_revive_portal = {"I'll revive at the portal, then come back to you."},
    -- fn523
    ghost_revive_none = {"There's nothing I can haunt to revive within sixteen units."},
    -- fn524
    ghost_revive_no_portal = {"I couldn't find a Florid Postern or Celestial Portal in this world."},
    -- fn525
    ghost_revive_failed = {"I couldn't revive. I've tried the available options nearby."},
    -- fn526
    ghost_revive_return = {"I'm alive again. I'm coming back to you."},
    -- fn527
    ghost_revive_return_blocked = {"I'm alive, but the way back is blocked. Please come meet me."},
    -- fn528
    bookstation_prepare = {"I'll gather the materials and place a bookshelf in the centre of your turf tile."},
    -- fn529
    bookstation_make_room = {"You're standing where the bookshelf goes. Let's move you aside a little."},
    -- fn530
    bookstation_blocked = {"The bookshelf is blocked, or there isn't a safe place to step aside. Please choose a clear tile."},
    -- fn531
    bookstation_cannot_make = {"A bookshelf needs two living logs, four papyrus and a feather pencil. My inventory and nearby chests don't have enough."},
    -- fn532
    bookstation_done = {"The bookshelf is ready, right in the centre of the tile. A resting place for our books."},
    -- fn533
    book_last_stored = {"This book has one reading left. I'll keep it on the shelf to recover. Ask again within thirty seconds if it's urgent."},
    -- fn534
    book_last_keep = {"This book has one reading left and no available shelf nearby. I'll keep it. Ask again within thirty seconds and I'll read it."},
    -- fn535
    book_used_up = {"Finished. That was the book's final reading. We'll need another copy."},
    -- fn536
    book_read_failed = {"I couldn't finish reading. The book may have moved, or its effect cannot be used right now."},
    -- ---------- 聊天指令的固定回复 ----------
    -- fn537
    follow_ok = {"Okay, I'll come with you."},
    -- fn538
    follow_busy = {"I'm keeping another friend company just now."},
    -- fn539
    follow_unfamiliar = {"We don't know each other well enough yet."},
    -- fn540
    ride_ok = {"Okay, I'll ride after you."},
    -- fn541
    ride_stop_ok = {"Alright, I'll walk from here."},
    -- fn542
    ride_unavailable = {"I don't have a rideable beefalo right now. I'll walk."},
    -- fn543
    ride_not_following = {"Ask me to follow you first, then I can ride after you."},
    -- fn544
    affinity_work = {"Once we're past 50 affinity, I'd be glad to do that for you."},
    -- fn545
    affinity_items = {"You'll need 20 affinity before you can touch my things."},
    -- fn546
    affinity_name = {"Reach 80 affinity and you can give me a name."},
    -- fn547
    affinity_locked = {"That needs {1} affinity before I can do it."},
    -- fn548
    affinity_skin = {"I'll change outfits once we reach 40 affinity."},
    -- fn549
    name_invalid = {"Please pick a short name, with no line breaks or odd symbols."},
    -- fn550
    name_ok = {"I like it! Call me {1} from now on."},
    -- fn551
    special_no_book = {"I can't find that book."},
    -- fn552
    special_no_food = {"I couldn't find that meal in my inventory."},
    -- fn553
    special_cannot_make = {"I don't have the materials or station to make that."},
    -- fn554
    recipe_batch_done = {"I've made {1} portions. I can't start another pot with the remaining ingredients and available cookware."},
    -- fn555
    recipe_inventory_full = {"I'm out of room. I'll stop here and leave anything in the pot for you."},
    -- fn556
    special_device_place_failed = {"The cookware is ready, but I couldn't find a clear place nearby."},
    -- fn557
    special_recall = {"All right, I'll have Abigail rest for a while."},
    -- fn558
    special_read_ok = {"I'll find that book and read it."},
    -- fn559
    special_spice_ok = {"I'll season that meal."},
    -- fn560
    special_command_ok = {"All right, I'll prepare it."},
    -- fn561
    no_backpack = {"There's no backpack I can use nearby, and I won't make a new one."},
    -- fn562
    backpack_unreachable = {"I can't get to that backpack right now. Let's wait until it's safer."},
    carry_backpack_ask = {
    -- fn563
        "I've put the heavy load down. May I go back for my backpack?",
    -- fn564
        "My backpack is still where I picked up that load. Can I fetch it?",
    -- fn565
        "My hands are free now. Is it okay if I retrieve my backpack?",
    },
    carry_backpack_yes = {
    -- fn566
        "I'll fetch my backpack and come straight back to you.",
    -- fn567
        "All right, I'll be back once I have my bag.",
    -- fn568
        "I'll get my bag. I'll ride my beefalo if it's available.",
    },
    carry_backpack_done = {
    -- fn569
        "I've got my backpack. I'm back!",
    -- fn570
        "Bag recovered. Ready to follow you again.",
    -- fn571
        "My backpack is with me again. Let's keep going.",
    },
    carry_backpack_failed = {
    -- fn572
        "I can't retrieve my backpack right now. I'll follow you for now.",
    -- fn573
        "I couldn't finish that trip. I'll catch up with you first.",
    },
    -- fn574
    no_tool = {"I can't find a tool I can use, so I'll leave this for now."},
    -- fn575
    hoe_incomplete = {"I've tidied every hole I could. Some are blocked by crops or obstacles and I can't manage those. Could you help?"},

    -- ---------- 指令说明 ----------
    -- fn576
    describe_butterfly = {"I'll hunt the butterflies around you without straying too far."},
    -- fn577
    butterfly_none = {"There are no butterflies I can reach around you right now."},
    -- fn578
    butterfly_done = {"I've finished with the nearby butterflies. I won't chase the ones that flew away."},
    -- fn579
    describe_sit = {"I'll take the nearest free seat."},
    -- fn580
    sit_unavailable = {"There isn't an available seat nearby. I'll stand for now."},
    -- fn581
    sit_stop_ok = {"All right, I'm getting up. I'll stretch my legs for a while."},
    -- fn582
    describe_dig_grass = {"I'll get a shovel and dig up the grass tufts around you."},
    -- fn583
    describe_dig_sapling = {"I'll dig up the nearby saplings and collect them."},
    -- fn584
    describe_dig_stump = {"I'll clear the nearby stumps and leave the living trees alone."},
    -- fn585
    dig_full = {"My bags are full. I'll stop digging until there's room."},
    -- fn586
    dig_none = {"There are no matching targets I can dig up around you right now."},
    -- fn587
    dig_done = {"I've finished the reachable targets in this area."},
    -- fn588
    describe_hoe = {"Hoeing at noon, sweat dripping into the soil."},
    -- fn589
    describe_water = {"The little plants need plenty to drink!"},
    -- fn590
    describe_chop = {"Chop, chop... I do wish we could build a house out of it."},
    -- fn591
    describe_mine = {"Today I'm playing the miner. Heave-ho!"},
    -- fn592
    describe_grass = {"I'll gather some good things for you."},
    -- fn593
    describe_harvest = {"Let me bring the harvest in for you."},
    -- fn594
    describe_seeds = {"I'll collect seeds for you, all part of our big harvest plan."},
    -- fn595
    describe_tidy = {"I'll tidy this place up for you."},
    -- fn596
    describe_hold = {"I'll wait here for you, and help myself to a nearby icebox if I get hungry."},
    -- fn597
    describe_base = {"From now on, this is my home!"},
    -- fn598
    base_needs_follow = {"Ask me to follow you first, then I'll know where to move to."},
    -- fn599
    switch_needs_follow = {"Sorry, I don't want to leave yet."},
    -- 玩家说"带走吧/送你/不要了"：走的时候把身上的东西一起带走
    -- fn600
    farewell_gift_ok = {"Then I'll keep it all, and take it with me when I go."},
    -- fn601
    farewell_gift_cancel = {"Alright, I'll leave everything behind when I go."},
}

return M

