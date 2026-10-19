-- English dialogue: chat replies, text in ascending fn order, voice references.
-- One text per line; fn identifies the Chinese audio slot. M.lines: dialogue; M.replies: replies.
-- Preserve keys, variant order and {1} placeholders; keep new numbered text after the last fn.
-- This locale uses the native character voice and has no custom voice_order table.

local M = {lines = {}, replies = {}}

-- Chat replies (pending questions only; not commands)
M.combat_encouragement_words = {"you can do it", "you got this", "you've got this", "keep it up", "don't give up", "i believe in you", "come on", "well done"}
M.chat_replies = {
    permission = {yes = {"yes", "sure", "go ahead", "ok", "okay", "no problem"}},
    sugar = {
        yes = {"yes", "sure", "okay", "ok", "go ahead", "eat", "eat it", "no problem"},
        no = {"no", "no way", "dont", "don't", "do not", "do not eat", "dont eat", "don't eat", "refuse", "not now"},
    },
    rockfruit = {
        yes = {"crack", "crack them", "crack it", "yes", "go ahead", "okay", "ok", "continue"},
        no = {"no", "don't crack", "do not crack", "keep them", "store them", "not now"},
    },
}

-- Numbered text (fn1 to fn695)
M.lines.pet_feed = {
    {"Hungry, little one? Here, have a bite."}, -- fn1
    {"This little snack is for you. Take your time."}, -- fn2
    {"No need to circle me. I know you're hungry."}, -- fn3
    {"Have a bite, then let's walk some more."}, -- fn4
}
M.lines.pet_travel = {
    {"Supplies ready. I'm off to meet a little companion."}, -- fn5
    {"I wonder if it'll be happy to meet me."}, -- fn6
    {"We'll have another friend when I get back."}, -- fn7
}
M.lines.pet_adopt = {
    {"Come along. We'll travel together from now on."}, -- fn8
    {"I've brought you a treat. Come home with me."}, -- fn9
    {"I'll take care of you, little one."}, -- fn10
}
M.lines.explore = {
    {"I haven't been this way. Let's take a look."}, -- fn11
    {"I'm keeping track of the route. Call me when you need me."}, -- fn12
    {"I'll take care of myself, then keep exploring."}, -- fn13
    {"Let's see what's beyond these woods."}, -- fn14
}
M.lines.explore_mount = {
    {"With a beefalo along, we can explore a little farther."}, -- fn15
    {"Let's ride out somewhere we haven't been."}, -- fn16
    {"All taken care of. Back in the saddle to explore."}, -- fn17
}
M.lines.explore_dismount = {
    {"Let's find some clear ground. I need to get down for a moment."}, -- fn18
    {"I'll walk this stretch. I'm still exploring."}, -- fn19
    {"I'll get down to take care of something, then carry on."}, -- fn20
}
M.lines.fish_prepare = {
    {"First, a fishing rod. The fish won't wait forever."}, -- fn21
    {"I'll find a rod, or make one."}, -- fn22
    {"Once the supplies are ready, I'll head to a pond."}, -- fn23
}
M.lines.fish_search = {
    {"No suitable pond here. I'll keep looking."}, -- fn24
    {"I can't fish here for now. Let's try elsewhere."}, -- fn25
    {"Rod ready. Now I just need a good pond."}, -- fn26
}
M.lines.fish_replace = {
    {"The rod wore out. Let's see if I can make another with what I'm carrying."}, -- fn27
    {"I'll replace the rod, then get back to fishing."}, -- fn28
    {"Time for a fresh rod, if I have the supplies."}, -- fn29
}
M.lines.fish_cast = {
    {"This looks like a good place to cast."}, -- fn30
    {"A little patience. Let's see what bites."}, -- fn31
    {"Come on, fish. Take the bait."}, -- fn32
}
M.lines.fish_caught = {
    {"Another catch, safely packed."}, -- fn33
    {"This one will make a nice meal."}, -- fn34
    {"A good catch. Let's cast again."}, -- fn35
}
M.lines.fish_full = {
    {"My pockets are full. I'll leave the fish on the bank."}, -- fn36
    {"I'll leave this one here to pick up later."}, -- fn37
    {"More fish than pocket space. I'll leave it here."}, -- fn38
}
M.lines.butterfly_hunt = {
    {"A little closer. This one flies fast."}, -- fn39
    {"I'll keep my eye on this one."}, -- fn40
    {"I'll get close before I swing."}, -- fn41
    {"Stay close this time. No swinging at thin air."}, -- fn42
}
M.lines.butterfly_loot = {
    {"Got it. Let's pick up the food."}, -- fn43
    {"Even a little can help in a pinch."}, -- fn44
    {"I'll pick this up before deciding what's next."}, -- fn45
}
M.lines.ghost_help = {
    {"It's {1}. I've become a ghost. Could someone help revive me?"}, -- fn46
    {"{1} needs help! Could someone bring a Telltale Heart? My belongings are still where I fell."}, -- fn47
    {"It's {1}, floating around as a ghost. Could a friend spare a moment to revive me?"}, -- fn48
    {"{1} is waiting for rescue. Can someone bring me back? I'll thank you properly once I'm alive."}, -- fn49
    {"It's {1}. I could really use some help this time! Could someone come revive me?"}, -- fn50
}
M.lines.ghost_help_depart = {
    {"It's {1}. Carry on, everyone. I'll float to the portal to revive, then return for my belongings."}, -- fn51
    {"{1} is heading to the portal to revive. No need to rush over; I'll come back for my things."}, -- fn52
    {"It's {1}. Everyone seems busy. I'll revive at the portal and come back for my things."}, -- fn53
}
M.lines.skin_changed = {
    {"All changed! What do you think?"}, -- fn54
    {"This outfit suits me. Thanks for picking it out."}, -- fn55
    {"A new look lifts the spirits. I have a spring in my step!"}, -- fn56
    {"Let me turn around. Does everything look tidy?"}, -- fn57
    {"Looking this nice, I'd better be careful with the chores."}, -- fn58
    {"You have good taste. You can help me choose next time too."}, -- fn59
    {"Will our friends recognize me in this?"}, -- fn60
    {"All freshened up. Let's get going."}, -- fn61
    {"Do I look like an even more dependable companion now?"}, -- fn62
    {"You've saved me ages of deciding what to wear."}, -- fn63
}
M.lines.gather_hurt = {
    {"That hurt to gather. I'll try somewhere else for a while."}, -- fn64
    {"That resource bites back. I'll leave it alone for now."}, -- fn65
    {"That cost me some health. I'll remember to avoid it for now."}, -- fn66
}
M.lines.wormhole_follow = {
    {"Wait for me. I'll follow you through."}, -- fn67
    {"Go ahead. I'll be right behind you."}, -- fn68
    {"This shortcut is sticky, but it beats the long way."}, -- fn69
}
M.lines.rift_follow = {
    {"Wait for me. I can use this rift too, right?"}, -- fn70
    {"I'll follow before it closes."}, -- fn71
    {"Go ahead. I'll jump through right behind you."}, -- fn72
    {"Now that's an unusual shortcut."}, -- fn73
}
M.lines.sit_rest = {
    {"There's a chair here. I'll rest a moment; tell me when we're going."}, -- fn74
    {"It's quiet here. My legs could use a rest."}, -- fn75
    {"A perfectly good seat! No need to stand around."}, -- fn76
    {"I'll enjoy the view. When you go, I'll follow."}, -- fn77
}
M.lines.sit_together = {
    {"Taking a seat? I'll keep you company."}, -- fn78
    {"There's a free seat nearby. Let's rest our feet."}, -- fn79
    {"We've walked quite a way. Let's sit and chat."}, -- fn80
    {"Let's sit together. We can head out when you're rested."}, -- fn81
}
M.lines.book_read = {
    {"Let me find the page. Knowledge takes patience."}, -- fn82
    {"Listen closely. This is no ordinary storybook."}, -- fn83
    {"The answer in this book should come in handy."}, -- fn84
    {"I remember this passage, but it pays to check."}, -- fn85
}
M.lines.book_shelf_read = {
    {"The book is on the shelf. I'll open it and read here."}, -- fn86
    {"Found it. It can stay right on the shelf."}, -- fn87
    {"No need to carry it around. I can read it here."}, -- fn88
    {"I'll close the shelf when I'm done. Knowledge deserves good care."}, -- fn89
}
M.lines.book_ground_pickup = {
    {"The book is on the ground. I'll pick it up before reading."}, -- fn90
    {"I found a book on the ground. Let's keep it from getting damp."}, -- fn91
}
M.lines.book_store = {
    {"One reading left. This book needs some time on the shelf."}, -- fn92
    {"These pages are worn. Let's give them a rest."}, -- fn93
    {"With a shelf nearby, we can let this book recover."}, -- fn94
    {"These last pages need care. I'll put the book away."}, -- fn95
}
M.lines.rockfruit = {
    {"Leave the rock fruit to me. I'll mine the hard ones and pick the soft ones."}, -- fn96
    {"These fruits look like rocks, and they certainly have the temperament of rocks."}, -- fn97
    {"I'll gather the nearby rock fruit before it pretends to be innocent on the ground."}, -- fn98
}
M.lines.rockfruit_ask = {
    {"The rock fruit is gathered. Should I mine it open, or put it in the nearest chest?"}, -- fn99
    {"The hard ones are ready. Should I crack them open? Tell me within thirty seconds."}, -- fn100
    {"Should I crack the rock fruit? If you don't say, I'll call it a collection."}, -- fn101
}
M.lines.rockfruit_mine_answer = {
    {"All right, you said yes. I'll crack the rock fruit open."}, -- fn102
    {"Message received. Rock shell, meet your destiny."}, -- fn103
}
M.lines.rockfruit_store_answer = {
    {"All right, no cracking. I'll store them for later."}, -- fn104
    {"Fine. I won't argue with the rock fruit today. The chest can look after it."}, -- fn105
}
M.lines.bullkelp = {
    {"I'll gather bull kelp and try not to become kelp myself."}, -- fn106
    {"Bull kelp, don't hide. None of you are escaping today."}, -- fn107
    {"I'll put the kelp in the fridge when I'm done and keep it cool."}, -- fn108
}
M.lines.dry_meat = {
    {"I'll find the food a drying rack. Sunlight beats sweating in my bag."}, -- fn109
    {"Are the drying racks ready? I'll hang up everything that can be dried."}, -- fn110
    {"Today's menu is dried food. The chef is staying out of the drying process."}, -- fn111
}
M.lines.dry_meat_collect = {
    {"Finished drying? I'll bring this batch of flavor back."}, -- fn112
    {"The sun worked hard. I'll put the results in the fridge."}, -- fn113
    {"The drying rack handed in its homework. I'll collect it."}, -- fn114
}
M.lines.carry_statue = {
    {"This statue is a little heavy, but I can carry it."}, -- fn115
    {"Don't rush me. This stone and I are getting acquainted."}, -- fn116
    {"Carrying things is exercise. My arms have work today."}, -- fn117
}
M.lines.carry_statue_mount = {
    {"Carrying a statue on a beefalo is quite a transport upgrade."}, -- fn118
    {"Easy, beefalo. We have a stone passenger on board."}, -- fn119
    {"Don't worry. The statue is sitting steadier than I am."}, -- fn120
}
M.lines.ride_mount = {
    {"You're too far away. Riding will be quicker."}, -- fn121
    {"Come on, take me to them."}, -- fn122
    {"I'll borrow your legs for the journey."}, -- fn123
}
M.lines.ride_chase = {
    {"I'll ride after them. I'll catch up soon."}, -- fn124
    {"Don't go too far. I'll catch up."}, -- fn125
    {"With a mount, I won't have to worry about falling behind."}, -- fn126
}
M.lines.ride_dismount = {
    {"This is close enough. I'll walk from here."}, -- fn127
    {"Thank you for the ride."}, -- fn128
    {"Good work. We can walk from here."}, -- fn129
}
M.lines.follow = {
    {"Okay, I'm right behind you."}, -- fn130
    {"Let's go together. I'll be right here beside you."}, -- fn131
    {"You lead the way, I'll keep up."}, -- fn132
    {"Anywhere's fine, as long as we go together."}, -- fn133
    {"Mm. Don't worry about losing me."}, -- fn134
    {"Coming! Let's go."}, -- fn135
}
M.lines.idle = {
    {"It's peaceful here. Let's rest a bit."}, -- fn136
    {"Let's take today slowly. No rush."}, -- fn137
    {"It's good having somewhere to come back to."}, -- fn138
    {"I'll wander around a bit."}, -- fn139
    {"Every gust of wind brings something back to me."}, -- fn140
    {"That's done. Let's catch our breath."}, -- fn141
    {"I'm checking whether today's wind ruined my hair."}, -- fn142
    {"Nothing urgent. My shadow and I are taking a walk."}, -- fn143
    {"Don't mind me. I'm seriously recharging."}, -- fn144
    {"The view is nice. Even spacing out feels worthwhile."}, -- fn145
    {"I'm on standby and thinking about dinner."}, -- fn146
    {"We've worked hard today. Rest when we can."}, -- fn147
}
M.lines.activity_idle = {
    {"Can't you tell? I'm relaxing on standby and watching the wind."}, -- fn148
    {"Nothing urgent. I'm maintaining the peaceful atmosphere."}, -- fn149
    {"I'm resting. Resting is part of the survival plan."}, -- fn150
}
M.lines.activity_chop = {
    {"Can't you tell? I'm chopping a tree."}, -- fn151
    {"I'm gathering wood for the coming winter."}, -- fn152
    {"Didn't you ask me to chop? I'm nearly done."}, -- fn153
}
M.lines.activity_mine = {
    {"I'm negotiating with this rock. It hasn't surrendered yet."}, -- fn154
    {"I'm mining. Let's see if the ground has a surprise."}, -- fn155
    {"I'm collecting stone and ore for the base."}, -- fn156
}
M.lines.activity_dig = {
    {"I'm digging. The ground will look more organized soon."}, -- fn157
    {"I'm transplanting these plants into a better home."}, -- fn158
    {"With a shovel in hand, the grass and saplings can take turns."}, -- fn159
}
M.lines.activity_fish = {
    {"I'm fishing. The rod needs more patience than I do."}, -- fn160
    {"I'm waiting for a bite. Don't scare the pond."}, -- fn161
    {"I'm trying to bring some seafood home for dinner."}, -- fn162
}
M.lines.activity_explore = {
    {"I'm exploring to see what corners of the world remain unknown."}, -- fn163
    {"I'm scouting ahead. Don't worry, I remember the way back."}, -- fn164
    {"I'm out for a walk. I'll bring back anything useful."}, -- fn165
}
M.lines.activity_fight = {
    {"I'm fighting. Let me see this visitor out."}, -- fn166
    {"I'm protecting you, and myself while I'm at it."}, -- fn167
    {"I'm dealing with trouble. I'll be back when it's handled."}, -- fn168
}
M.lines.activity_feed = {
    {"I'm feeding the little one. Its stomach is honest."}, -- fn169
    {"I'm caring for my pet. Cute is not the only responsibility."}, -- fn170
    {"I'm getting it a bite to eat. Almost done."}, -- fn171
}
M.lines.activity_tidy = {
    {"I'm organizing supplies. The chests almost know me by name."}, -- fn172
    {"I'm putting away spare things before they wander off."}, -- fn173
    {"I'm tidying up. A base needs some order."}, -- fn174
}
M.lines.activity_cook = {
    {"I'm cooking. The pot won't stay empty today."}, -- fn175
    {"I'm turning ingredients into something more like dinner."}, -- fn176
    {"I'm preparing a meal. Remember to eat it while it's warm."}, -- fn177
}
M.lines.activity_eat = {
    {"I'm eating. An important survival meeting is in session."}, -- fn178
    {"I'm refueling. An empty stomach can't accomplish much."}, -- fn179
    {"I'm eating properly. Don't worry, I didn't take your portion."}, -- fn180
}
M.lines.activity_build = {
    {"I'm crafting. These materials will soon become something useful."}, -- fn181
    {"I'm building. A dependable base takes time."}, -- fn182
    {"I'm making something. You'll see when it's finished."}, -- fn183
}
M.lines.activity_follow = {
    {"I'm following you. Am I hiding too well?"}, -- fn184
    {"I'm walking with you and watching for useful things."}, -- fn185
    {"I'm on standby beside you. I go where you go."}, -- fn186
}
M.lines.activity_ride = {
    {"I'm riding. Four legs are certainly busier than two."}, -- fn187
    {"I'm riding to catch up. Don't run too fast."}, -- fn188
    {"I'm traveling with my beefalo. The mount has today's distance covered."}, -- fn189
}
M.lines.activity_sit = {
    {"I'm resting. The chair is doing reliable work today."}, -- fn190
    {"I'm sitting with you. My legs deserve some respect too."}, -- fn191
    {"I'm on standby in this chair. Call me when it's time to go."}, -- fn192
}
M.lines.work = {
    {"Leave this one to me."}, -- fn193
    {"Bit by bit. We'll get there."}, -- fn194
    {"I'll be careful with it."}, -- fn195
    {"Let's finish what's in front of us first."}, -- fn196
    {"A little work now, rest after."}, -- fn197
    {"I'm just glad I can help."}, -- fn198
}
M.lines.chop = {
    {"This wood should last us a while."}, -- fn199
    {"A bit more wood and the night won't worry me."}, -- fn200
    {"Careful, don't stand where it's going to fall."}, -- fn201
    {"Let's take the wood back. We'll find plenty of uses for it."}, -- fn202
    {"One swing at a time."}, -- fn203
    {"These trees have grown so tall."}, -- fn204
}
M.lines.mine = {
    {"There's good stuff hidden inside these rocks."}, -- fn205
    {"Mind your feet, these chips are sharp."}, -- fn206
    {"Let's put these ores somewhere safe."}, -- fn207
    {"A few more swings should do it."}, -- fn208
    {"We'll be needing these materials later."}, -- fn209
    {"Even the hardest rock cracks if you keep at it."}, -- fn210
}
M.lines.gather = {
    {"Let's take this one too."}, -- fn211
    {"Slow and steady, so we don't miss any."}, -- fn212
    {"A stock like this puts my mind at ease."}, -- fn213
    {"If it's useful and it's on our way, I'll grab it."}, -- fn214
    {"There's still a bit more to pick up around here."}, -- fn215
    {"A little more in the bag."}, -- fn216
}
M.lines.plant = {
    {"Grow up strong here, little one."}, -- fn217
    {"This place will be greener one day."}, -- fn218
    {"I saved a spot just for you."}, -- fn219
    {"Take your time growing. We'll wait."}, -- fn220
    {"Settle your roots in and you'll be fine."}, -- fn221
    {"This little patch is waking up."}, -- fn222
}
M.lines.fertilizer_search = {
    {"I'll look for fertilizer on the savanna."}, -- fn223
    {"I've checked this patch. Let's look a little farther."}, -- fn224
    {"The grass tufts need fertilizer. I'll look for some."}, -- fn225
}
M.lines.fertilizer_collect = {
    {"The grass tufts back home can use this."}, -- fn226
    {"I'll take these home before fertilizing."}, -- fn227
    {"A little more fertilizer for the garden."}, -- fn228
}
M.lines.fertilize = {
    {"Some nutrients to help you grow again."}, -- fn229
    {"Fertilized. Now the grass can recover."}, -- fn230
    {"That's another tuft taken care of."}, -- fn231
}
M.lines.build = {
    {"Now it's starting to feel like home."}, -- fn232
    {"That's one more done."}, -- fn233
    {"This should sit nicely right here."}, -- fn234
    {"A bit of preparation now saves trouble later."}, -- fn235
    {"None of those materials went to waste."}, -- fn236
    {"Bit by bit, we'll have everything we need."}, -- fn237
}
M.lines.store = {
    {"Same things together, much easier to find."}, -- fn238
    {"I'll put these away for later."}, -- fn239
    {"A quick tidy and the bag feels lighter."}, -- fn240
    {"Now we'll know exactly where to look."}, -- fn241
    {"Everything has a place of its own."}, -- fn242
    {"It never hurts to keep a little spare."}, -- fn243
}
M.lines.recipe_cook = {
    {"These ingredients make a better meal together."}, -- fn244
    {"There's a pot here. Time for a proper meal."}, -- fn245
    {"I'll save these ingredients. I have a recipe in mind."}, -- fn246
    {"Ingredients in. Now let the heat do its work."}, -- fn247
    {"There's enough in the fridge for a cooked meal today."}, -- fn248
}
M.lines.recipe_clear = {
    {"There are leftover ingredients in the pot. I'll put them away first."}, -- fn249
    {"These are still useful. I'll find somewhere suitable to store them."}, -- fn250
    {"I'll clear the pot, then start the dish you requested."}, -- fn251
}
M.lines.recipe_ready = {
    {"Dinner's ready. That smells good."}, -- fn252
    {"I'll keep this meal for when I'm hungry."}, -- fn253
    {"Worth the effort. A fresh meal is ready."}, -- fn254
    {"All done. I'll take it along."}, -- fn255
}
M.lines.cook = {
    {"Something hot always sits better."}, -- fn256
    {"Easy does it, mustn't burn it."}, -- fn257
    {"Just a little longer."}, -- fn258
    {"Let me get this one ready first."}, -- fn259
    {"I'd better watch the heat closely."}, -- fn260
    {"A proper meal would be so nice."}, -- fn261
}
M.lines.eat = {
    {"A bite first, then back to it."}, -- fn262
    {"It's easier to keep going on a full stomach."}, -- fn263
    {"This meal came just in time."}, -- fn264
    {"I mustn't get so busy that I forget to eat."}, -- fn265
    {"No need to rush a meal."}, -- fn266
    {"That's better. Now I can carry on."}, -- fn267
}
M.lines.fed = {
    {"Thank you for saving a share for me."}, -- fn268
    {"Got it! Don't let yourself go hungry either."}, -- fn269
    {"It makes me happy, you looking after me like this."}, -- fn270
    {"Thank you. That bite really warmed me up."}, -- fn271
    {"It's lovely, being thought of."}, -- fn272
    {"I've eaten. Now you take care of yourself too."}, -- fn273
    {"Thank you for sharing a bite with me."}, -- fn274
    {"I'll treasure the thought."}, -- fn275
}
M.lines.fed_careful = {
    {"Thank you, though this one needs eating carefully."}, -- fn276
    {"Down it went. I'll take it easy for a bit."}, -- fn277
    {"That had a rather... unusual taste."}, -- fn278
    {"Don't worry, I'll keep an eye on how I feel."}, -- fn279
    {"Let's find something better suited next time."}, -- fn280
    {"I know you meant well, but let's be a bit choosier."}, -- fn281
}
M.lines.gift = {
    {"For me? Thank you, I'll put it to good use."}, -- fn282
    {"With this along, the road feels safer."}, -- fn283
    {"Thank you for getting this ready for me."}, -- fn284
    {"It's safely stowed. Don't worry."}, -- fn285
    {"You're looking after me again. Thank you."}, -- fn286
    {"I'll take good care of this."}, -- fn287
    {"Thank you. It'll be ready when I need it."}, -- fn288
    {"Do keep some gear for yourself as well."}, -- fn289
}
M.lines.feed_player = {
    {"Eat something first. Don't go hungry."}, -- fn290
    {"Take your time. I'll stay right here with you."}, -- fn291
    {"You look hungry. Get your strength back first."}, -- fn292
    {"This is for you. We've still got a long way to go."}, -- fn293
    {"Eat your fill first, then back to work, all right?"}, -- fn294
    {"Don't just push on. Look after yourself too."}, -- fn295
    {"I've got some to spare. Here, take it."}, -- fn296
    {"I hope this makes you feel a bit better."}, -- fn297
}
M.lines.beefalo_feed = {
    {"Here, have a bite. Take it slow."}, -- fn298
    {"Easy now. You need a full belly to carry us."}, -- fn299
    {"Twigs and grass for you. I will win you over today."}, -- fn300
    {"Be a little more obedient. I saved you something tasty."}, -- fn301
    {"Come on, fill your belly until you are comfortable."}, -- fn302
    {"This beefalo has quite the temper. We will train patiently."}, -- fn303
    {"No headbutting! I brought dinner."}, -- fn304
    {"One bite at a time. We will get to know each other."}, -- fn305
    {"Have a rest after eating. The road can wait."}, -- fn306
    {"Eat up, and please do not throw me off next time."}, -- fn307
}
M.lines.beefalo_cook = {
    {"I am cooking beefalo feed for our ride."}, -- fn308
    {"There are enough twigs. Time to make the beefalo's favorite."}, -- fn309
    {"A well cared for beefalo makes the road easier."}, -- fn310
}
M.lines.player_takes_food = {
    {"Hungry? You could have asked before taking my rations."}, -- fn311
    {"Having trouble finding dinner? I have some to share."}, -- fn312
    {"Go on, take it. Do not let yourself go hungry."}, -- fn313
    {"So you had your eye on my dinner too."}, -- fn314
    {"Eat slowly. I will not fight you for it."}, -- fn315
    {"Tell me next time you are hungry. We can eat together."}, -- fn316
}
M.lines.player_takes_sack = {
    {"Taking my lunchbox too? You must be really hungry."}, -- fn317
    {"I still need that lunchbox. Do not go selling it."}, -- fn318
    {"What are you doing with my sack? Do you not have one?"}, -- fn319
    {"You can borrow the lunchbox, but do not waste the food inside."}, -- fn320
    {"My lunch is going with you. Dinner is on you tonight."}, -- fn321
    {"With you taking the lunchbox, where will I put my meals?"}, -- fn322
}
M.lines.beefalo_cooked = {
    {"The beefalo feed is ready. I will save it for our beefalo."}, -- fn323
    {"This pot is not our dinner!"}, -- fn324
    {"Beefalo rations packed for next time."}, -- fn325
}
M.lines.hurt = {
    {"That stung... I'll be more careful."}, -- fn326
    {"I should get away from here."}, -- fn327
    {"I can still hold on."}, -- fn328
    {"Please, not again."}, -- fn329
    {"Just need a breath. I can still move."}, -- fn330
    {"I'll have to be more careful now."}, -- fn331
}
M.lines.meal_open = {
    {"Let me check the food I brought."}, -- fn332
    {"I'll open my sack and have a bite."}, -- fn333
    {"My food is right here."}, -- fn334
    {"I packed a meal. Time to get some strength back."}, -- fn335
}
M.lines.meal_take = {
    {"I'll take something to eat from here."}, -- fn336
    {"I'll eat what I need and return the rest."}, -- fn337
    {"There's food here. Just what I need."}, -- fn338
    {"I'll have a bite and leave the rest here."}, -- fn339
}
M.lines.meal_return = {
    {"The rest goes back where it belongs."}, -- fn340
    {"That was enough. I'll put the rest away."}, -- fn341
    {"I can return the food I kept for later now."}, -- fn342
    {"I'll leave the uneaten food here."}, -- fn343
}
M.lines.player_attack = {
    {"Why are you attacking me? Stop. We can talk."}, -- fn344
    {"Please stop hitting me. I do not want to fight you."}, -- fn345
    {"I came to help, not to be beaten."}, -- fn346
    {"If you keep this up, I will have to defend myself."}, -- fn347
}
M.lines.ghost_return_question = {
    {"I will stay here for now. May I go back for the things we need?"}, -- fn348
    {"If you agree, I can go back and bring the things here."}, -- fn349
    {"May I fetch some supplies and come back to you?"}, -- fn350
}
M.lines.fight = {
    {"Careful! I've got your back."}, -- fn351
    {"Don't panic. We'll wait for the right moment."}, -- fn352
    {"I won't let you face this alone."}, -- fn353
    {"Keep your distance. Don't get hurt."}, -- fn354
    {"No time to run, we'll take it on together."}, -- fn355
    {"I'm right here. Don't be afraid."}, -- fn356
    {"Watch the opening. Don't let it breathe."}, -- fn357
    {"I'll keep it busy. Find an opening."}, -- fn358
    {"Stay steady. We take it together."}, -- fn359
    {"One step back. Let it swing first."}, -- fn360
    {"I can still fight. Keep going!"}, -- fn361
}
M.lines.fight_boss = {
    {"Even something that big can be beaten. Stay with me!"}, -- fn362
    {"A giant is here. Don't stand in front of it!"}, -- fn363
    {"I'll help hold it off. Take the opening!"}, -- fn364
    {"Watch its movement. Don't get caught in the area attack."}, -- fn365
    {"This is a big fight, but we're not alone."}, -- fn366
    {"Watch the opening. Don't let it breathe."}, -- fn367
    {"Break its rhythm first, then strike hard."}, -- fn368
    {"It's preparing something big. Spread out!"}, -- fn369
    {"Don't stand under it. An area attack is coming."}, -- fn370
}
M.lines.flee = {
    {"It's not safe here. Let's go."}, -- fn371
    {"Getting out alive matters more than anything."}, -- fn372
    {"Let's take another route."}, -- fn373
    {"Don't push it. Back off a little."}, -- fn374
    {"Let's get clear first, then think."}, -- fn375
    {"Stay close. We're leaving."}, -- fn376
}
M.lines.greeting = {
    {"hello."}, -- fn377
    {"it's good to see you."}, -- fn378
    {"how has your day been?"}, -- fn379
    {"take care out there."}, -- fn380
    {"rest a bit when you get tired."}, -- fn381
    {"I hope today treats you kindly."}, -- fn382
}
M.lines.care_health = {
    {"are you all right?"}, -- fn383
    {"you look hurt. Take a moment."}, -- fn384
    {"don't push yourself. I'll rest here with you."}, -- fn385
    {"look after yourself first, all right? I'm worried about you."}, -- fn386
}
M.lines.care_hunger = {
    {"make sure you eat plenty!"}, -- fn387
    {"getting hungry? Let's go find you something."}, -- fn388
    {"you've been at it a while. Fancy a bite?"}, -- fn389
    {"don't go hungry. I'll help you find some food."}, -- fn390
}
M.lines.care_sanity = {
    {"you really need some proper rest!"}, -- fn391
    {"feeling worn out? Let's slow down."}, -- fn392
    {"don't wind yourself so tight. Stop and rest a while."}, -- fn393
    {"I'm right here with you. Rest easy."}, -- fn394
}
M.lines.gift_sack = {
    {"Thank you for the sack. My meals will keep well now."}, -- fn395
    {"Now I have somewhere to keep my meals. Thank you."}, -- fn396
    {"I'll put my meals inside and take good care of it."}, -- fn397
}
M.lines.gift_food = {
    {"Am I holding this food for you? I'll keep it safe."}, -- fn398
    {"Thank you. I'll carry it for you."}, -- fn399
    {"Food in my bag puts my mind at ease."}, -- fn400
    {"I'll take these rations, then."}, -- fn401
    {"You're always making sure I'm fed."}, -- fn402
}
M.lines.gift_food_settled = {
    {"This food has been with me all this time. Thank you for thinking of me."}, -- fn403
    {"I've been keeping the rations you gave me."}, -- fn404
    {"It really does make me happy, being shared with."}, -- fn405
    {"I won't forget this kindness."}, -- fn406
    {"Thank you. I won't go hungry now."}, -- fn407
}
M.lines.hold_position = {
    {"Okay, I'll wait for you right here."}, -- fn408
    {"I won't go far. Just around here."}, -- fn409
    {"Got it. I'll stay put."}, -- fn410
    {"I'll keep watch here. Go on, don't worry."}, -- fn411
    {"Right. Holding this spot."}, -- fn412
}
M.lines.hold_idle = {
    {"Still here, still waiting."}, -- fn413
    {"Just pacing about. I won't wander off."}, -- fn414
    {"I'll be here when you get back."}, -- fn415
    {"I've got this spot memorised."}, -- fn416
    {"Take your time. I'm in no hurry."}, -- fn417
}
M.lines.base_set = {
    {"Good. From now on, this is home."}, -- fn418
    {"I've marked this place in my mind."}, -- fn419
    {"Let's make this the new home."}, -- fn420
    {"I'll be waiting around here from now on."}, -- fn421
    {"It's nice here. I like it."}, -- fn422
}
M.lines.base_idle = {
    {"Strolling near home. It's calming."}, -- fn423
    {"So this is home now."}, -- fn424
    {"I won't stray far from home."}, -- fn425
    {"As long as there's food at home, we'll be fine."}, -- fn426
    {"It's lovely to be somewhere familiar."}, -- fn427
}
M.lines.late_join = {
    {"This world has come a long way already. I won't go putting up buildings."}, -- fn428
    {"You're all settled in. I'll just tag along."}, -- fn429
    {"I'll only pick grass and twigs. I'll leave the rest be."}, -- fn430
    {"Everything here is yours. I won't help myself."}, -- fn431
}
M.lines.wander = {
    {"Nothing left to eat. I'll go have a look around."}, -- fn432
    {"I'll take a wander. Might turn something up."}, -- fn433
    {"It's a long road. I'll take it slow."}, -- fn434
    {"I'll try a little further out."}, -- fn435
}
M.lines.ask_pickup = {
    {"May I pick up the things on the ground here?"}, -- fn436
    {"These aren't grass or food. Shall I gather them up?"}, -- fn437
    {"I see some materials. Want me to grab them? Just say yes."}, -- fn438
    {"May I touch these? I'd hate to take something you need."}, -- fn439
}
M.lines.pickup_allowed = {
    {"Right, I'll gather things up for you then."}, -- fn440
    {"Understood. I'll pick up materials from now on."}, -- fn441
    {"Thank you. I'll keep them safe."}, -- fn442
}
M.lines.revived_thanks = {
    {"Thank you for bringing me back... I thought I'd never see you again."}, -- fn443
    {"Was it you who saved me? Thank you. I won't forget it."}, -- fn444
    {"I'm back. Thank you for not giving up on me."}, -- fn445
    {"I'll repay this. You'll see."}, -- fn446
    {"I'm still standing, and that's thanks to you."}, -- fn447
}
M.lines.revive_player = {
    {"Don't be afraid. I'm here. Come back."}, -- fn448
    {"Hold onto this. We're not finished yet."}, -- fn449
    {"I'm sorry I was slow. Hurry back."}, -- fn450
    {"This heart is for you. Get up."}, -- fn451
    {"I'm not leaving you behind."}, -- fn452
}
M.lines.revive_drop = {
    {"I've set it down here. Touch it and you'll come back."}, -- fn453
    {"This will bring you back. It's right by your feet."}, -- fn454
    {"I've left what I can. The rest is up to you."}, -- fn455
    {"See it? Go on, haunt it."}, -- fn456
}
M.lines.farewell = {
    {"Everyone... I'm leaving. Thank you for walking this far with me."}, -- fn457
    {"It's time to say goodbye. Don't see me off, I'll manage."}, -- fn458
    {"I'll remember every single day here. Take care."}, -- fn459
    {"Don't worry about me. Someone will be along soon to keep you company."}, -- fn460
    {"Our paths split here, but I won't forget you."}, -- fn461
}
M.lines.switch_arrive = {
    {"Hello, everyone. I hope you'll have me."}, -- fn462
    {"I heard someone was waiting for me?"}, -- fn463
    {"I hope we can be good friends."}, -- fn464
    {"Where is this? Is anyone there?"}, -- fn465
}
M.lines.cold = {
    {"Getting cold. I'll put something warm on."}, -- fn466
    {"My hands are going stiff. Time to bundle up."}, -- fn467
    {"This weather really is bitter."}, -- fn468
}
M.lines.hot = {
    {"Far too hot. I'll change into something cooler."}, -- fn469
    {"In this heat I need to cool down somehow."}, -- fn470
    {"The sun is making me dizzy. Let me cover up."}, -- fn471
}
M.lines.worn_out = {
    {"This one is about to give out. I'll take it off and keep it."}, -- fn472
    {"Any longer and it'll break for good. I'm putting it away."}, -- fn473
    {"This is nearly worn through. Better save it."}, -- fn474
}
M.lines.dark = {
    {"It's gone dark. Let me light something."}, -- fn475
    {"It's getting dark. Stay close to me."}, -- fn476
    {"A bit of light makes all the difference."}, -- fn477
}
M.replies.command_refuse_human = {"按理说，你这个级别的人类还没有权力命令我，但是为了满足你，我会听你的下一条命令。"} -- fn478
M.replies.describe_carry_statue = {"I'll carry the nearest statue and follow you with it."} -- fn479
M.replies.carry_statue_follow = {"The statue is in my arms. I'll follow you with it, and ride if I have a beefalo nearby."} -- fn480
M.replies.carry_statue_mount = {"Hold tight. Even a statue can go for a ride."} -- fn481
M.replies.carry_statue_none = {"There is no statue nearby that I can carry."} -- fn482
M.replies.describe_rockfruit = {"I'll mine the rock fruit with a tool, or pick nearby bushes if I have no tool."} -- fn483
M.replies.describe_bullkelp = {"OK,I'll put it in a fridge when I'm done."} -- fn484
M.replies.describe_dry_meat = {"I'll hang everything I can dry on the nearby drying racks."} -- fn485
M.replies.dry_meat_done = {"Everything that could be dried is hanging. The wind and sun can take it from here."} -- fn486
M.replies.describe_monkeytail = {
    "I'll pick nearby monkeytails and reeds, then scan again after five seconds.", -- fn487
    "Got it. I'll clear every pickable monkeytail and reed in this area.", -- fn488
    "I'll gather monkeytails and reeds in batches, checking nearby again after five seconds.", -- fn489
    "I'll search this area carefully and won't leave a nearby pickable plant behind.", -- fn490
}
M.replies.monkeytail_done = {
    "The monkeytails and reeds are gathered. I brought the materials back.", -- fn491
    "I've checked the nearby monkeytails and reeds and brought everything back.", -- fn492
    "The gathered reeds are safe in my inventory and ready for you.", -- fn493
    "Gathering is finished. I kept all the reeds together for you.", -- fn494
}
M.replies.monkeytail_none = {
    "There were no pickable monkeytails or reeds nearby.", -- fn495
    "I searched around, but this time there were no monkeytails or reeds to gather.", -- fn496
    "Nothing nearby was ready to pick, so I'm coming back.", -- fn497
}
M.replies.describe_banana = {
    "I'll pick the banana bushes within twenty units, then give them to you or use a nearby icebox.", -- fn498
    "I'll gather the nearby bananas and bring them back safely.", -- fn499
    "Banana duty accepted. I'll harvest the ripe bushes close to us.", -- fn500
    "I'll search the nearby banana bushes and store the fruit when I'm done.", -- fn501
}
M.replies.banana_done = {
    "The bananas are gathered and handed over or stored in a nearby icebox.", -- fn502
    "I've finished the nearby banana bushes. The fruit is safe with me or in the icebox.", -- fn503
    "The bananas are all sorted out and ready for you.", -- fn504
    "Banana gathering is complete. Nothing was left on the ground.", -- fn505
}
M.replies.banana_none = {
    "There are no ripe banana bushes within twenty units.", -- fn506
    "I checked the area, but there are no bananas ready to pick right now.", -- fn507
    "The nearby banana bushes aren't ready yet, so I'm coming back.", -- fn508
}
M.replies.pet_unknown = {"Which pet would you like? A Mothling, Vargling, or Eets?"} -- fn509
M.replies.pet_full = {"I already have a companion to care for."} -- fn510
M.replies.pet_materials = {"I'm missing some adoption supplies. Ask again once I'm carrying them."} -- fn511
M.replies.pet_no_den = {"I couldn't find a reachable Rock Den. I'll come back for now."} -- fn512
M.replies.pet_unavailable = {"I couldn't complete the adoption. I'm coming back."} -- fn513
M.replies.pet_prepare = {"I have the supplies. I'll visit the Rock Den and bring our new friend back."} -- fn514
M.replies.pet_done = {"All adopted! I'm coming back with our new friend."} -- fn515
M.replies.describe_explore = {"I'll explore somewhere new. Call me back when you need me."} -- fn516
M.replies.describe_fish = {"I'll go fishing and make another rod if I have the materials. Call me when I should stop."} -- fn517
M.replies.fish_no_rod = {"I can't find a freshwater rod or the supplies and science station to make one."} -- fn518
M.replies.fish_rod_done = {"My rod wore out and I can't make another right now. I'm coming back."} -- fn519
M.replies.fish_rod_missing = {"My fishing rod is missing. I'll come back for now."} -- fn520
M.replies.ghost_revive_nearby = {"I'll haunt a nearby resurrection item. Wait for me."} -- fn521
M.replies.ghost_revive_portal = {"I'll revive at the portal, then come back to you."} -- fn522
M.replies.ghost_revive_none = {"There's nothing I can haunt to revive within sixteen units."} -- fn523
M.replies.ghost_revive_no_portal = {"I couldn't find a Florid Postern or Celestial Portal in this world."} -- fn524
M.replies.ghost_revive_failed = {"I couldn't revive. I've tried the available options nearby."} -- fn525
M.replies.ghost_revive_return = {"I'm alive again. I'm coming back to you."} -- fn526
M.replies.ghost_revive_return_blocked = {"I'm alive, but the way back is blocked. Please come meet me."} -- fn527
M.replies.bookstation_prepare = {"I'll gather the materials and place a bookshelf in the centre of your turf tile."} -- fn528
M.replies.bookstation_make_room = {"You're standing where the bookshelf goes. Let's move you aside a little."} -- fn529
M.replies.bookstation_blocked = {"The bookshelf is blocked, or there isn't a safe place to step aside. Please choose a clear tile."} -- fn530
M.replies.bookstation_cannot_make = {"A bookshelf needs two living logs, four papyrus and a feather pencil. My inventory and nearby chests don't have enough."} -- fn531
M.replies.bookstation_done = {"The bookshelf is ready, right in the centre of the tile. A resting place for our books."} -- fn532
M.replies.book_last_stored = {"This book has one reading left. I'll keep it on the shelf to recover. Ask again within thirty seconds if it's urgent."} -- fn533
M.replies.book_last_keep = {"This book has one reading left and no available shelf nearby. I'll keep it. Ask again within thirty seconds and I'll read it."} -- fn534
M.replies.book_used_up = {"Finished. That was the book's final reading. We'll need another copy."} -- fn535
M.replies.book_read_failed = {"I couldn't finish reading. The book may have moved, or its effect cannot be used right now."} -- fn536
M.replies.follow_ok = {"Okay, I'll come with you."} -- fn537
M.replies.follow_busy = {"I'm keeping another friend company just now."} -- fn538
M.replies.follow_unfamiliar = {"We don't know each other well enough yet."} -- fn539
M.replies.ride_ok = {"Okay, I'll ride after you."} -- fn540
M.replies.ride_stop_ok = {"Alright, I'll walk from here."} -- fn541
M.replies.ride_unavailable = {"I don't have a rideable beefalo right now. I'll walk."} -- fn542
M.replies.ride_not_following = {"Ask me to follow you first, then I can ride after you."} -- fn543
M.replies.affinity_work = {"Once we're past 50 affinity, I'd be glad to do that for you."} -- fn544
M.replies.affinity_items = {"You'll need 20 affinity before you can touch my things."} -- fn545
M.replies.affinity_name = {"Reach 80 affinity and you can give me a name."} -- fn546
M.replies.affinity_locked = {"That needs {1} affinity before I can do it."} -- fn547
M.replies.affinity_skin = {"I'll change outfits once we reach 40 affinity."} -- fn548
M.replies.name_invalid = {"Please pick a short name, with no line breaks or odd symbols."} -- fn549
M.replies.name_ok = {"I like it! Call me {1} from now on."} -- fn550
M.replies.special_no_book = {"I can't find that book."} -- fn551
M.replies.special_no_food = {"I couldn't find that meal in my inventory."} -- fn552
M.replies.special_cannot_make = {"I don't have the materials or station to make that."} -- fn553
M.replies.recipe_batch_done = {"I've made {1} portions. I can't start another pot with the remaining ingredients and available cookware."} -- fn554
M.replies.recipe_inventory_full = {"I'm out of room. I'll stop here and leave anything in the pot for you."} -- fn555
M.replies.special_device_place_failed = {"The cookware is ready, but I couldn't find a clear place nearby."} -- fn556
M.replies.special_recall = {"All right, I'll have Abigail rest for a while."} -- fn557
M.replies.special_read_ok = {"I'll find that book and read it."} -- fn558
M.replies.special_spice_ok = {"I'll season that meal."} -- fn559
M.replies.special_command_ok = {"All right, I'll prepare it."} -- fn560
M.replies.no_backpack = {"There's no backpack I can use nearby, and I won't make a new one."} -- fn561
M.replies.backpack_unreachable = {"I can't get to that backpack right now. Let's wait until it's safer."} -- fn562
M.replies.carry_backpack_ask = {
    "I've put the heavy load down. May I go back for my backpack?", -- fn563
    "My backpack is still where I picked up that load. Can I fetch it?", -- fn564
    "My hands are free now. Is it okay if I retrieve my backpack?", -- fn565
}
M.replies.carry_backpack_yes = {
    "I'll fetch my backpack and come straight back to you.", -- fn566
    "All right, I'll be back once I have my bag.", -- fn567
    "I'll get my bag. I'll ride my beefalo if it's available.", -- fn568
}
M.replies.carry_backpack_done = {
    "I've got my backpack. I'm back!", -- fn569
    "Bag recovered. Ready to follow you again.", -- fn570
    "My backpack is with me again. Let's keep going.", -- fn571
}
M.replies.carry_backpack_failed = {
    "I can't retrieve my backpack right now. I'll follow you for now.", -- fn572
    "I couldn't finish that trip. I'll catch up with you first.", -- fn573
}
M.replies.no_tool = {"I can't find a tool I can use, so I'll leave this for now."} -- fn574
M.replies.hoe_incomplete = {"I've tidied every hole I could. Some are blocked by crops or obstacles and I can't manage those. Could you help?"} -- fn575
M.replies.describe_butterfly = {"I'll hunt the butterflies around you without straying too far."} -- fn576
M.replies.butterfly_none = {"There are no butterflies I can reach around you right now."} -- fn577
M.replies.butterfly_done = {"I've finished with the nearby butterflies. I won't chase the ones that flew away."} -- fn578
M.replies.describe_sit = {"I'll take the nearest free seat."} -- fn579
M.replies.sit_unavailable = {"There isn't an available seat nearby. I'll stand for now."} -- fn580
M.replies.sit_stop_ok = {"All right, I'm getting up. I'll stretch my legs for a while."} -- fn581
M.replies.describe_dig_grass = {"I'll get a shovel and dig up the grass tufts around you."} -- fn582
M.replies.describe_dig_sapling = {"I'll dig up the nearby saplings and collect them."} -- fn583
M.replies.describe_dig_stump = {"I'll clear the nearby stumps and leave the living trees alone."} -- fn584
M.replies.dig_full = {"My bags are full. I'll stop digging until there's room."} -- fn585
M.replies.dig_none = {"There are no matching targets I can dig up around you right now."} -- fn586
M.replies.dig_done = {"I've finished the reachable targets in this area."} -- fn587
M.replies.describe_hoe = {"Hoeing at noon, sweat dripping into the soil."} -- fn588
M.replies.describe_water = {"The little plants need plenty to drink!"} -- fn589
M.replies.describe_chop = {"Chop, chop... I do wish we could build a house out of it."} -- fn590
M.replies.describe_mine = {"Today I'm playing the miner. Heave-ho!"} -- fn591
M.replies.describe_grass = {"I'll gather some good things for you."} -- fn592
M.replies.describe_harvest = {"Let me bring the harvest in for you."} -- fn593
M.replies.describe_seeds = {"I'll collect seeds for you, all part of our big harvest plan."} -- fn594
M.replies.describe_tidy = {"I'll tidy this place up for you."} -- fn595
M.replies.describe_hold = {"I'll wait here for you, and help myself to a nearby icebox if I get hungry."} -- fn596
M.replies.describe_base = {"From now on, this is my home!"} -- fn597
M.replies.base_needs_follow = {"Ask me to follow you first, then I'll know where to move to."} -- fn598
M.replies.switch_needs_follow = {"Sorry, I don't want to leave yet."} -- fn599
M.replies.farewell_gift_ok = {"Then I'll keep it all, and take it with me when I go."} -- fn600
M.replies.farewell_gift_cancel = {"Alright, I'll leave everything behind when I go."} -- fn601
M.replies.tower_start = {
    "I will touch the Lazy Deserter. Give me a moment.", -- fn602
    "Let us wake the magic in that tower.", -- fn603
    "All right, I will activate the tower.", -- fn604
}
M.replies.tower_missing = {
    "There is no usable Lazy Deserter nearby.", -- fn605
    "The tower cannot be used right now.", -- fn606
    "I could not find an available tower.", -- fn607
}
M.replies.tower_channel = {
    "The tower is awake. I will stay here.", -- fn608
    "I am channeling the tower now.", -- fn609
    "It answered. Come through when you need to.", -- fn610
}
M.replies.describe_squeeze_heart = {
    "All right, I will squeeze the Twintailed Heart.", -- fn611
    "Let me press this heart and see where it leads.", -- fn612
    "I will call to the souls inside this heart.", -- fn613
}
M.replies.heart_unavailable = {
    "I have no heart that I can squeeze right now.", -- fn614
    "The Twintailed Heart is not ready. Check its link first.", -- fn615
    "I could not find a usable Twintailed Heart.", -- fn616
}
M.replies.heart_squeezed = {
    "The heart has answered my call.", -- fn617
    "The souls will show me the way.", -- fn618
    "I squeezed it. I hope someone is waiting on the other side.", -- fn619
}
M.replies.watch_heal = {
    "Give me a moment. I can turn it back.", -- fn620
    "The Ageless Watch can still buy me some time.", -- fn621
    "The hands are turning back. I feel better already.", -- fn622
}
M.replies.cooling_seek = {
    "It is too hot. I need somewhere cool for a moment.", -- fn623
    "It is cooler over there. I will return once I cool down.", -- fn624
    "Let me cool off before I end up roasted.", -- fn625
}
M.replies.body_exchanged = {
    "All swapped. Let us take care of what we are carrying.", -- fn626
    "You can borrow this body. Remember to come back.", -- fn627
    "Same name, different body.", -- fn628
}
M.replies.activity_wanda_fuel = {
    "This Nightmare Fuel will keep the Alarming Clock ticking.", -- fn629
    "I will gather this. Time needs fuel, too.", -- fn630
    "Better keep it, so my clock will not stop when I need it.", -- fn631
}
M.replies.activity_wanda_refuel = {
    "The Alarming Clock can ring again.", -- fn632
    "A little nightmare buys a little more time.", -- fn633
    "That should keep it from stopping.", -- fn634
}
M.replies.activity_wortox_heal = {
    "Let this soul soothe your wounds.", -- fn635
    "Easy now. The souls will mend you, one by one.", -- fn636
    "Another soul set free, to ease your pain.", -- fn637
}
M.replies.describe_make_heart = {
    "Ten souls for a heart that can bring life back.", -- fn638
    "All right. I will weave these souls into a Twintailed Heart.", -- fn639
    "A heart? That will cost ten souls.", -- fn640
}
M.replies.heart_made = {
    "The Twintailed Heart is ready. Life gets another chance.", -- fn641
    "Ten souls have become one heart. Use it wisely.", -- fn642
    "Here is the heart. Do not let hope slip away.", -- fn643
}
M.replies.heart_make_failed = {
    "I need ten souls and somewhere to carry the heart.", -- fn644
    "Gather ten souls and leave a little room for the heart.", -- fn645
    "Not yet. Check my souls and the space in my bags.", -- fn646
}
M.replies.activity_wormwood_heal = {
    "I'll dress these wounds before moving on.", -- fn647
    "This medicine should help me recover.", -- fn648
    "These injuries need tending first.", -- fn649
}
M.lines.combat_encouraged = {
    {"Thanks, {1}! I'll do my best!"}, -- fn650
    {"Your encouragement helps. I've got this!"}, -- fn651
    {"I hear you, {1}! I'll watch for an opening."}, -- fn652
    {"I'll stay careful and give it my best shot."}, -- fn653
}
M.lines.sugar_ask = {
    {"{1}, my health is very low and I lack enough healing food. May I eat one Jellybean?"}, -- fn654
    {"{1}, I found Jellybean nearby. May I eat one piece?"}, -- fn655
    {"I am barely standing, {1}. May I eat one Jellybean?"}, -- fn656
}
M.lines.sugar_accept = {
    {"Thank you. I will eat only this one."}, -- fn657
    {"All right, I will use it carefully."}, -- fn658
    {"Understood. One Jellybean, then."}, -- fn659
}
M.lines.sugar_decline = {
    {"All right. I will hold on a little longer."}, -- fn660
    {"Understood. I will not eat it without permission."}, -- fn661
    {"Okay. I will keep looking for proper healing food."}, -- fn662
}

M.replies.describe_plant_trees = {"I'll use the tree seeds I'm carrying to plant around this spot."} -- fn663
M.replies.plant_trees_done = {"This round of planting is finished."} -- fn664
M.replies.plant_trees_no_seeds = {"I'm not carrying any plantable pine cones, birchnuts or twiggy tree cones."} -- fn665
M.replies.plant_trees_no_space = {"There are no more suitable planting spots in this area."} -- fn666
M.replies.wendy_enrage_ok = {"All right. I'll have Abigail become aggressive."} -- fn667
M.replies.wendy_calm_ok = {"All right. I'll have Abigail calm down."} -- fn668
M.replies.wendy_abigail_unavailable = {"Abigail is not summoned right now."} -- fn669
M.lines.time_rewind_near = {
    {"Time turned back, but I still remember you."}, -- fn670
    {"We came back to the past. Do you want to recover what was lost, or make amends for a mistake?"}, -- fn671
    {"It feels like a dream. We have met again in a familiar place."}, -- fn672
    {"The past cannot be recovered, but the future can be changed."}, -- fn673
}
M.lines.time_rewind_far = {
    {"Oh my! How far back in the past have we gone?"}, -- fn674
    {"Even if we returned to our first meeting, I would never forget what we shared."}, -- fn675
    {"If we went back to before we met, you would have to find me again."}, -- fn676
    {"The past can be recovered, and the future can be changed too."}, -- fn677
}
M.lines.rain_request = {
    {"It is raining. Could you give me an umbrella?"}, -- fn678
    {"Do you have an umbrella? Maybe we should find somewhere to shelter together."}, -- fn679
    {"I hope this rain stops soon."}, -- fn680
}
M.lines.season_spring = {
    {"It is spring. We should prepare for the rain."}, -- fn681
    {"Spring is a good season for planting. What do you think?"}, -- fn682
    {"Would you take me along to see the scenery?"}, -- fn683
}
M.lines.season_summer = {
    {"This is the hottest season. Please do not overheat; I would worry about you."}, -- fn684
    {"Shall we visit the oasis and look for treasure together?"}, -- fn685
    {"The days ahead will be hot. Could I have a feather fan?"}, -- fn686
}
M.lines.season_autumn = {
    {"The air is cool, and I can smell the harvest."}, -- fn687
    {"Let us gather supplies for winter while we can."}, -- fn688
    {"Every autumn wind carries a wistful scent. Who are you thinking of?"}, -- fn689
}
M.lines.season_winter = {
    {"My home is by the sea. I had never seen snow before I came here."}, -- fn690
    {"Do not let yourself freeze. Come closer and warm up with me."}, -- fn691
    {"This season makes me want to stay home and warm myself by the fire."}, -- fn692
}
M.lines.follow_reunion = {
    {"Hi, we meet again."}, -- fn693
    {"Long time no see. Are you having fun?"}, -- fn694
    {"Don't forget to bring me along next time!"}, -- fn695
}
return M
