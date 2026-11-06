local simplified_chinese = locale == "zh" or locale == "zhr"
local traditional_chinese = locale == "zht" or locale == "zh_tw" or locale == "zh-tw"
local russian = locale == "ru" or locale == "ru_ru" or locale == "ru-ru"
local chinese = simplified_chinese or traditional_chinese
name = simplified_chinese and "一路同行"
    or traditional_chinese and "一路同行"
    or russian and "Путь вместе"
    or "Journey Together"
description = simplified_chinese and "在这片永恒大陆，我会与你并肩同行。"
    or traditional_chinese and "在這片永恆大陸，我會與你並肩同行。"
    or russian and "На этом вечном континенте я буду путешествовать вместе с тобой."
    or "On this eternal continent, I will travel with you."
author = "阮秀"
version = "3.0.2"
forumthread = ""
api_version = 10

dst_compatible = true
all_clients_require_mod = true
client_only_mod = false
server_filter_tags = {"companion", "伙伴"}

icon_atlas = "friend.xml"
icon = "friend.tex"

local function ExtraKeyOptions()
    local result = {{description = simplified_chinese and "关闭" or traditional_chinese and "關閉"
        or russian and "Отключено" or "Disabled", data = "DISABLED"}}
    for i = 1, 12 do result[#result + 1] = {description = "F" .. i, data = "F" .. i} end
    return result
end

local function UIButtonOptions()
    return {
        {description = simplified_chinese and "关闭" or traditional_chinese and "關閉"
            or russian and "Отключено" or "Disabled", data = false},
        {description = simplified_chinese and "开启" or traditional_chinese and "開啟"
            or russian and "Включено" or "Enabled", data = true},
    }
end

-- Native profile-flair catalogue from the current game atlas; stable keys are saved.
local function ChatIconOptions()
    local icons = {
        {"profileflair_abigail_flower", "阿比盖尔之花", "阿比蓋爾之花", "Цветок Аби", "Abby's Flower"},
        {"profileflair_amulet_orangeplanet", "聚集护符", "聚集護符", "Амулет собирателя", "Gathering Amulet"},
        {"profileflair_amulet_red_rose", "玫瑰红护符", "玫瑰紅護符", "Амулет с красной розой", "Rosy Red Amulet"},
        {"profileflair_amulet_yellowan", "新护符", "新護符", "Амулет в стиле ар-нуво", "Nouveau Amulet"},
        {"profileflair_anchor_nautical", "生锈船锚", "生銹船錨", "Ржавый якорь", "Rusty Anchor"},
        {"profileflair_armor_marbleplanet", "大理石冲击盔甲", "大理石衝擊盔甲", "Ударная мраморная броня", "Marble Impact Armor"},
        {"profileflair_armor_ruinsan", "新铥矿甲", "新銩礦甲", "Тулецитовая броня в стиле ар-нуво", "Nouveau Thulecite Suit"},
        {"profileflair_arrowsignpost_circus", "马戏团路标", "馬戲團路標", "Призрачный, неподвижный указатель", "Spectacular Stationary Wayfinder"},
        {"profileflair_babybeefalo", "牛宝宝", "牛寶寶", "Детеныш бифало", "Baby Beef"},
        {"profileflair_bat_furled", "生气的蝙蝠", "生氣的蝙蝠", "Ворчливый Мышелиск", "Grouchy Bat"},
        {"profileflair_bearger_roar", "暴躁的熊獾", "暴躁的熊獾", "Сердитый Медведь-барсук", "Grumpy Bearger"},
        {"profileflair_beargerfursack_rose", "极地怒放桶", "極地怒放桶", "Ларь с северными цветами", "Polar Bloom Bin"},
        {"profileflair_beargervest_rose", "玫瑰熊獾背心", "玫瑰熊獾背心", "Цветущий жилет из медведя-барсука", "Rosebloom Bearger Vest"},
        {"profileflair_beebox_crystal", "水晶穹顶蜂巢", "水晶穹頂蜂巢", "Хрустальный улей", "Crystalline Honeydome"},
        {"profileflair_beeboxinsect", "黄油蜜蜂", "黃油蜜蜂", "Масляная пчела", "Butterbee"},
        {"profileflair_beefalo", "皮弗娄牛", "皮弗婁牛", "Бифало", "Beefalo"},
        {"profileflair_beefalohat_klaus", "克劳斯帽", "克勞斯帽", "Шапка Клауса", "Klaus Cap"},
        {"profileflair_bernie", "伯尼", "伯尼", "Берни", "Bernie"},
        {"profileflair_birdcage_circus", "神奇的杂耍图标", "神奇的雜耍圖示", "Иконка великолепного аттракциона", "The Amazing Sideshow Icon"},
        {"profileflair_bishop", "发条主教", "發條主教", "Механический слон", "Clockwork Bishop"},
        {"profileflair_boat_nautical", "弃船", "棄船", "Покинутый корабль", "Abandoned Ship"},
        {"profileflair_cane_rose", "玫瑰红手杖", "玫瑰紅手杖", "Трость из красных роз", "Rosy Red Cane"},
        {"profileflair_catcoon", "浣猫", "浣貓", "Енотокот", "Catcoon"},
        {"profileflair_chester", "切斯特", "賈斯特", "Честер", "Chester"},
        {"profileflair_clayhound", "黏土猎犬", "黏土獵犬", "Глиняная гончая", "Clay Hound"},
        {"profileflair_claywarg", "黏土座狼", "黏土座狼", "Глиняный варг", "Clay Varg"},
        {"profileflair_coldfirepit_an", "新冻僵火坑", "新凍僵火坑", "Ледяное кострище в стиле ар-нуво", "Nouveau Frigid Firepit"},
        {"profileflair_coldfirepit_teeth", "刺骨严寒火坑", "刺骨嚴寒火坑", "Леденящий камин", "Bone-Chilling Firepit"},
        {"profileflair_cookpotplanet", "天体瓮烹饪锅", "天體甕烹飪鍋", "Звездный котелок", "Celesturn Crock Pot"},
        {"profileflair_corvus", "良羽鸦", "良羽鴉", "Вран Карлеоне", "Corvus Goodfeather"},
        {"profileflair_crow", "黑乌鸦", "黑烏鴉", "Черный Ворон", "Black Crow"},
        {"profileflair_crowkid", "小乌鸦", "小烏鴉", "Вороненок", "Crow Kid"},
        {"profileflair_cupcake", "杯子蛋糕", "杯子蛋糕", "Кексик", "Cupcake"},
        {"profileflair_deerclops", "独眼巨鹿", "獨眼巨鹿", "Циклополени", "Deerclops"},
        {"profileflair_dragonfly_sleeping", "嗜睡的龙蝇", "嗜睡的龍蠅", "Сонная Дракомуха", "Sleepy Dragonfly"},
        {"profileflair_dragonflychest_kraken", "利维坦箱子", "利維坦箱子", "Сундук левиафана", "Leviathan Chest"},
        {"profileflair_dragonflyfurnace_crystal", "水晶火炉", "水晶火爐", "Хрустальная печь", "Crystalline Furnace"},
        {"profileflair_dragonfruit", "火龙果", "火龍果", "Драконий фрукт", "Dragon Fruit"},
        {"profileflair_egg", "鸟蛋", "鳥蛋", "Яйцо", "Egg"},
        {"profileflair_egg_rotten", "腐烂鸟蛋", "腐爛鳥蛋", "Тухлое яйцо", "Rotten Egg"},
        {"profileflair_eyebrellahat_crystal", "玻璃眼球伞", "玻璃眼球傘", "Стеклянный глазонтик", "Glass Eyebrella"},
        {"profileflair_eyebrellahat_insect", "蠕动眼球伞", "蠕动眼球伞", "Вертлявый глазонтик", "Wriggly Eyebrella"},
        {"profileflair_eyebrellahat_rose", "玫瑰眼球伞", "玫瑰眼球傘", "Розовый глазонтик", "Rosy Eyebrella"},
        {"profileflair_factory", "工厂标识", "工廠標識", "Фабричная табличка", "Factory Signpost"},
        {"profileflair_featherhat_circus", "女骑手头饰", "女騎手頭飾", "Головной убор цирковой наездницы", "Equestrienne Headdress"},
        {"profileflair_firecrackers_yotp", "红鞭炮", "紅鞭炮", "Красные Петарды", "Red Firecrackers"},
        {"profileflair_firesuppressor_circus", "神奇雪球杂耍机", "神奇雪球雜耍機", "Удивительная снежкометалка", "Amazing Snowball Juggler"},
        {"profileflair_fishbox_nautical", "银金枪鱼罐", "銀金槍魚罐", "Серебряная банка с тунцом", "Silver Tuna Tin"},
        {"profileflair_food_berrytart", "浆果挞", "漿果撻", "Ягодный тарт", "Berry Tart"},
        {"profileflair_food_carrotcake", "胡萝卜蛋糕", "胡蘿蔔蛋糕", "Морковный торт", "Carrot Cake"},
        {"profileflair_food_cheeseburger", "芝士汉堡", "芝士漢堡", "Чизбургер", "Cheeseburger"},
        {"profileflair_food_cheesecake", "芝士蛋糕", "芝士蛋糕", "Чизкейк", "Cheesecake"},
        {"profileflair_food_crabcake", "螃蟹蛋糕", "螃蟹蛋糕", "Пирог с крабовым мясом", "Crab Cake"},
        {"profileflair_food_crabroll", "蟹肉卷", "蟹肉卷", "Ролл с крабовым мясом", "Crab Roll"},
        {"profileflair_food_croquette", "炸肉饼", "炸肉餅", "Тефтелька", "Croquette"},
        {"profileflair_food_fishpie", "鱼饼", "魚餅", "Рыбный пирог", "Fish Pie"},
        {"profileflair_food_grilledcheese", "烤芝士", "烤芝士", "Жареный сыр", "Grilled Cheese"},
        {"profileflair_food_jellyroll", "果冻卷", "果凍卷", "Рулет с джемом", "Jelly Roll"},
        {"profileflair_food_meatpie", "肉饼", "肉餅", "Мясной пирог", "Meat Pie"},
        {"profileflair_food_pizza", "美味披萨", "美味披薩", "Вкусная пицца", "Tasty Pizza"},
        {"profileflair_food_potroast", "锅烤美食", "鍋烤美食", "Тушеное мясо", "Pot Roast"},
        {"profileflair_food_pudding", "布丁", "布丁", "Пудинг", "Pudding"},
        {"profileflair_food_roastedveggies", "烤蔬菜", "烤蔬菜", "Жареные овощи", "Roast Vegetables"},
        {"profileflair_food_spaghettiandmeatballs", "意粉和肉丸", "意粉和肉丸", "Спагетти с фрикаделькой", "Spaghetti and Meatball"},
        {"profileflair_food_steakfrites", "牛排薯条", "牛排薯條", "Стейк с картошкой", "Steak Frites"},
        {"profileflair_food_stuffedmushroom", "酿蘑菇", "塞滿餡料的蘑菇", "Фаршированный гриб", "Stuffed Mushroom"},
        {"profileflair_food_trifle", "多层小蛋糕", "多層小蛋糕", "Бисквит", "Trifle"},
        {"profileflair_food_turnipcake", "大萝卜蛋糕", "大蘿蔔蛋糕", "Пирог с репой", "Turnip Cake"},
        {"profileflair_frog", "青蛙", "青蛙", "Лягушечка", "Froggy"},
        {"profileflair_gift_1", "金色礼物", "金色禮物", "Золотой подарок", "Golden Present"},
        {"profileflair_gift_2", "绿色礼物", "綠色禮物", "Зеленый подарок", "Green Gift"},
        {"profileflair_gift_3", "糟糕的包装", "糟糕的包裝", "Небрежно упакованная коробка", "Poorly Wrapped Package"},
        {"profileflair_goosemoose", "麋鹿鹅", "麋鹿鵝", "Лось/Гусь", "Moose/Goose"},
        {"profileflair_greenstaff_an", "新拆解器", "新拆解器", "Разрушитель в стиле ар-нуво", "Nouveau Deconstructor"},
        {"profileflair_greenstaff_planet", "全局解构魔杖", "全域解構魔杖", "Посох всемирного разрушения", "Global Deconstruction Staff"},
        {"profileflair_hambat_nautical", "海鱼棒", "海魚棒", "Рыбья бита", "Fishy Bat"},
        {"profileflair_heatrock_fire", "变形火焰", "變形火焰", "Метаморфоза пламени", "Metamorphosed Flame"},
        {"profileflair_heatrock_planet", "烈焰核心", "烈焰核心", "Пламенное ядро", "Pyric Core"},
        {"profileflair_hivehat_an", "新皇冠", "新皇冠", "Корона в стиле ар-нуво", "Nouveau Crown"},
        {"profileflair_hound", "猎犬", "獵犬", "Гончая", "Hound"},
        {"profileflair_icebox_crystal", "水晶冰箱", "水晶冰箱", "Хрустальный холодильник", "Crystalline Ice Box"},
        {"profileflair_icehound", "蓝色猎犬", "藍色獵犬", "Синяя гончая", "Blue Hound"},
        {"profileflair_knight", "发条骑士", "發條騎士", "Механический конь", "Clockwork Knight"},
        {"profileflair_koalefant", "考拉象", "考拉象", "Коалослон", "Koalefant"},
        {"profileflair_krampus", "坎普斯", "坎普斯", "Крампус", "Krampus"},
        {"profileflair_lantern_crystal", "盐灯", "鹽燈", "Соляная лампа", "Salt Lamp"},
        {"profileflair_lantern_insect", "蝇光灯", "蠅光燈", "Свет светляков", "Light of the Flies"},
        {"profileflair_lightningrodnautical", "惩戒避雷针", "懲戒避雷針", "Кароотвод", "Smite'ning Rod"},
        {"profileflair_living_wood", "有生命的万圣节树木", "有生命的萬聖節樹木", "Живое хэллоуинское дерево", "Living Halloween Tree"},
        {"profileflair_luckygoldnugget_yotp", "幸运金块", "幸運金塊", "Счастливый Золотой Самородок", "Lucky Gold Nugget"},
        {"profileflair_mactusk", "海象", "海象", "МакБивень", "MacTusk"},
        {"profileflair_mad_science", "疯狂科学家实验室", "瘋狂科學家實驗室", "Лаборатория безумного ученого", "Mad Scientist Lab"},
        {"profileflair_mandrake", "曼德拉草", "曼德拉草", "Мандрагора", "Mandrake"},
        {"profileflair_mast_nautical", "岩石大白鲨风帆", "岩石大白鯊風帆", "Парус Камнезева", "Rockjaw Sail"},
        {"profileflair_mastupgradelamp_nautical", "贝壳甲板照明仪", "貝殼甲板照明儀", "Ракушечный мачтовый фонарь", "Shellbound Deck Illuminator"},
        {"profileflair_mastupgradelightningrod_nautical", "巨蛇风暴吞噬者", "巨蛇風暴吞噬者", "Витой грозоед", "Serpentine Storm Eater"},
        {"profileflair_merm", "鱼人", "魚人", "Тритон", "Merm"},
        {"profileflair_mole", "鼹鼠", "鼴鼠", "Кроточервь", "Moleworm"},
        {"profileflair_moonstaff_crystal", "棱镜唤月者魔杖", "棱鏡喚月者魔杖", "Призматический посох призывателя луны", "Prismatic Moon Caller Staff"},
        {"profileflair_mudpie_yotp", "八宝泥馅饼", "八寶泥餡餅", "Грязевой пирог Восьми Сокровищ", "Eight Treasures Mud Pie"},
        {"profileflair_mushroom_light2an", "折衷蘑菇灯", "折衷蘑菇燈", "Эклектичная светошляпка", "Eclectic Glowcap"},
        {"profileflair_mushroom_lightan", "马赛克蘑菇灯", "馬賽克蘑菇燈", "Мозаичная гриболампа", "Mosaic Mushlamp"},
        {"profileflair_nightlight", "暗夜灯", "魂燈", "Пламя ночи", "Night Light"},
        {"profileflair_none", "空头像", "空頭像", "Пустой значок", "Empty avatar"},
        {"profileflair_ornaments_1", "精致的节庆小饰品", "精緻的節慶小飾品", "Нарядная Праздничная игрушка", "Fine Festive Bauble"},
        {"profileflair_ornaments_10", "华丽的坎普斯装饰物", "華麗的坎普斯裝飾物", "Великолепное украшение в виде Клауса", "Magnificent Klaus Ornament"},
        {"profileflair_ornaments_11", "华丽的无眼鹿装饰物", "華麗的無眼鹿裝飾物", "Великолепное украшение в виде Безглазого оленя", "Magnificent No-Eyed Deer Ornament"},
        {"profileflair_ornaments_12", "绿色节庆小饰品", "綠色節慶小飾品", "Зеленая Праздничная игрушка", "Green Festive Bauble"},
        {"profileflair_ornaments_13", "盛宴树盆", "盛宴樹盆", "Кадка для Праздничной Ели", "Festive Tree Planter"},
        {"profileflair_ornaments_14", "独眼巨鹿装饰物", "獨眼巨鹿裝飾物", "Украшение: циклополень", "Deerclops Ornament"},
        {"profileflair_ornaments_15", "麋鹿鹅装饰物", "麋鹿鵝裝飾物", "Украшение: лось/гусь", "Moose/Goose Ornament"},
        {"profileflair_ornaments_16", "蜂王装饰物", "蜂王裝飾物", "Украшение: пчелиная матка", "Bee Queen Ornament"},
        {"profileflair_ornaments_17", "邪天翁饰品", "邪天翁飾品", "Украшение «Мальбатрос»", "Malbatross Ornament"},
        {"profileflair_ornaments_2", "节庆星星小饰品", "節慶星星小飾品", "Звездная Праздничная игрушка", "Festive Star Bauble"},
        {"profileflair_ornaments_3", "华丽的织影者装饰物", "華麗的織影者裝飾物", "Великолепное украшение в виде Кошмарного Прядильщика", "Magnificent Fuelweaver Ornament"},
        {"profileflair_ornaments_4", "红色节庆小饰品", "紅色節慶小飾品", "Красная Праздничная игрушка", "Red Festive Bauble"},
        {"profileflair_ornaments_5", "欢快的蓝灯", "歡快的藍燈", "Веселая Синяя лампочка", "Jolly Blue Light"},
        {"profileflair_ornaments_6", "华丽的坎普斯装饰物", "華麗的坎普斯裝飾物", "Великолепное украшение в виде Крампуса", "Magnificent Krampus Ornament"},
        {"profileflair_ornaments_7", "粉色节庆小饰品", "粉色節慶小飾品", "Розовая Праздничная игрушка", "Pink Festive Bauble"},
        {"profileflair_ornaments_8", "精美的星星小饰品", "精美的星星小飾品", "Забавная Звездная игрушка", "Fancy Star Bauble"},
        {"profileflair_ornaments_9", "华丽的蚁狮装饰物", "華麗的蟻獅裝飾物", "Великолепное украшение в виде Муравьиного Льва", "Magnificent Antlion Ornament"},
        {"profileflair_panflute_an", "新排箫", "新排簫", "Панфлейта в стиле ар-нуво", "Nouveau Panflute"},
        {"profileflair_panflute_insect", "蝶箫", "蝶簫", "Флейтабочка", "Butterflute"},
        {"profileflair_pengull", "企鸥", "企鷗", "Пинчайка", "Pengull"},
        {"profileflair_phonograph", "邪恶留声机", "邪惡留聲機", "Никудышный граммофон", "Wretched Gramophone"},
        {"profileflair_pig_happy", "快乐的猪人", "快樂的豬人", "Счастливый Свинолюд", "Happy Pigman"},
        {"profileflair_pigking", "猪王", "豬王", "Король свиней", "The Pig King"},
        {"profileflair_pigking_yotp", "猪王", "豬王", "Король свиней", "Pig King"},
        {"profileflair_pigtoken_yotp", "金腰带", "金腰帶", "Золотой пояс", "Golden Belt"},
        {"profileflair_potion_sanity", "理智药水", "理智藥水", "Зелье благоразумия", "Sensible Potion"},
        {"profileflair_pottedfern_cotl", "山茶花坛", "山茶花壇", "Клумба с камелиями", "Camellia Flowerbed"},
        {"profileflair_pottedfern_rose", "玫瑰盆栽", "玫瑰盆栽", "Розовый куст", "Rose Bushel"},
        {"profileflair_pumpkinlantern", "可怕的南瓜灯", "可怕的南瓜燈", "Жуткий Фонарь из тыквы", "Spooky Pumpkin Lantern"},
        {"profileflair_puppington", "小座狼", "小座狼", "Варжонок", "Vargling"},
        {"profileflair_quagmiretournament_bronze", "饕餮镀铜图标", "饕餮鍍銅圖示", "Сверкающая иконка Грызуна", "Burnished Icon of Gnaw"},
        {"profileflair_quagmiretournament_gold", "饕餮黄金图标", "饕餮黃金圖示", "Золотая иконка Грызуна", "Golden Icon of Gnaw"},
        {"profileflair_quagmiretournament_participation", "饕餮图标", "饕餮圖示", "Иконка Грызуна", "Icon of Gnaw"},
        {"profileflair_quagmiretournament_silver", "饕餮纯银图标", "饕餮純銀圖示", "Серебряная иконка Грызуна", "Sterling Icon of Gnaw"},
        {"profileflair_rabbit", "兔子", "兔子", "Кролик", "Rabbit"},
        {"profileflair_rabbithouse_yule", "倒挂树屋", "倒掛樹屋", "Древесный дом вверх дном", "Topsy-Turvy Treehouse"},
        {"profileflair_rainometer_circus", "华丽的雨量计图标", "華麗的雨量計圖示", "Иконка великолепного дождеметра", "The Magnificent Rainometer Icon"},
        {"profileflair_redbird", "红雀", "紅雀", "Красная птица", "Redbird"},
        {"profileflair_redhound", "红色猎犬", "紅色獵犬", "Красная гончая", "Red Hound"},
        {"profileflair_redlantern_yotp", "红灯笼", "紅燈籠", "Красный Фонарь", "Red Lantern"},
        {"profileflair_researchlab2_crystal", "神秘水晶", "神秘水晶", "Магический кристаллариум", "Arcane Crystalarium"},
        {"profileflair_researchlab3_crystal", "附魔水晶", "附魔水晶", "Зачарованный хрусталь", "Enchanted Crystal"},
        {"profileflair_researchlab3_monster", "恐怖怪兽", "恐怖怪獸", "Чудовищный ужас", "Monstrous Horror"},
        {"profileflair_researchlab_green", "恐怖漏液机器", "恐怖漏液機器", "Аппарат с мерзкой слизью", "Terrible Ooze Machine"},
        {"profileflair_rook", "发条战车", "發條戰車", "Механическая ладья", "Clockwork Rook"},
        {"profileflair_rose", "红玫瑰", "紅玫瑰", "Красная роза", "Red Rose"},
        {"profileflair_ruins_batan", "新大棒", "新大棒", "Булава в стиле ар-нуво", "Nouveau Club"},
        {"profileflair_ruinshat_an", "新头饰", "新頭飾", "Диадема в стиле ар-нуво", "Nouveau Headpiece"},
        {"profileflair_saltbox_shaker", "盐罐", "鹽罐", "Солонка", "Salt Shaker"},
        {"profileflair_saltboxnautical", "海水盐盒", "海水鹽盒", "Просоленный ящик", "Briny Salt Box"},
        {"profileflair_shadowhand", "黑夜之手", "黑夜之手", "Теневая рука", "Night Hand"},
        {"profileflair_shadowmanipulator", "暗影操控器", "暗影操控器", "Теневой манипулятор", "Shadow Manipulator"},
        {"profileflair_skincollector", "珍宝收集者", "珍寶收集者", "Коллекционер предметов", "Curio Collector"},
        {"profileflair_smallbird", "小鸟", "小鳥", "Птенец", "Smallbird"},
        {"profileflair_snowbird", "雪雀", "雪雀", "Снежная птица", "Snowbird"},
        {"profileflair_spider", "蜘蛛", "蜘蛛", "Паук", "Spider"},
        {"profileflair_starstaff_crystal", "光芒唤星者魔杖", "光芒喚星者魔杖", "Сияющий посох призывателя звезд", "Radiant Star Caller's Staff"},
        {"profileflair_steeringwheel_nautical", "鱿鱼方向舵", "魷魚方向舵", "Штурвал-кальмар", "Skittersquid Helm"},
        {"profileflair_tallbird_eye", "高脚鸟的注视", "高腳鳥的注視", "Пристальный взгляд долговязой птицы", "Tallbird Stare"},
        {"profileflair_telebase_crystal", "黑魔法", "黑魔法", "Темная магия", "Dark Magic"},
        {"profileflair_telestaff_crystal", "巫师法杖", "巫師法杖", "Волшебный посох", "Sorcerer's Staff"},
        {"profileflair_tent_an", "新帐篷", "新帳篷", "Палатка в стиле ар-нуво", "Nouveau Tent"},
        {"profileflair_tent_circus", "世界之最大顶篷图标", "世界之最大頂篷圖示", "Иконка: лучший в мире цирковой шатер", "World's Greatest Big Top Tent Icon"},
        {"profileflair_theforge_battlestandard", "鳄鱼指挥官旗帜", "鱷魚指揮官旗幟", "Боевое знамя крокомандира", "Crocommander Standard"},
        {"profileflair_theforge_battlestandardattack", "攻击旗帜", "攻擊旗幟", "Боевое знамя атаки", "Attack Standard"},
        {"profileflair_theforge_battlestandardheal", "治愈旗帜", "治癒旗幟", "Боевое знамя исцеления", "Healing Standard"},
        {"profileflair_theforge_beetletaur", "地狱独眼巨猪", "地獄獨眼巨豬", "Адский Свиноклоп", "Infernal Swineclops"},
        {"profileflair_theforge_blowdarts", "战斗吹箭", "戰鬥吹箭", "Боевые дротики", "Battle Darts"},
        {"profileflair_theforge_boaraudienceboo", "冷嘲热讽的野猪", "冷嘲熱諷的野豬", "Глумящийся боров", "Jeering Boar"},
        {"profileflair_theforge_boaraudiencecheer", "欢呼的野猪", "歡呼的野豬", "Подбадривающий боров", "Cheering Boar"},
        {"profileflair_theforge_boaraudienceeat", "大笑的野猪", "大笑的野豬", "Смеющийся боров", "Laughing Boar"},
        {"profileflair_theforge_boarlord", "战斗大师普格纳", "戰鬥大師普格納", "Полководец Пугна", "Battlemaster Pugna"},
        {"profileflair_theforge_boaron", "战猪", "戰豬", "Хряк из пекла", "Pit Pig"},
        {"profileflair_theforge_boarrior", "大熔炉猪战士", "大熔爐豬戰士", "Великий Боров-воин Горнила", "Grand Forge Boarrior"},
        {"profileflair_theforge_bookelemental", "召唤之书", "召喚之書", "Том призыва", "Tome of Beckoning"},
        {"profileflair_theforge_bookfossil", "石化之书", "石化之書", "Том окаменения", "Petrifying Tome"},
        {"profileflair_theforge_elementalattack", "岩浆傀儡", "岩漿傀儡", "Магмовый голем", "Magma Golem"},
        {"profileflair_theforge_elementalrise", "岩浆傀儡攻击", "岩漿傀儡攻擊", "Атака магмового голема", "Magma Golem Attack"},
        {"profileflair_theforge_fireballstaff", "地狱魔杖", "地獄魔杖", "Адский посох", "Infernal Staff"},
        {"profileflair_theforge_gungnir", "尖齿矛", "尖齒矛", "Мощная пика", "Pith Pike"},
        {"profileflair_theforge_hammer", "锻锤", "鍛錘", "Молот Горнила", "Forging Hammer"},
        {"profileflair_theforge_healingstaff", "生命魔杖", "生命魔杖", "Посох жизни", "Living Staff"},
        {"profileflair_theforge_lance", "螺旋矛", "螺旋矛", "Спиральное копье", "Spiral Spear"},
        {"profileflair_theforge_peghook", "蝎子", "蠍子", "Скорпехотинец", "Scorpeon"},
        {"profileflair_theforge_rhinodrill", "犀牛兄弟", "犀牛兄弟", "Носоробро", "Rhinocebro"},
        {"profileflair_theforge_snapper", "鳄鱼指挥官", "鱷魚指揮官", "Крокомандир", "Crocommander"},
        {"profileflair_theforge_tails", "野猪猩", "野豬猩", "Свинорилла", "Boarilla"},
        {"profileflair_theforge_tailsguard", "戒备的野猪猩", "戒備的野豬猩", "Предусмотрительная Свинорилла", "Guarded Boarilla"},
        {"profileflair_theforge_turtillus", "坦克龟", "坦克龜", "Хрюкопаха", "Snortoise"},
        {"profileflair_toothtrap_rose", "玫瑰尖刺陷阱", "玫瑰尖刺陷阱", "Ловушка из розовых шипов", "Rose Thorn Trap"},
        {"profileflair_tophat_circus", "神奇驯兽师帽图标", "神奇馴獸師帽圖示", "Иконка шляпы потрясающего шпрехшталмейстера", "Amazing Ringmaster Hat Icon"},
        {"profileflair_torch_nautical", "海螺火炬", "海螺火炬", "Ракушечный факел", "Conch Torch"},
        {"profileflair_treasurechest_monster", "残暴箱子", "殘暴箱子", "Грубый сундук", "Brute Case"},
        {"profileflair_treeguard", "树精守卫", "樹精守衛", "Энт", "Treeguard"},
        {"profileflair_trinket_faketeeth", "二手假牙", "二手假牙", "Поношенная вставная челюсть", "Second-hand Dentures"},
        {"profileflair_trinket_gnome", "地精爷爷", "地精爺爺", "Гном", "Gnome"},
        {"profileflair_trinket_gnomette", "地精奶奶", "地精奶奶", "Гнометта", "Gnomette"},
        {"profileflair_umbrella_circus", "马戏团伞顶头像", "馬戲團傘頂頭像", "Значок Огромный зонт", "Big Top Umbrella Icon"},
        {"profileflair_varg", "座狼", "座狼", "Варг", "Varg"},
        {"profileflair_victorian_boar", "沼泽猪长老", "沼澤豬長老", "Болотный свин-старейшина", "Swamp Pig Elder"},
        {"profileflair_victorian_coppercoin", "三枚硬币", "三枚硬幣", "Три монеты", "Three Coins"},
        {"profileflair_victorian_goatkid", "比利（小子）", "比利（小子）", "Билли (малыш)", "Billy (The Kid)"},
        {"profileflair_victorian_goatmom", "玛姆茜", "瑪姆茜", "Мамушка", "Mumsy"},
        {"profileflair_victorian_goldcoin", "三个马克硬币", "三個馬克硬幣", "Три метки", "Three Marks"},
        {"profileflair_victorian_merm", "皮普顿", "皮普頓", "Пиптон", "Pipton"},
        {"profileflair_victorian_merm2", "萨米", "薩米", "Сэмми", "Sammy"},
        {"profileflair_victorian_pigeon", "鸽子", "鴿子", "Голубь", "Pigeon"},
        {"profileflair_victorian_safe", "保险箱", "保險箱", "Сейф", "Safe"},
        {"profileflair_victorian_silvercoin", "三枚徽章", "三枚徽章", "Три медальона", "Three Medallions"},
        {"profileflair_victorian_topazcoin", "三重青睐", "三個惠贈", "Три милости", "Three Favors"},
        {"profileflair_waffle", "华夫饼！", "華夫餅！", "Вафли!", "Waffles!"},
        {"profileflair_wardrobe_crystal", "水晶", "水晶", "Кристаллы", "Crystals"},
        {"profileflair_wardrobe_insect", "蝴蝶衣柜", "蝴蝶衣櫃", "Butterfly Wardrobe", "Butterfly Wardrobe"},
        {"profileflair_wardrobe_yule", "冬季衣柜", "冬季衣櫃", "Зимний гардероб", "Winter Wardrobe"},
        {"profileflair_waterballoon_insect", "爆虫水球", "爆蟲水球", "Bugburst Waterballoon", "Bugburst Waterballoon"},
        {"profileflair_watermelonhat_pumpkin", "时髦南瓜帽", "時髦南瓜帽", "Стильная тыквенная шляпа", "Fashionable Pumpkin Hat"},
        {"profileflair_werepig_howl", "疯猪", "瘋豬", "Свин-оборотень", "Werepig"},
        {"profileflair_wererabbit", "友好的兔人", "友好的兔人", "Дружелюбный Заяц", "Friendly Bunnyman"},
        {"profileflair_winterometer_circus", "热强度测量器图标", "熱強度測量器圖示", "Иконка: термосиломер", "Thermal Strength Measurer Icon"},
        {"profileflair_yule_bearger", "暴躁的熊獾", "暴躁的熊獾", "Своенравный Медведь-барсук", "Cranky Bearger"},
        {"profileflair_yule_candycane", "拐杖糖", "拐杖糖", "Карамельная Трость", "Candy Cane"},
        {"profileflair_yule_chocolatelog", "巧克力原木蛋糕", "巧克力原木蛋糕", "Шоколадное Рождественское Полено", "Chocolate Log Cake"},
        {"profileflair_yule_claus", "克劳斯", "克勞斯", "Клаус", "Klaus"},
        {"profileflair_yule_deer", "无眼鹿", "無眼鹿", "Безглазый Олень", "No-Eyed Deer"},
        {"profileflair_yule_deerclops", "极饿的盛宴独眼巨鹿", "極餓的盛宴獨眼巨鹿", "Прожорливый Праздничный циклоп", "Ravenous Feastclops"},
        {"profileflair_yule_doorgategingerbread", "姜饼门", "薑餅門", "Пряничная калитка", "Gingerbread Gate"},
        {"profileflair_yule_dragonfly", "冬季盛宴龙蝇", "冬季盛宴龍蠅", "Зимняя Праздничная муха", "Winter's Feastfly"},
        {"profileflair_yule_dragonflyfire", "火热盛宴龙蝇", "火熱盛宴龍蠅", "Огнеопасная Праздничная муха", "Fiery Feastfly"},
        {"profileflair_yule_eggnog", "美味的蛋酒", "美味的蛋酒", "Небесный Эггног", "Heavenly Eggnog"},
        {"profileflair_yule_fruitcake", "永远的水果蛋糕", "永遠的水果蛋糕", "Фруктовый Кекс", "Eternal Fruitcake"},
        {"profileflair_yule_gingerbreadman", "小姜饼", "小薑餅", "Имбирное Печенье", "Gingerbread Cookie"},
        {"profileflair_yule_gingerpig", "姜饼猪", "薑餅豬", "Пряничный свин", "Gingerbread Pig"},
        {"profileflair_yule_gingervarg", "姜饼座狼", "薑餅座狼", "Пряничный варг", "Gingerbread Varg"},
        {"profileflair_yule_glommer", "冰雪格罗姆", "冰雪格羅姆", "Ледяной гломглом", "Ice Glomglom"},
        {"profileflair_yule_goosemoose", "欢快麋鹿鹅", "歡快麋鹿鵝", "Веселый Лось/Гусь", "Jolly Moose/Goose"},
        {"profileflair_yule_hotchocolate", "热可可", "熱可哥", "Горячее Какао", "Hot Cocoa"},
        {"profileflair_yule_mulledwine", "香料潘趣酒", "香料潘趣酒", "Пунш со специями", "Mulled Punch"},
        {"profileflair_yule_mushroomlightfestive", "节庆真菌灯", "節慶真菌燈", "Праздничная гриболампа", "Festive Fungal Lamp"},
        {"profileflair_yule_pumpkinpie", "南瓜派", "南瓜餅", "Тыквенный пирог", "Pumpkin Pie"},
        {"profileflair_yule_puppington", "寒冬小座狼", "寒冬小座狼", "Озимевший варжонок", "Winterized Vargling"},
        {"profileflair_yule_roastturkey", "烤火鸡", "烤火雞", "Жареная индейка", "Roasted Turkey"},
        {"profileflair_yule_sugarcookie", "糖曲奇饼", "糖曲奇餅", "Сахарное Печенье", "Sugar Cookie"},
    }
    local result = {}
    for i = 1, #icons do
        local icon = icons[i]
        result[#result + 1] = {data = icon[1], description = simplified_chinese and icon[2]
            or traditional_chinese and icon[3] or russian and icon[4] or icon[5]}
    end
    return result
end

configuration_options = {
    {
        name = "companion_chat_icon",
        label = simplified_chinese and "伙伴聊天头像" or traditional_chinese and "夥伴聊天頭像"
            or russian and "Значок чата спутника" or "Companion Chat Avatar",
        hover = simplified_chinese and "附近与公共聊天共用。可选择当前游戏的聊天头像，默认冰雪格罗姆；缺少资源时显示空头像。"
            or traditional_chinese and "附近與公共聊天共用。可選擇目前遊戲的聊天頭像，預設冰雪格羅姆；缺少資源時顯示空頭像。"
            or russian and "Общий значок для чата рядом и общего чата. По умолчанию ледяной гломглом; недоступные значки заменяются пустым."
            or "Used for nearby and public chat. Defaults to Ice Glomglom; unavailable icons fall back to an empty avatar.",
        options = ChatIconOptions(), default = "profileflair_yule_glommer",
    },
    {
        name = "model_enabled",
        label = simplified_chinese and "AI大模型模式" or traditional_chinese and "AI大模型模式"
            or russian and "Режим ИИ" or "AI Model Mode",
        hover = simplified_chinese and "启用模型接口及自动连接，无需先跟随。公屏带伙伴名字即可聊天；跟随时只接受领队安排工作。重试间隔递增5秒，连续30次失败停止。"
            or traditional_chinese and "啟用模型介面及自動連線，無需先跟隨。公頻帶夥伴名字即可聊天；跟隨時只接受領隊安排工作。重試間隔遞增5秒，連續30次失敗停止。"
            or russian and "Автоподключение без следования. В чате называйте спутника по имени; при следовании работу задаёт только лидер. Интервал +5 секунд, до 30 ошибок."
            or "Connects automatically without following. Address the companion by name in chat; while following, only the leader can assign work. Retry delay +5 seconds, up to 30 failures.",
        options = UIButtonOptions(), default = false,
    },
    {
        name = "model_dedicated_transport",
        label = simplified_chinese and "专服模型连接方式" or traditional_chinese and "專服模型連線方式"
            or russian and "Подключение ИИ на сервере" or "Dedicated Server AI Connection",
        hover = simplified_chinese and "管理员客户端模式使用管理员电脑上的助手，支持与伙伴分处地表和洞穴；常规配对可由伙伴分片连接云服上的API助手。"
            or traditional_chinese and "管理員用戶端模式使用管理員電腦上的助手，支援與夥伴分處地表和洞穴；一般配對可由夥伴分片連線雲服上的API助手。"
            or russian and "Помощник администратора может находиться на другом осколке. Обычное подключение использует API-помощник на сервере."
            or "Admin relay supports players on another shard. Standard server pairing can connect to the API assistant running on the server.",
        options = {
            {description = simplified_chinese and "常规配对" or traditional_chinese and "一般配對"
                or russian and "Обычное подключение" or "Standard Pairing", data = "standard"},
            {description = simplified_chinese and "管理员客户端" or traditional_chinese and "管理員用戶端"
                or russian and "Клиент администратора" or "Admin Client", data = "admin_client"},
        },
        default = "standard",
    },
    {
        name = "command_wheel_extra_key",
        label = simplified_chinese and "指令轮盘额外快捷键" or traditional_chinese and "指令輪盤額外快捷鍵"
            or russian and "Доп. клавиша колеса команд" or "Additional Command Wheel Key",
        hover = simplified_chinese and "保留原来的 Alt+字母快捷键。" or traditional_chinese and "保留原來的 Alt+字母快捷鍵。"
            or russian and "Сочетание Alt+буква продолжает работать." or "The existing Alt+letter shortcut still works.",
        options = ExtraKeyOptions(), default = "DISABLED",
    },
    {
        name = "companion_panel_extra_key",
        label = simplified_chinese and "伙伴面板额外快捷键" or traditional_chinese and "夥伴面板額外快捷鍵"
            or russian and "Доп. клавиша панели спутника" or "Additional Companion Panel Key",
        hover = simplified_chinese and "保留 Alt+鼠标右键；优先打开鼠标下伙伴的面板。" or traditional_chinese and "保留 Alt+滑鼠右鍵；優先開啟滑鼠下夥伴的面板。"
            or russian and "Alt+ПКМ также работает. Приоритет у спутника под курсором." or "Alt+right-click still works. Prefers the companion under the cursor.",
        options = ExtraKeyOptions(), default = "DISABLED",
    },
    {
        name = "companion_panel_ui_button",
        label = simplified_chinese and "伙伴背包面板按钮" or traditional_chinese and "夥伴背包面板按鈕"
            or russian and "Кнопка инвентаря спутника" or "Companion Inventory Button",
        hover = simplified_chinese and "在屏幕顶部居中显示可点击或触摸的伙伴面板按钮。"
            or traditional_chinese and "在螢幕頂部置中顯示可點擊或觸摸的夥伴面板按鈕。"
            or russian and "Показывает вверху по центру экрана кнопку панели спутника для мыши и касаний."
            or "Show a companion panel button at the top center for mouse or touch input.",
        options = UIButtonOptions(), default = false,
    },
    {
        name = "command_wheel_ui_button",
        label = simplified_chinese and "指令轮盘按钮" or traditional_chinese and "指令輪盤按鈕"
            or russian and "Кнопка колеса команд" or "Command Wheel Button",
        hover = simplified_chinese and "在屏幕顶部居中显示可点击或触摸的指令轮盘按钮。"
            or traditional_chinese and "在螢幕頂部置中顯示可點擊或觸摸的指令輪盤按鈕。"
            or russian and "Показывает вверху по центру экрана кнопку колеса команд для мыши и касаний."
            or "Show a command wheel button at the top center for mouse or touch input.",
        options = UIButtonOptions(), default = false,
    },
    {
        name = "language",
        label = simplified_chinese and "伙伴语言"
            or traditional_chinese and "夥伴語言"
            or russian and "Язык спутника"
            or "Companion Language",
        options = {
            -- Add a new {description = "...", data = "xx"} entry after the
            -- reviewed files are added under scripts/languages/xx/.
            {description = simplified_chinese and "中文"
                or traditional_chinese and "簡體中文"
                or russian and "Китайский"
                or "Chinese", data = "zh"},
            {description = simplified_chinese and "繁体中文"
                or traditional_chinese and "繁體中文"
                or russian and "Традиционный китайский"
                or "Traditional Chinese", data = "zh_tw"},
            {description = chinese and "English"
                or russian and "Английский"
                or "English", data = "en"},
            {description = simplified_chinese and "俄语"
                or traditional_chinese and "俄語"
                or russian and "Русский"
                or "Russian", data = "ru"},
        },
        default = traditional_chinese and "zh_tw"
            or simplified_chinese and "zh"
            or russian and "ru"
            or "en",
    },
    {
        name = "voice_enabled",
        label = simplified_chinese and "伙伴语音"
            or traditional_chinese and "夥伴語音"
            or russian and "Голос спутника"
            or "Companion Voice",
        options = {
            {description = simplified_chinese and "开启"
                or traditional_chinese and "開啟"
                or russian and "Включён"
                or "Enabled", data = true},
            {description = simplified_chinese and "关闭"
                or traditional_chinese and "關閉"
                or russian and "Выключен"
                or "Disabled", data = false},
        },
        default = true,
    },
    {
        name = "command_wheel_key",
        label = simplified_chinese and "指令轮盘 Alt 快捷键"
            or traditional_chinese and "指令輪盤 Alt 快捷鍵"
            or russian and "Клавиша колеса команд с Alt"
            or "Command Wheel Shortcut",
        options = {
            {description = "Alt+A", data = "a"}, {description = "Alt+B", data = "b"},
            {description = "Alt+C", data = "c"}, {description = "Alt+D", data = "d"},
            {description = "Alt+E", data = "e"}, {description = "Alt+F", data = "f"},
            {description = "Alt+G", data = "g"}, {description = "Alt+H", data = "h"},
            {description = "Alt+I", data = "i"}, {description = "Alt+J", data = "j"},
            {description = "Alt+K", data = "k"}, {description = "Alt+L", data = "l"},
            {description = "Alt+M", data = "m"}, {description = "Alt+N", data = "n"},
            {description = "Alt+O", data = "o"}, {description = "Alt+P", data = "p"},
            {description = "Alt+Q", data = "q"}, {description = "Alt+R", data = "r"},
            {description = "Alt+S", data = "s"}, {description = "Alt+T", data = "t"},
            {description = "Alt+U", data = "u"}, {description = "Alt+V", data = "v"},
            {description = "Alt+W", data = "w"}, {description = "Alt+X", data = "x"},
            {description = "Alt+Y", data = "y"}, {description = "Alt+Z", data = "z"},
        },
        default = "r",
    },
}
-- Standard DST mod configuration has no free-form text field; six digit
-- selectors allow an arbitrary code without adding a custom configuration UI.
for i = 1, 6 do
    local digits = {}
    for digit = 0, 9 do digits[#digits + 1] = {description = "" .. digit, data = "" .. digit} end
    configuration_options[#configuration_options + 1] = {
        name = "model_pair_digit_" .. i,
        label = simplified_chinese and ("模型配对码第" .. i .. "位") or traditional_chinese and ("模型配對碼第" .. i .. "位")
            or russian and ("Цифра кода ИИ " .. i) or ("Model Pairing Code Digit " .. i),
        hover = simplified_chinese and "六位组合须与助手设置一致，默认321151。" or traditional_chinese and "六位組合須與助手設定一致，預設321151。"
            or russian and "Совпадает с кодом помощника; по умолчанию 321151." or "Must match the assistant code; default 321151.",
        options = digits, default = ("321151"):sub(i, i),
    }
end
