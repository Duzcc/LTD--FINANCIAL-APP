"""Từ vựng giao dịch tiếng Việt dùng để sinh bộ dữ liệu huấn luyện.

Mỗi danh mục gồm: hành động (verbs), đồ vật/dịch vụ (items), nơi chốn/thương hiệu
(places). Nhãn danh mục trùng mã danh mục mặc định của ứng dụng.
"""

CATEGORIES = {
    # ---------------- chi tiêu ----------------
    "food": {
        "income": False,
        "name": "Ăn uống",
        "verbs": ["ăn", "uống", "mua", "đặt", "gọi", "đi ăn", "ăn vặt", "đãi", "mời", "liên hoan", "nhậu"],
        "items": [
            "phở", "bún bò", "bún chả", "bánh mì", "cơm tấm", "cơm văn phòng", "cơm trưa", "cơm gà", "xôi",
            "bánh cuốn", "hủ tiếu", "mì quảng", "bún riêu", "lẩu", "nướng", "gà rán", "pizza", "bánh xèo",
            "cà phê", "cà phê sữa đá", "bạc xỉu", "trà sữa", "trà đá", "nước mía", "sinh tố", "nước ngọt",
            "bia", "rượu", "kem", "bánh ngọt", "trái cây", "hoa quả", "rau", "thịt", "cá", "trứng", "gạo",
            "sữa", "đồ ăn sáng", "bữa trưa", "bữa tối", "đồ ăn vặt", "bánh tráng trộn", "ốc", "hải sản",
            "đồ nhậu", "buffet", "lẩu nướng", "sushi", "gà", "vịt", "chè", "bánh bao", "mì tôm", "đồ ăn",
        ],
        "places": [
            "Highlands", "Phúc Long", "Starbucks", "The Coffee House", "Katinat", "Cộng cà phê", "GrabFood",
            "ShopeeFood", "Baemin", "KFC", "Lotteria", "Jollibee", "McDonald's", "Bách Hóa Xanh", "WinMart",
            "Co.op Mart", "chợ", "siêu thị", "căng tin", "quán cơm", "nhà hàng", "quán nhậu", "Gong Cha",
            "Mixue", "Pizza Hut", "Haidilao", "Kichi Kichi", "Circle K", "7-Eleven", "GS25",
        ],
        "extra": ["ăn sáng", "ăn trưa", "ăn tối", "ăn khuya", "đi chợ", "liên hoan lớp", "cafe với bạn", "uống nước"],
    },
    "life": {
        "income": False,
        "name": "Sinh hoạt",
        "verbs": ["trả", "đóng", "nạp", "thanh toán", "mua", "gia hạn"],
        "items": [
            "tiền điện", "tiền nước", "internet", "wifi", "cước điện thoại", "gói 4G", "thẻ cào", "tiền gas",
            "bình gas", "tiền rác", "phí quản lý", "nước lau nhà", "bột giặt", "nước rửa bát", "giấy vệ sinh",
            "kem đánh răng", "dầu gội", "sữa tắm", "đồ dùng gia đình", "khăn giấy", "pin", "bóng đèn",
            "giặt là", "giặt sấy", "dịch vụ dọn nhà", "Netflix", "Spotify", "YouTube Premium", "iCloud",
            "Google One", "tiền truyền hình",
            "xà phòng", "nước rửa tay", "nước giặt", "nước xả vải", "túi rác", "khăn ướt", "nước tẩy", "giấy ăn",
            "bàn chải", "dao cạo", "băng vệ sinh", "phí thu gom rác", "tiền mạng", "cước wifi",
        ],
        "places": ["EVN", "VNPT", "Viettel", "FPT", "Mobifone", "Vinaphone", "Điện Máy Xanh", "Guardian", "Watsons", "Pharmacity"],
        "extra": ["hóa đơn điện tháng", "hóa đơn nước", "nạp tiền điện thoại", "đóng tiền mạng"],
    },
    "house": {
        "income": False,
        "name": "Nhà cửa",
        "verbs": ["trả", "đóng", "thuê", "sửa", "mua", "lắp"],
        "items": [
            "tiền nhà", "tiền thuê nhà", "tiền phòng", "phòng trọ", "tiền trọ", "tiền cọc nhà", "sửa nhà",
            "sơn nhà", "điều hòa", "tủ lạnh", "máy giặt", "nội thất", "bàn ghế", "giường", "nệm", "rèm cửa",
            "sửa ống nước", "thợ điện", "khóa cửa", "chung cư", "phí gửi xe chung cư", "trả góp nhà",
            "quạt", "quạt điện", "máy lạnh", "kệ", "kệ sách", "tủ quần áo", "tủ giày", "bàn làm việc", "sofa",
            "chăn", "ga giường", "gối", "chăn ga gối", "đệm", "thảm", "nồi cơm điện", "bếp từ", "lò vi sóng",
            "máy lọc nước", "máy hút bụi", "vòi nước", "bồn cầu", "sửa điện nước", "thay ổ khóa", "đồ gia dụng",
            "phí dịch vụ chung cư", "tiền thuê căn hộ",
        ],
        "places": ["IKEA", "Nội thất Hòa Phát", "chủ nhà", "ban quản lý", "Điện Máy Xanh"],
        "extra": ["đóng tiền nhà tháng", "trả tiền phòng trọ", "đặt cọc thuê nhà"],
    },
    "self": {
        "income": False,
        "name": "Bản thân",
        "verbs": ["mua", "đi", "xem", "đăng ký", "học", "cắt", "làm", "chơi", "tặng"],
        "items": [
            "quần áo", "áo", "quần jean", "váy", "giày", "dép", "túi xách", "mỹ phẩm", "son", "nước hoa",
            "cắt tóc", "làm tóc", "làm nail", "spa", "gym", "yoga", "sách", "khóa học", "học tiếng Anh",
            "phim", "vé xem phim", "game", "nạp game", "du lịch", "khách sạn", "vé concert", "quà sinh nhật",
            "quà", "tai nghe", "điện thoại", "laptop", "đồng hồ", "kính", "đồ chơi", "karaoke", "bi-a",
            "massage", "gội đầu", "homestay", "resort", "đặt phòng", "tour du lịch", "vé tham quan", "kem chống nắng",
            "skincare", "làm móng", "đi bơi", "vé bơi", "sân cầu lông", "đá bóng", "thẻ tập", "khóa học online",
            "ứng dụng trả phí", "đồ công nghệ", "phụ kiện điện thoại",
        ],
        "places": ["Shopee", "Lazada", "Tiki", "TikTok Shop", "Uniqlo", "Zara", "CGV", "Lotte Cinema", "Fahasa",
                   "Thế Giới Di Động", "CellphoneS", "Steam", "Agoda", "Traveloka", "30Shine"],
        "extra": ["đi chơi cuối tuần", "đi du lịch Đà Lạt", "mua đồ online", "săn sale"],
    },
    "transport": {
        "income": False,
        "name": "Đi lại",
        "verbs": ["đổ", "đi", "gửi", "trả", "mua", "sửa", "rửa", "thay"],
        "items": [
            "xăng", "đổ xăng", "grab", "taxi", "xe ôm", "gửi xe", "vé xe buýt", "vé xe khách", "vé tàu",
            "vé máy bay", "sửa xe", "rửa xe", "thay nhớt", "vá xe", "bảo dưỡng xe", "phí cầu đường",
            "vé tháng gửi xe", "đăng kiểm", "bảo hiểm xe", "metro", "xe điện", "be", "gojek",
            "vá lốp", "thay lốp", "thay ắc quy", "phụ tùng xe", "thay dầu", "phí BOT", "trạm thu phí", "phí cao tốc",
            "đỗ xe", "gửi ô tô", "sạc xe điện", "xe ôm công nghệ", "vé tàu hỏa", "phà",
        ],
        "places": ["Petrolimex", "PVOil", "Grab", "Be", "Xanh SM", "Gojek", "Vietjet", "Vietnam Airlines",
                   "Bamboo", "FUTA", "Phương Trang", "Honda Head", "VETC"],
        "extra": ["đi grab về nhà", "bắt taxi ra sân bay", "đổ xăng xe máy", "gửi xe ở trường"],
    },
    "health": {
        "income": False,
        "name": "Sức khỏe",
        "verbs": ["mua", "khám", "đi", "chữa", "nhổ", "tiêm", "xét nghiệm", "đóng"],
        "items": [
            "thuốc", "thuốc cảm", "khám bệnh", "khám răng", "nhổ răng", "niềng răng", "bệnh viện", "phòng khám",
            "xét nghiệm máu", "vitamin", "thực phẩm chức năng", "khẩu trang", "tiêm vắc xin", "bảo hiểm y tế",
            "bảo hiểm sức khỏe", "kính mắt", "vật lý trị liệu", "siêu âm",
            "khám mắt", "cạo vôi răng", "trám răng", "chụp x quang", "khám da liễu", "nhiệt kế", "thuốc dạ dày",
            "thuốc giảm đau", "băng gạc", "khám thai",
        ],
        "places": ["Long Châu", "Pharmacity", "An Khang", "Vinmec", "bệnh viện Bạch Mai", "Hoàn Mỹ", "nha khoa", "Medlatec"],
        "extra": ["đi khám tổng quát", "mua thuốc ho", "tái khám"],
    },
    "child": {
        "income": False,
        "name": "Con cái",
        "verbs": ["đóng", "mua", "cho", "đưa", "trả"],
        "items": [
            "học phí cho con", "học phí mầm non", "sữa bột", "tã", "bỉm", "đồ chơi cho bé", "quần áo cho bé",
            "tiền ăn bán trú", "học thêm cho con", "sách vở cho con", "đồ dùng học tập", "tiền tiêu vặt cho con",
            "xe đẩy", "trông trẻ", "học bơi cho bé", "đưa đón con", "đồng phục cho con", "sữa cho bé",
            "đồ chơi lego", "bỉm cho con", "học phí tiểu học",
        ],
        "places": ["Con Cưng", "Bibo Mart", "Kids Plaza", "trường mầm non", "trung tâm tiếng Anh"],
        "extra": ["đóng tiền học cho bé", "mua sữa cho con", "tiền ăn của bé"],
    },
    # ---------------- thu nhập ----------------
    "salary": {
        "income": True,
        "name": "Lương",
        "verbs": ["nhận", "được", "lĩnh", "về"],
        "items": ["lương", "lương tháng", "tiền lương", "lương cứng", "lương part-time", "lương thực tập",
                  "lương làm thêm giờ", "tạm ứng lương"],
        "places": ["công ty", "sếp", "kế toán", "trường"],
        "extra": ["lương về", "nhận lương tháng này", "công ty trả lương"],
    },
    "bonus": {
        "income": True,
        "name": "Thưởng",
        "verbs": ["nhận", "được", "trúng", "có"],
        "items": ["thưởng", "thưởng Tết", "thưởng KPI", "thưởng dự án", "lì xì", "tiền mừng tuổi", "học bổng",
                  "hoa hồng", "thưởng tháng 13", "giải thưởng", "tiền quà"],
        "places": ["công ty", "bố mẹ", "ông bà", "trường"],
        "extra": ["được lì xì", "nhận học bổng kỳ này", "thưởng cuối năm"],
    },
    "business": {
        "income": True,
        "name": "Kinh doanh",
        "verbs": ["bán", "thu", "nhận", "chốt"],
        "items": ["bán hàng", "doanh thu", "tiền hàng", "đơn hàng", "khách thanh toán", "bán online", "lãi bán hàng",
                  "tiền ship COD", "bán quần áo", "bán đồ ăn"],
        "places": ["shop", "cửa hàng", "khách", "Shopee", "Facebook", "TikTok"],
        "extra": ["khách chuyển khoản tiền hàng", "chốt đơn", "doanh thu hôm nay"],
    },
    "other_income": {
        "income": True,
        "name": "Thu nhập khác",
        "verbs": ["nhận", "được", "bán", "hoàn"],
        "items": ["làm thêm", "freelance", "dạy kèm", "gia sư", "bán đồ cũ", "hoàn tiền", "cashback",
                  "tiền hoàn thuế", "cho thuê phòng", "trợ cấp", "bố mẹ gửi", "tiền chợ bố mẹ cho", "viết bài"],
        "places": ["Momo", "ZaloPay", "Upwork", "bố mẹ", "khách"],
        "extra": ["nhận tiền dạy kèm", "được hoàn tiền", "bán điện thoại cũ"],
    },
}

TIME_WORDS = ["", "", "", "sáng nay", "trưa nay", "tối qua", "hôm qua", "hôm nay", "chiều nay", "cuối tuần",
              "tối nay", "ngày 5", "15/10", "đầu tháng", "tuần này"]
PEOPLE = ["An", "Bình", "Minh", "Lan", "Hoa", "Tuấn", "Hùng", "Linh", "Trang", "Nam", "Huy", "Mai", "Phương",
          "Đức", "Hải", "Dũng", "Hiếu", "Nhiệm", "mẹ", "bố", "anh Tú", "chị Hà", "em Ngọc", "bạn cùng phòng"]
COMPANIONS = ["", "", "", "với bạn", "cùng đồng nghiệp", "với gia đình", "với người yêu", "cho cả nhà", "cùng lớp"]
AMOUNTS = ["", "", "20k", "35k", "45k", "50.000", "60k", "100k", "120k", "150.000", "200k", "350k", "500k",
           "1tr", "1tr2", "1,5tr", "2 triệu", "3tr", "5 triệu", "15tr", "25k", "70.000", "80k"]

# Ý định (loại giao dịch) cho mô hình NLU.
INTENT_TEMPLATES = {
    "expense": ["{item} {amount}", "{verb} {item} {amount} {time}", "chi {amount} cho {item}", "trả tiền {item} {amount}",
                "{time} {verb} {item} hết {amount}", "mua {item} ở {place} {amount}", "thanh toán {item} {amount}"],
    "income": ["nhận {item} {amount}", "{item} về {amount}", "được {item} {amount}", "{place} chuyển {item} {amount}",
               "thu {amount} từ {item}", "{item} tháng này {amount}", "vừa nhận {amount} tiền {item}"],
    "transfer": ["chuyển {amount} sang ví tiết kiệm", "nạp {amount} vào ví {wallet}", "chuyển tiền từ {wallet} sang {wallet2} {amount}",
                 "rút {amount} từ ngân hàng ra tiền mặt", "nạp tiết kiệm {amount}", "chuyển {amount} vào {wallet}",
                 "rút tiền mặt {amount}", "để dành {amount} vào heo đất"],
    "lend": ["cho {person} mượn {amount}", "cho {person} vay {amount}", "{person} mượn {amount}", "ứng cho {person} {amount}",
             "cho {person} mượn tiền {amount} {time}", "trả hộ {person} {amount}"],
    "borrow": ["mượn {person} {amount}", "vay {person} {amount}", "vay của {person} {amount}", "mượn tiền {person} {amount}",
               "{person} cho mình mượn {amount}", "vay ngân hàng {amount}", "{person} cho vay {amount}"],
    "repay": ["trả nợ {person} {amount}", "trả {person} {amount} tiền mượn", "trả lại {person} {amount}", "trả tiền vay {person} {amount}",
              "trả góp khoản vay {amount}", "hoàn tiền cho {person} {amount}"],
    "collect": ["{person} trả nợ {amount}", "{person} trả tiền {amount}", "thu nợ {person} {amount}", "đòi nợ {person} được {amount}",
                "{person} trả lại {amount}", "nhận lại tiền {person} mượn {amount}"],
    "interestIncome": ["lãi tiết kiệm {amount}", "nhận lãi {amount}", "tiền lãi ngân hàng {amount}", "{person} trả lãi {amount}",
                       "lãi cho vay {amount}"],
    "interestExpense": ["trả lãi {amount}", "trả lãi vay {amount}", "tiền lãi thẻ tín dụng {amount}", "trả lãi cho {person} {amount}",
                        "đóng lãi ngân hàng {amount}"],
}
WALLETS = ["tiền mặt", "ngân hàng", "Techcombank", "Vietcombank", "MB", "Momo", "ZaloPay", "heo đất", "tiết kiệm"]
